module AnytimeValidation
using TOML
using ..Anytime
include("../vendor/formulations/Benchmarks.jl")
export check_trace, fixtures, Benchmarks
function check_trace(input,raw;require_solution=false)
    d=read_routes(input);nodes=d.nodes
    p=Benchmarks.BenchmarkInstance("independent-validation",Benchmarks.PickupDeliveryProblem(d.fleet,d.capacity,nodes[:,2:3],
        Int.(nodes[:,4]),nodes[:,5],nodes[:,6],nodes[:,7],[(Int(nodes[i,8]),i) for i in 2:size(nodes,1) if nodes[i,8]>0]))
    t=TOML.parsefile(raw);events=get(t,"events",[]);previous=Inf;time=-Inf
    get(t,"timing_available",false) || error("Missing observation timing")
    require_solution && isempty(events) && error("No feasible incumbent in qualification fixture: $raw")
    for event in events
        x=event["values"];sort(x)==collect(2:size(nodes,1)+d.fleet-1) || error("Invalid token permutation")
        v=Benchmarks.validate_solution(p,decode(d,x));v.valid || error("Invalid incumbent: $(v.errors)")
        expected=v.objective.vehicles*d.big_m+v.objective.distance
        isapprox(event["objective"],expected;atol=1e-6,rtol=1e-10) || error("Objective disagrees with independent validation")
        event["objective"]<previous || error("Non-improving incumbent event")
        event["elapsed_seconds"]>=time || error("Non-monotonic trace")
        0<=event["solve_seconds"]<=t["solve_call_seconds"]+.1 || error("Invalid discovery time")
        previous=event["objective"];time=event["elapsed_seconds"]
        event["vehicles"]=v.objective.vehicles;event["distance"]=v.objective.distance
        event["within_solve_budget"]=event["solve_seconds"]<=t["budget_seconds"]
    end
    t["found"]==!isempty(events) || error("Found/trace mismatch")
    t["independently_validated"]=true
    t["within_budget_feasible"]=any(e->e["within_solve_budget"],events)
    t["budget_overrun_seconds"]=max(0.,t["solve_call_seconds"]-t["budget_seconds"])
    if !isempty(events)
        t["first_feasible_seconds"]=first(events)["solve_seconds"]
        t["first_feasible_end_to_end_seconds"]=first(events)["elapsed_seconds"]
        t["best_discovery_seconds"]=last(events)["solve_seconds"]
    end
    t
end
function fixtures(directory)
    mkpath(directory)
    # Two pairs, two vehicles: exhaustive 5! token permutations remain cheap.
    data=Benchmarks.PickupDeliveryProblem(2,2,[0. 0.;1. 0.;2. 0.;0. 1.;0. 2.],
        [0,1,-1,1,-1],zeros(5),fill(100.,5),zeros(5),[(2,3),(4,5)])
    p=Benchmarks.BenchmarkInstance("two-pairs-two-vehicles",data)
    path=joinpath(directory,"two-pairs.txt");write_input(path,p)
    path
end
end
