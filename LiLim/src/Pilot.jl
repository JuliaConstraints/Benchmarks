module Pilot
using JuMP, HiGHS, Random
using ..Benchmarks
import MathOptInterface as MOI

distances(d) = [hypot(d.coordinates[i,1]-d.coordinates[j,1], d.coordinates[i,2]-d.coordinates[j,2])
    for i in eachindex(d.demand), j in eachindex(d.demand)]
route_distance(route, D) = sum(D[i,j] for (i,j) in zip([1;route], [route;1]))
function feasible_route(route, d, D)
    clock=d.earliest[1]; load=0; previous=1
    for i in route
        clock=max(d.earliest[i], clock+d.service[previous]+D[previous,i])
        clock<=d.latest[i]+1e-8 || return false
        load+=d.demand[i]
        0<=load<=d.capacity || return false
        previous=i
    end
    return load==0 && clock+d.service[previous]+D[previous,1]<=d.latest[1]+1e-8
end

"""Small standalone reference, not a CBLS/LocalSearchSolvers implementation."""
function insertion(p; starts=5, seed=1)
    d=p.data; D=distances(d); best=nothing; key=(typemax(Int), Inf)
    for attempt in 1:starts
        pairs=attempt==1 ? sort(d.pairs;by=pq->d.latest[pq[1]]) : shuffle(Xoshiro(seed+attempt-1), d.pairs)
        routes=Vector{Int}[]; failed=false
        for (pickup, delivery) in pairs
            chosen=nothing; delta=Inf
            for (r, route) in enumerate(routes)
                oldcost=route_distance(route,D)
                for a in 1:length(route)+1, b in a+1:length(route)+2
                    candidate=copy(route); insert!(candidate,a,pickup); insert!(candidate,b,delivery)
                    feasible_route(candidate,d,D) || continue
                    change=route_distance(candidate,D)-oldcost
                    if change<delta
                        chosen=(r,candidate); delta=change
                    end
                end
            end
            if chosen===nothing
                candidate=[pickup,delivery]
                if length(routes)==d.vehicles || !feasible_route(candidate,d,D)
                    failed=true; break
                end
                push!(routes,candidate)
            else
                routes[chosen[1]]=chosen[2]
            end
        end
        failed && continue
        validation=validate_solution(p,routes)
        validation.valid || error("insertion result failed independent validation")
        candidatekey=(validation.objective.vehicles,validation.objective.distance)
        if candidatekey<key
            key=candidatekey; best=deepcopy(routes)
        end
    end
    return best
end

"""Vehicle-independent arcs with route labels anchored to each route's first customer.
Unique anchors + equal labels along selected customer arcs enforce same-route pairs.
Order constraints remove all customer-only cycles, even for zero travel times.
No fleet restriction or distance rounding; depot departures count the full fleet.
"""
function model(p; threads=4, seed=1, seconds=30.0, logpath=nothing, pair_bridge=nothing)
    d=p.data; n=length(d.demand); tasks=2:n; D=distances(d)
    arcs=[(i,j) for i in 1:n, j in 1:n if i!=j && d.earliest[i]+d.service[i]+D[i,j]<=d.latest[j]]
    m=Model(HiGHS.Optimizer)
    set_attribute(m,"threads",threads); set_attribute(m,"parallel","on")
    set_attribute(m,"random_seed",seed); set_time_limit_sec(m,seconds)
    isnothing(logpath) || set_attribute(m,"log_file",logpath)
    set_attribute(m,"log_to_console",false)
    x=Dict(a=>@variable(m,binary=true) for a in arcs)
    incoming=[[(i,j) for (i,j) in arcs if j==v] for v in 1:n]
    outgoing=[[(i,j) for (i,j) in arcs if i==v] for v in 1:n]
    @variable(m,d.earliest[i]<=clock[i=tasks]<=d.latest[i])
    @variable(m,0<=load[tasks]<=d.capacity)
    @variable(m,1<=order[tasks]<=n-1)
    @variable(m,1<=label[tasks]<=n-1)
    for i in tasks
        @constraint(m,sum(x[a] for a in incoming[i])==1)
        @constraint(m,sum(x[a] for a in outgoing[i])==1)
    end
    fleet=@expression(m,sum(x[a] for a in outgoing[1]))
    distance=@expression(m,sum(D[i,j]*x[(i,j)] for (i,j) in arcs))
    @constraint(m,fleet<=d.vehicles)
    @constraint(m,fleet==sum(x[a] for a in incoming[1]))
    for (pickup,delivery) in d.pairs
        if pair_bridge === nothing
            @constraint(m,label[pickup]==label[delivery])
        else
            pair_bridge(m, label[pickup], label[delivery], 1:n-1)
        end
        @constraint(m,order[delivery]>=order[pickup]+1)
    end
    for (i,j) in arcs
        a=x[(i,j)]
        if i==1
            lower=d.earliest[1]+d.service[1]+D[1,j]
            @constraint(m,clock[j]>=lower-max(0,lower-d.earliest[j])*(1-a))
            @constraint(m,label[j]-(j-1)<=(n-1)*(1-a))
            @constraint(m,label[j]-(j-1)>=-(n-1)*(1-a))
            L=d.capacity+abs(d.demand[j])
            @constraint(m,load[j]-d.demand[j]<=L*(1-a))
            @constraint(m,load[j]-d.demand[j]>=-L*(1-a))
        elseif j==1
            M=max(0,d.latest[i]+d.service[i]+D[i,1]-d.latest[1])
            @constraint(m,clock[i]+d.service[i]+D[i,1]<=d.latest[1]+M*(1-a))
            @constraint(m,load[i]<=d.capacity*(1-a))
        else
            M=max(0,d.latest[i]+d.service[i]+D[i,j]-d.earliest[j])
            @constraint(m,clock[j]>=clock[i]+d.service[i]+D[i,j]-M*(1-a))
            @constraint(m,order[j]>=order[i]+1-(n-1)*(1-a))
            @constraint(m,label[j]-label[i]<=(n-1)*(1-a))
            @constraint(m,label[j]-label[i]>=-(n-1)*(1-a))
            L=d.capacity+abs(d.demand[j])
            @constraint(m,load[j]-load[i]-d.demand[j]<=L*(1-a))
            @constraint(m,load[j]-load[i]-d.demand[j]>=-L*(1-a))
        end
    end
    @objective(m,Min,fleet)
    return (;m,x,fleet,distance,D,p)
end

function warmstart!(f,routes)
    validate_solution(f.p,routes).valid || error("invalid MIP start")
    d=f.p.data; m=f.m
    for v in values(f.x); set_start_value(v,0.0) end
    for route in routes
        t=d.earliest[1]; load=0; previous=1
        for (position,i) in enumerate(route)
            set_start_value(f.x[(previous,i)],1.0)
            t=max(d.earliest[i],t+d.service[previous]+f.D[previous,i]); load+=d.demand[i]
            set_start_value(m[:clock][i],t); set_start_value(m[:load][i],load)
            set_start_value(m[:order][i],position); set_start_value(m[:label][i],first(route)-1)
            previous=i
        end
        set_start_value(f.x[(previous,1)],1.0)
    end
    # Check all algebraic constraints, independently from route semantics.
    point=Dict(v=>start_value(v) for v in all_variables(m))
    violations=primal_feasibility_report(m,point;atol=1e-6)
    isempty(violations) || error("MIP start violates $(length(violations)) algebraic constraints")
end

function decode(f, selected=[a for (a,v) in f.x if value(v)>0.5])
    successors=Dict(i=>j for (i,j) in selected if i!=1)
    routes=Vector{Int}[]
    for start in sort([j for (i,j) in selected if i==1])
        route=Int[]; node=start
        while node!=1
            node in route && error("cycle in solver output")
            push!(route,node); node=get(successors,node,0)
            node==0 && error("incomplete solver output")
        end
        push!(routes,route)
    end
    validate_solution(f.p,routes).valid || error("solver output failed independent validation")
    return routes
end

"Observe actual HiGHS incumbents, validating them before the caller's deadline."
function observe_incumbents!(f, observe; expired=()->false, rejected=error->throw(error))
    # Synchronize before optimize!: the caching optimizer does not expose
    # optimizer_index during the initial copy-and-optimize callback.
    MOI.Utilities.attach_optimizer(backend(f.m))
    optimizer = unsafe_backend(f.m)
    columns = [(arc,HiGHS.column(optimizer,optimizer_index(variable))+1)
        for (arc,variable) in f.x]
    function callback(kind::Cint, ::Ptr{Cchar}, data::HiGHS.HighsCallbackDataOut)::Cint
        expired() && return Cint(1)
        if kind in (HiGHS.kHighsCallbackMipSolution,HiGHS.kHighsCallbackMipImprovingSolution) &&
                data.mip_solution != C_NULL && data.mip_solution_size > 0
            # HiGHS owns this buffer; do not retain it beyond the callback.
            primal = unsafe_wrap(Vector{Float64},data.mip_solution,Int(data.mip_solution_size);own=false)
            all(pair -> pair[2] <= length(primal),columns) || error("callback column mapping exceeds primal buffer")
            selected = [arc for (arc,column) in columns if primal[column] > 0.5]
            routes = try
                decode(f,selected)
            catch error
                rejected(error)
                nothing
            end
            routes === nothing || observe(routes)
        end
        return Cint(expired())
    end
    set_attribute(f.m,HiGHS.CallbackFunction(Cint[HiGHS.kHighsCallbackMipSolution,
        HiGHS.kHighsCallbackMipImprovingSolution,HiGHS.kHighsCallbackMipInterrupt]),callback)
    nothing
end

function solve!(f; seconds=30.0)
    started=time_ns(); optimize!(f.m)
    phases=Dict{String,Any}[Dict("objective"=>"vehicles","status"=>string(termination_status(f.m)),
        "bound"=>isfinite(objective_bound(f.m)) ? objective_bound(f.m) : "unavailable")]
    solution=has_values(f.m) ? decode(f) : nothing
    if termination_status(f.m)==MOI.OPTIMAL && (seconds-(time_ns()-started)/1e9)>0.05
        optimum=round(Int,value(f.fleet))
        @constraint(f.m,f.fleet==optimum)
        @objective(f.m,Min,f.distance)
        set_time_limit_sec(f.m,seconds-(time_ns()-started)/1e9)
        optimize!(f.m)
        push!(phases,Dict("objective"=>"distance","status"=>string(termination_status(f.m)),
            "bound"=>isfinite(objective_bound(f.m)) ? objective_bound(f.m) : "unavailable"))
        has_values(f.m) && (solution=decode(f))
    end
    return solution,phases,(time_ns()-started)/1e9
end
end
