using JuLS, Random, TOML
include(joinpath(@__DIR__,"..","..","competitors","Permutation.jl"))
using .PermutationRoutes
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
    q=evaluate(inv.data,route)
    inv.component==2 && return inv.data.big_m*q.vehicles+q.distance
    units=ceil(Int64,q.error);0<=units<2^52/10000 || error("integral error bound exceeded")
    Float64(units)
end
function J.init!(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    for m in messages;inv.route[m.index]=m.value.value end
    J.FloatFullMessage(invariantvalue(inv,inv.route))
end
function J.eval(inv::RouteInvariant,messages::J.DAGMessagesVector{J.SingleVariableMessage{J.IntDecisionValue}})
    route=copy(inv.route);for m in messages;route[m.index]=m.value.value end
    J.FloatFullMessage(invariantvalue(inv,route))
end
function J.eval(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    route=copy(inv.route);for m in deltas;route[m.index]=m.new_value.value end
    J.FloatDelta(invariantvalue(inv,route)-invariantvalue(inv,inv.route))
end
function J.commit!(inv::RouteInvariant,deltas::J.DAGMessagesVector{J.SingleVariableMoveDelta{J.IntDecisionValue}})
    for m in deltas;inv.route[m.index]=m.new_value.value end
end
J.n_decision_variables(e::PDPTW)=length(e.data.initial)
J.decision_type(::PDPTW)=J.IntDecisionValue
J.generate_domains(e::PDPTW)=[collect(2:J.n_decision_variables(e)+1) for _ in 1:J.n_decision_variables(e)]
(::J.SimpleInitialization)(e::PDPTW)=copy(e.data.initial)
function J.create_dag(e::PDPTW)
    n=J.n_decision_variables(e);dag=J.DAG(n)
    hardvalue=J.add_invariant!(dag,RouteInvariant(e.data,copy(e.data.initial),1);variable_parent_indexes=collect(1:n))
    objective=J.add_invariant!(dag,RouteInvariant(e.data,copy(e.data.initial),2);variable_parent_indexes=collect(1:n))
    hard=J.add_invariant!(dag,J.StaticConstraintInvariant(10000.);invariant_parent_indexes=[hardvalue])
    soft=J.add_invariant!(dag,J.ObjectiveInvariant();invariant_parent_indexes=[objective])
    J.add_invariant!(dag,J.AggregatorInvariant();invariant_parent_indexes=[hard,soft]);dag
end
cpu()=begin
    stamp=Ref{NTuple{2,Clong}}((0,0));ccall(:clock_gettime,Cint,(Cint,Ref{NTuple{2,Clong}}),2,stamp)==0 || error("CPU clock")
    stamp[][1]+stamp[][2]/1e9
end
function build(d,profile)
    pick=profile=="greedy" ? J.GreedyMoveSelection() : J.SimulatedAnnealing()
    J.init_model(PDPTW(d);init=J.SimpleInitialization(),neigh=BatchSwaps(J.SwapNeighbourhood(length(d.initial)),64),pick=FeasiblePick(pick),using_cp=false)
end
struct FeasiblePick{T} <: J.MoveSelectionHeuristic
    delegate::T
end
function J.pick_a_move(h::FeasiblePick,moves::Vector{<:J.MoveEvaluatorOutput};rng=Random.default_rng())
    feasible=filter(J.isfeasible,moves)
    isempty(feasible) ? J.DONT_MOVE : J.pick_a_move(h.delegate,feasible;rng)
end
struct BatchSwaps <: J.NeighbourhoodHeuristic
    delegate::J.SwapNeighbourhood
    count::Int
end
function J.get_neighbourhood(h::BatchSwaps,m::J.Model;rng=Random.default_rng())
    [only(J.get_neighbourhood(h.delegate,m;rng)) for _ in 1:h.count]
end
function solve(input,budget,seed,profile)
    GC.gc();origin=time_ns();c=cpu();d=read_common(input);m=build(d,profile)
    elapsed()=(time_ns()-origin)/1e9
    events=Any[];best=(typemax(Int),Inf);iterations=0;rng=Xoshiro(seed)
    function observe()
        m.best_solution===nothing && return
        values=Int[v.value for v in m.best_solution.values];q=evaluate(d,values)
        iszero(q.error) || error("native stored feasibility disagrees with full score")
        (q.vehicles,q.distance)<best && elapsed()<=budget || return
        best=(q.vehicles,q.distance)
        push!(events,Dict("seconds"=>elapsed(),"vehicles"=>q.vehicles,"distance"=>q.distance,"values"=>values))
    end
    observe();build_seconds=elapsed()
    while elapsed()<budget
        J.size_hint!(m,1);J.optimize_one_iteration!(m,J.Move;rng);iterations+=1;observe()
    end
    current=evaluate(d,Int[v.value for v in m.current_solution.values])
    iszero(current.error)==m.current_solution.feasible || error("current native feasibility mismatch")
    wall=elapsed();consumed=cpu()-c
    Dict("seed"=>seed,"trajectory"=>events,"iterations"=>iterations,"wall_seconds"=>wall,
        "process_cpu_seconds"=>consumed,"mean_active_cpus"=>consumed/wall,"build_seconds"=>build_seconds)
end
function qualify(input)
    d=read_common(input);m=build(d,"greedy");rng=Xoshiro(0);checks=0
    for _ in 1:100
        a,b=randperm(rng,length(d.initial))[1:2]
        move=J.Move(m.decision_variables[[a,b]],J.IntDecisionValue[m.current_solution.values[b],m.current_solution.values[a]])
        candidate=Int[v.value for v in m.current_solution.values];candidate[a],candidate[b]=candidate[b],candidate[a]
        expected=evaluate(d,candidate);evaluated=J.eval(m.dag,move)
        J.isfeasible(evaluated)==iszero(expected.error) || error("candidate delta feasibility mismatch")
        if J.isfeasible(evaluated)
            before=evaluate(d,Int[v.value for v in m.current_solution.values])
            change=d.big_m*(expected.vehicles-before.vehicles)+expected.distance-before.distance
            isapprox(J.delta_obj(evaluated),change;atol=1e-7,rtol=1e-12) || error("candidate objective delta mismatch")
            J.apply_move!(m,J.MoveEvaluatorOutput(evaluated))
        end
        q=evaluate(d,Int[v.value for v in m.current_solution.values])
        iszero(q.error)==m.current_solution.feasible || error("delta feasibility mismatch")
        checks+=1
    end
    checks
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==4 || error("usage: input seconds greedy|annealing output.toml")
    input,seconds,profile,out=ARGS;budget=parse(Float64,seconds)
    profile in ("greedy","annealing") && budget>0 || error("invalid profile or budget")
    checks=qualify(input);for pass in 1:2;solve(input,1.,0,profile) end
    result=Dict{String,Any}("schema"=>"li-lim-juls-native/1","julia"=>string(VERSION),
        "threads"=>Threads.nthreads(),"budget_seconds"=>budget,"profile"=>profile,"qualification_checks"=>checks,
        "seed_controlled"=>true,"parallelism"=>"native parallel move evaluation","constraint_penalty"=>10000.,
        "neighbourhood"=>"adapter batch of 64 native random swap proposals",
        "selection_guard"=>"exclude infeasible early-stopped moves before native greedy/annealing selection",
        "error_units"=>"ceil(total violation), exact-zero preserving","trials"=>Any[])
    for seed in (41,42,43)
        push!(result["trials"],solve(input,budget,seed,profile));open(io->TOML.print(io,result;sorted=true),out,"w")
    end
end
