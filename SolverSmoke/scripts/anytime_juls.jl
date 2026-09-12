include(joinpath(@__DIR__,"..","..","Solvers","scripts","resources.jl"))
using JuLS,Random,TOML
include("../src/Anytime.jl");using .Anytime
const J=JuLS
struct PDPTW <: J.Experiment
    data::RouteData
end
mutable struct RouteInvariant <: J.Invariant
    data::RouteData
    route::Vector{Int}
    component::Int
end
function invariantvalue(inv,route)
    value=evaluate(inv.data,route)[inv.component]
    inv.component==2 && return value
    units=ceil(Int64,value)
    0<=units<2^52/10000 || error("Integral error bound exceeded")
    Float64(units)
end
function J.init!(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    for m in messages;inv.route[m.index]=m.value.value;end
    J.FloatFullMessage(invariantvalue(inv,inv.route))
end
function J.eval(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    route=copy(inv.route)
    for m in messages;route[m.index]=m.value.value;end
    J.FloatFullMessage(invariantvalue(inv,route))
end
function J.eval(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    route=copy(inv.route)
    for m in deltas;route[m.index]=m.new_value.value;end
    J.FloatDelta(invariantvalue(inv,route)-invariantvalue(inv,inv.route))
end
function J.commit!(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    for m in deltas;inv.route[m.index]=m.new_value.value;end
end
J.n_decision_variables(e::PDPTW)=size(e.data.nodes,1)+e.data.fleet-2
J.decision_type(::PDPTW)=J.IntDecisionValue
J.generate_domains(e::PDPTW)=[collect(2:J.n_decision_variables(e)+1) for _ in 1:J.n_decision_variables(e)]
(::J.SimpleInitialization)(e::PDPTW)=collect(2:J.n_decision_variables(e)+1)
function J.create_dag(e::PDPTW)
    n=J.n_decision_variables(e);dag=J.DAG(n)
    hardvalue=J.add_invariant!(dag,RouteInvariant(e.data,collect(2:n+1),1);variable_parent_indexes=collect(1:n))
    objective=J.add_invariant!(dag,RouteInvariant(e.data,collect(2:n+1),2);variable_parent_indexes=collect(1:n))
    hard=J.add_invariant!(dag,J.StaticConstraintInvariant(10000.);invariant_parent_indexes=[hardvalue])
    soft=J.add_invariant!(dag,J.ObjectiveInvariant();invariant_parent_indexes=[objective])
    J.add_invariant!(dag,J.AggregatorInvariant();invariant_parent_indexes=[hard,soft]);dag
end
function solve_case(input,seconds,seed)
    Random.seed!(seed);t=Trace();d=read_routes(input);e=PDPTW(d);n=J.n_decision_variables(e)
    # Full permutation, native swap neighborhood, explicit greedy selection, no CP filter.
    m=J.init_model(e;init=J.SimpleInitialization(),neigh=J.SwapNeighbourhood(n),pick=J.GreedyMoveSelection(),using_cp=false)
    observer=s->observe!(t,s.objective,Int[v.value for v in s.values])
    isnothing(m.best_solution) || observer(m.best_solution)
    J.BENCHMARK_INCUMBENT_OBSERVER[]=observer
    t.solve_origin=time_ns();build=(t.solve_origin-t.origin)/1e9
    try
        J.optimize!(m;limit=J.TimeLimit(seconds),rng=Xoshiro(seed))
    finally
        J.BENCHMARK_INCUMBENT_OBSERVER[]=nothing
    end
    elapsed=(time_ns()-t.solve_origin)/1e9
    current=Int[v.value for v in m.current_solution.values]
    iszero(first(evaluate(d,current)))==m.current_solution.feasible || error("JuLS stored feasibility disagrees with recomputation")
    t,build,elapsed
end
input,budget,seed,out,warm=ARGS
for _ in 1:2;solve_case(warm,2.,0);end
t,build,elapsed=solve_case(input,parse(Float64,budget),parse(Int,seed))
save_trace(out,t;engine="juls_native",profile="greedy_swap",budget_seconds=parse(Float64,budget),seed=parse(Int,seed),
    build_seconds=build,solve_call_seconds=elapsed,threads=4,seed_controlled=true,
    constraint_penalty=10000.,error_unit="ceil(total violation), exact-zero preserving",julia_version=string(VERSION),
    warmup_solves=2,warmup_budget_seconds=2.)
