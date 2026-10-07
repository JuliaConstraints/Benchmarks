"GHOST's Julia MOI wrapper with the existing qualified PDPTW ICNs."
module GHOSTNative
using GHOST, JuMP, TOML, SHA
using ..Benchmarks, ..Pilot, ..MetaRepair, ..ICNScoring
include("PlatformResources.jl")
import MathOptInterface as MOI
const _bank = Ref{Any}(nothing)
function prepared_bank()
    _bank[] === nothing && (_bank[] = ICNScoring.load_backend(:icn))
    _bank[]
end

mutable struct RouteError{P,B}
    problem::P
    backend::B
    distances::Matrix{Float64}
    successors::Vector{Int}
end

function successors!(e::RouteError, permutation)
    n = length(e.successors) + 1
    fill!(e.successors, 1)
    previous = 1
    for node in permutation
        if node > n
            previous > 1 && (e.successors[previous-1] = 1)
            previous = 1
        elseif 2 <= node <= n
            previous > 1 && (e.successors[previous-1] = node)
            previous = node
        else
            return false
        end
    end
    true
end
function score(e::RouteError, values)
    successors!(e, values) || return (error=1., vehicles=typemax(Int), distance=Inf)
    ICNScoring.score(e.backend, e.problem, e.distances, e.successors)
end
(e::RouteError)(values) = Float64(score(e, values).error)

mutable struct RouteObjective{E}
    evaluator::E
    origin::UInt64
    budget::Float64
    fleet_weight::Float64
    best_key::Tuple{Int,Float64}
    best_routes::Vector{Vector{Int}}
    trajectory::Vector{Dict{String,Any}}
    calls::Int
end
elapsed(o::RouteObjective) = (time_ns() - o.origin) / 1e9
function (o::RouteObjective)(values)
    o.calls += 1
    result = score(o.evaluator, values)
    isfinite(result.distance) || return o.fleet_weight * (length(values) + 1)
    key = (result.vehicles, result.distance)
    if iszero(result.error) && key < o.best_key && elapsed(o) <= o.budget
        routes = MetaRepair.routes_from_successors(o.evaluator.problem,o.evaluator.successors)
        routes === nothing && error("ICN feasible permutation could not be decoded")
        checked = validate_solution(o.evaluator.problem, routes)
        checked.valid || error("GHOST ICN zero set disagrees with the original PDPTW validator")
        key = (checked.objective.vehicles, checked.objective.distance)
        if key < o.best_key
            o.best_key = key
            o.best_routes = deepcopy(routes)
            push!(o.trajectory, Dict("seconds"=>elapsed(o), "vehicles"=>key[1],
                "distance"=>key[2], "routes"=>deepcopy(routes), "source"=>"ghost_icn"))
        end
    end
    o.fleet_weight * result.vehicles + result.distance
end

function permutation_start(initial, n, fleet)
    values = Int[]
    for i in 1:fleet
        i <= length(initial) && append!(values, initial[i])
        i < fleet && push!(values, n+i)
    end
    values
end

function lane(p, initial, bank, origin, seconds, initial_seconds; native_seconds_limit=Inf)
    n = length(p.data.demand)
    distances = Pilot.distances(p.data)
    check = validate_solution(p, initial)
    evaluate = RouteError(p, ICNScoring.clone_backend(bank), distances, ones(Int,n-1))
    objective = RouteObjective(deepcopy(evaluate), origin, seconds,
        2n * maximum(distances) + 1., (check.objective.vehicles,check.objective.distance),
        deepcopy(initial), Dict{String,Any}[], 0)
    model = Model(GHOST.Optimizer)
    set_optimizer_attribute(model, "permutation_problem", true)
    set_optimizer_attribute(model, MOI.NumberOfThreads(), 1)
    values = permutation_start(initial, n, p.data.vehicles)
    @variable(model, 2 <= order[1:length(values)] <= length(values)+1, Int)
    set_start_value.(order, values)
    # Permutation moves preserve this invariant; the default wrapper catalog
    # nevertheless supplies its ICN and checks the original AllDifferent set.
    @constraint(model, order in MOI.AllDifferent(length(values)))
    @constraint(model, order in GHOST.Error(evaluate))
    GHOST.set_callback_objective(model, MOI.MIN_SENSE, order, objective)
    remaining = seconds - (time_ns()-origin)/1e9
    remaining <= 0 && return objective
    set_time_limit_sec(model, min(remaining,native_seconds_limit))
    optimize!(model)
    optimizer = unsafe_backend(model)
    state = only(filter(s->s.objective,optimizer.session.callbacks))
    ledger = state.f
    # Final validation is performed by GHOST/MOI and again below. Native final
    # results after the shared deadline do not enter the within-budget ledger.
    ledger
end

"Prepare the actual model, callback and ICN code before comparative trial clocks."
function warmup(path, policy;threads=1,id=nothing)
    p = read_benchmark(path,:li_lim;id=something(id,splitext(basename(path))[1]))
    initial = Pilot.insertion(p;starts=policy["insertion_starts"],seed=policy["insertion_seed"])
    initial === nothing && error("No common GHOST warmup start")
    bank = prepared_bank()
    ledgers = fetch.([Threads.@spawn lane(p,initial,bank,time_ns(),Inf,0.;native_seconds_limit=0.02)
        for _ in 1:threads])
    all(l->l.calls>0,ledgers) || error("GHOST warmup did not invoke the actual objective callback")
    # Compile the same driver/task entry points used by subsequent trials.
    # Its short output is discarded and never treated as comparative evidence.
    Base.invokelatest(run_case,path,3.,41,policy;threads,id)
    nothing
end

"Functional and comparative trials share the original validator and common clock."
function run_case(path, seconds, seed, policy; threads=1, id=nothing)
    threads > 0 && threads <= Threads.nthreads() || error("GHOST lane width exceeds Julia threads")
    origin = time_ns()
    cpu_before = PlatformResources.cpu_seconds()
    gc_before = Base.gc_num()
    p = read_benchmark(path, :li_lim; id=something(id,splitext(basename(path))[1]))
    initial = Pilot.insertion(p; starts=policy["insertion_starts"], seed=policy["insertion_seed"])
    initial === nothing && error("No common feasible insertion start for GHOST")
    checked = validate_solution(p,initial)
    checked.valid || error("Invalid common GHOST start")
    initial_seconds = (time_ns()-origin)/1e9
    initial_seconds <= seconds || error("Common insertion exceeded the GHOST trial budget")
    bank = prepared_bank()
    jobs = [Threads.@spawn lane(p,initial,bank,origin,seconds,initial_seconds) for _ in 1:threads]
    ledgers = fetch.(jobs)
    trajectory = Dict{String,Any}[Dict("seconds"=>initial_seconds,
        "vehicles"=>checked.objective.vehicles,"distance"=>checked.objective.distance,
        "routes"=>deepcopy(initial),"source"=>"common_start")]
    observations = sort!(vcat((l.trajectory for l in ledgers)...);by=e->e["seconds"])
    best = (checked.objective.vehicles,checked.objective.distance)
    best_routes = deepcopy(initial)
    for event in observations
        check = validate_solution(p,event["routes"])
        check.valid || error("GHOST trajectory violates original PDPTW")
        key = (check.objective.vehicles,check.objective.distance)
        key < best || continue
        event["seconds"] <= seconds || error("GHOST ledger contains a late incumbent")
        best=key; best_routes=deepcopy(event["routes"]); push!(trajectory,event)
    end
    wall = (time_ns()-origin)/1e9
    gc = Base.GC_Diff(Base.gc_num(),gc_before)
    Dict{String,Any}("schema"=>"li-lim-resource-trial/1", "instance"=>p.id,
        "method"=>"ghost_icn", "seed"=>seed,"seed_applied_to_search"=>false,
        "source_sha256"=>bytes2hex(sha256(read(path))),
        "budget_seconds"=>seconds,"wall_seconds"=>wall,"outer_elapsed_seconds"=>wall,
        "threads_requested"=>threads,"julia_threads_available"=>Threads.nthreads(),
        "threads_mode"=>"independent GHOST.jl models; one native worker and private ICN workspace per Julia lane",
        "initial_seconds"=>initial_seconds,"initial_vehicles"=>checked.objective.vehicles,
        "initial_distance"=>checked.objective.distance,"vehicles"=>best[1],"distance"=>best[2],
        "routes"=>best_routes,"trajectory"=>trajectory,"original_validation"=>true,
        "audited_incumbents"=>length(observations),"objective_evaluations"=>sum(l.calls for l in ledgers),
        "process_cpu_seconds"=>PlatformResources.cpu_seconds()-cpu_before,
        "mean_active_cpus"=>(PlatformResources.cpu_seconds()-cpu_before)/max(wall,eps()),
        "gc_seconds"=>gc.total_time/1e9,"gc_bytes"=>gc.allocd,
        "reset_counters"=>"not exposed by native ABI", "tabu_counters"=>"not exposed by native ABI")
end
end
