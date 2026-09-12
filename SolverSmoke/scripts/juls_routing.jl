include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using JuLS, Random, TOML
const J=JuLS
struct RoutingExperiment <: J.Experiment
    nodes::Vector{Vector{Float64}}
    capacity::Int
end
function routevalue(e,route)
    error=length(route)-length(unique(route));cost=0.;clock=e.nodes[1][5];load=0.;previous=1;seen=Set{Int}()
    for i in route
        v=e.nodes[i];u=e.nodes[previous];travel=hypot(v[2]-u[2],v[3]-u[3]);cost+=travel
        clock=max(v[5],clock+u[7]+travel);error+=max(0,clock-v[6]);load+=v[4]
        error+=max(0,-load)+max(0,load-e.capacity)
        v[8]>0 && !(Int(v[8]) in seen) && (error+=1)
        push!(seen,i);previous=i
    end
    v=e.nodes[previous];u=e.nodes[1];travel=hypot(v[2]-u[2],v[3]-u[3]);cost+=travel
    error+=max(0,clock+v[7]+travel-u[6])+abs(load)
    return Float64(error),cost
end
mutable struct RouteInvariant <: J.Invariant
    experiment::RoutingExperiment
    route::Vector{Int}
    component::Int
end
function invariantvalue(inv::RouteInvariant,route)
    value=routevalue(inv.experiment,route)[inv.component]
    inv.component==2 && return value
    # JuLS accumulates constraint deltas and tests exact zero. Integral units
    # prevent roundoff from hiding a genuinely feasible route. Travel distances
    # and objective remain Float64; this is only the search's error function.
    units=ceil(Int64,value*1_000_000)
    0<=units*10000<2^52 || error("Exact-penalty bound exceeded")
    Float64(units)
end
function J.init!(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    for m in messages; inv.route[m.index]=m.value.value;end
    J.FloatFullMessage(invariantvalue(inv,inv.route))
end
function J.eval(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    route=copy(inv.route)
    for m in messages;route[m.index]=m.value.value;end
    J.FloatFullMessage(invariantvalue(inv,route))
end
function J.eval(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    route=copy(inv.route)
    for delta in deltas;route[delta.index]=delta.new_value.value;end
    J.FloatDelta(invariantvalue(inv,route)-invariantvalue(inv,inv.route))
end
function J.commit!(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    for delta in deltas; inv.route[delta.index]=delta.new_value.value;end
end
J.n_decision_variables(e::RoutingExperiment)=length(e.nodes)-1
J.decision_type(::RoutingExperiment)=J.IntDecisionValue
J.generate_domains(e::RoutingExperiment)=[collect(2:length(e.nodes)) for _ in 2:length(e.nodes)]
(::J.SimpleInitialization)(e::RoutingExperiment)=collect(2:length(e.nodes))
function J.create_dag(e::RoutingExperiment)
    n=J.n_decision_variables(e);dag=J.DAG(n)
    constraint=J.add_invariant!(dag,RouteInvariant(e,collect(2:n+1),1);variable_parent_indexes=collect(1:n))
    objective=J.add_invariant!(dag,RouteInvariant(e,collect(2:n+1),2);variable_parent_indexes=collect(1:n))
    hard=J.add_invariant!(dag,J.StaticConstraintInvariant(10000.);invariant_parent_indexes=[constraint])
    soft=J.add_invariant!(dag,J.ObjectiveInvariant();invariant_parent_indexes=[objective])
    J.add_invariant!(dag,J.AggregatorInvariant();invariant_parent_indexes=[hard,soft])
    dag
end
input,out=ARGS;mkpath(out)
lines=readlines(input);n,capacity=parse.(Int,split(lines[1]));e=RoutingExperiment([parse.(Float64,split(l)) for l in lines[2:end]],capacity)
checked=0
for route in J.permutations(collect(2:n))
    inv=RouteInvariant(e,copy(route),1)
    for i in 1:n-2,j in i+1:n-1
        deltas=J.DAGMessagesVector([J.SingleVariableMoveDelta(i,J.IntDecisionValue(route[i]),J.IntDecisionValue(route[j])),
            J.SingleVariableMoveDelta(j,J.IntDecisionValue(route[j]),J.IntDecisionValue(route[i]))])
        next=copy(route);next[i],next[j]=next[j],next[i]
        delta=J.eval(inv,deltas).value
        expected=invariantvalue(inv,next)
        @assert invariantvalue(inv,route)*10000+delta*10000==expected*10000
        @assert (expected==0)==(first(routevalue(e,next))==0)
        global checked+=1
    end
end
open(io->TOML.print(io,Dict("checked_transitions"=>checked,"exact_penalty_consistency"=>true)),joinpath(out,"juls-penalty-regression.toml"),"w")
function solveone(seconds,seed)
    Random.seed!(seed);start=time_ns()
    m=J.init_model(e;init=J.SimpleInitialization(),neigh=J.SwapNeighbourhood(n-1),pick=J.GreedyMoveSelection(),using_cp=false)
    build=(time_ns()-start)/1e9
    elapsed=@elapsed J.optimize!(m;limit=J.TimeLimit(seconds),rng=Xoshiro(seed))
    found=!isnothing(m.best_solution)
    route=found ? Int[v.value for v in m.best_solution.values] : Int[]
    current=Int[v.value for v in m.current_solution.values]
    (first(routevalue(e,current))==0)==m.current_solution.feasible || error("JuLS feasibility bookkeeping disagrees with full recomputation")
    Dict("engine"=>"juls_native","found"=>found,"route"=>route,"solve_call_seconds"=>elapsed,"build_seconds"=>build,
        "budget_seconds"=>seconds,"seed"=>seed,"threads"=>4,"julia_version"=>string(VERSION),"using_cp"=>false,
        "neighborhood"=>"SwapNeighbourhood(n)","selection"=>"GreedyMoveSelection","constraint_penalty"=>10000.,
        "error_units_per_unit_violation"=>1_000_000,"final_current_route"=>current,"final_current_recomputed_error"=>first(routevalue(e,current)),
        "final_current_stored_feasible"=>m.current_solution.feasible)
end
solveone(0.25,0)
for seed in 1:3
    result=solveone(2.,seed)
    open(io->TOML.print(io,result;sorted=true),joinpath(out,"juls_native-$seed.toml"),"w")
    println(result);flush(stdout)
end
