include("activate.jl")
using JuMP,HiGHS,TOML
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../../LiLim/src/Pilot.jl")
function solve_case(input,seconds,seed)
    t=Trace();d=read_routes(input);nodes=d.nodes
    p=Benchmarks.BenchmarkInstance("full-fleet",Benchmarks.PickupDeliveryProblem(d.fleet,d.capacity,nodes[:,2:3],Int.(nodes[:,4]),
        nodes[:,5],nodes[:,6],nodes[:,7],[(Int(nodes[i,8]),i) for i in 2:size(nodes,1) if nodes[i,8]>0]))
    f=Pilot.model(p;threads=4,seed=seed,seconds=seconds);m=f.m
    @objective(m,Min,d.big_m*f.fleet+f.distance)
    JuMP.MOI.Utilities.attach_optimizer(JuMP.backend(m))
    columns=Dict(a=>JuMP.optimizer_index(v).value for (a,v) in f.x)
    function callback(kind::Cint,message::Ptr{Cchar},data::HiGHS.HighsCallbackDataOut)::Cint
        data.mip_solution==C_NULL && return Cint(0)
        arcs=[a for (a,column) in columns if unsafe_load(data.mip_solution,column)>.5]
        next=Dict(i=>j for (i,j) in arcs if i!=1);routes=Vector{Int}[]
        for first in sort([j for (i,j) in arcs if i==1])
            route=Int[];i=first
            while i!=1
                i in route && error("Cycle in HiGHS incumbent")
                push!(route,i);i=get(next,i,0);i==0 && error("Incomplete HiGHS incumbent")
            end
            push!(routes,route)
        end
        values=Int[];separator=size(nodes,1)+1
        for (i,r) in enumerate(routes)
            append!(values,r);i<length(routes) && (push!(values,separator);separator+=1)
        end
        append!(values,separator:size(nodes,1)+d.fleet-1)
        observe!(t,data.objective_function_value,values)
        return Cint(0)
    end
    set_attribute(m,HiGHS.CallbackFunction([HiGHS.kHighsCallbackMipImprovingSolution]),callback)
    t.solve_origin=time_ns();build=(t.solve_origin-t.origin)/1e9;optimize!(m)
    elapsed=(time_ns()-t.solve_origin)/1e9
    metadata=Dict("engine"=>"highs_control","profile"=>"compact_mip","budget_seconds"=>seconds,"seed"=>seed,
        "threads"=>4,"seed_controlled"=>true,"build_seconds"=>build,"solve_call_seconds"=>elapsed,
        "status"=>string(termination_status(m)),"optimality_proved"=>termination_status(m)==JuMP.MOI.OPTIMAL,
        "final_has_solution"=>has_values(m))
    if termination_status(m)==JuMP.MOI.OPTIMAL
        metadata["proof_seconds_upper_bound"]=elapsed
    end
    # Do not fabricate a discovery event when presolve returned a solution without callback.
    if has_values(m) && isempty(t.events)
        metadata["discovery_callback_missing"]=true
        metadata["final_routes"]=Pilot.decode(f)
    end
    t,metadata
end
input,budget,seed,out,warm=ARGS
solve_case(warm,.1,0)
t,metadata=solve_case(input,parse(Float64,budget),parse(Int,seed))
save_trace(out,t;[Symbol(k)=>v for (k,v) in metadata]...)
