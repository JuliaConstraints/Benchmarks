module CompetitorAdapters
include("../src/PlatformResources.jl")
using TOML, SHA
using ..Benchmarks, ..Pilot
export export_common_start, audit_timefold, audit_hexaly, audit_hexaly_trial, hexaly_command,
    audit_ortools_trial, ortools_command, ortools_portfolio

"One-based node IDs, depot=1; complete native fleet and an independently validated start."
function export_common_start(io,p,initial)
    validate_solution(p,initial).valid || throw(ArgumentError("invalid common start"))
    d=p.data;n=length(d.demand);pickup=zeros(Int,n)
    for (a,b) in d.pairs;pickup[b]=a end
    println(io,"lilim-common-start/1 ",n," ",d.capacity," ",d.vehicles)
    for i in 1:n
        println(io,join((i,d.coordinates[i,1],d.coordinates[i,2],d.demand[i],
            d.earliest[i],d.latest[i],d.service[i],pickup[i]),' '))
    end
    for i in 1:d.vehicles
        route=i<=length(initial) ? initial[i] : Int[]
        println(io,length(route),isempty(route) ? "" : " "*join(route,' '))
    end
end
function audit_timefold(p,initial,native)
    native["schema"]=="li-lim-timefold-native/1" || error("wrong Timefold schema")
    native["qualification_checks"]>100 || error("incremental scorer was not qualified")
    checked=validate_solution(p,initial);checked.valid || error("invalid fallback")
    trials=Any[]
    for trial in native["trials"]
        best=deepcopy(initial);quality=checked.objective;censored=0;observations=Any[]
        for worker in trial["workers"],event in worker["trajectory"]
            isfinite(event["seconds"]) && event["seconds"]>=0 || error("invalid clock")
            if event["seconds"]>trial["budget_seconds"];censored+=1;continue end
            routes=[Int.(r) for r in event["routes"]]
            validation=validate_solution(p,routes)
            validation.valid || error("Timefold incumbent violates original problem")
            validation.objective.vehicles==event["vehicles"] || error("fleet score mismatch")
            isapprox(validation.objective.distance,event["distance"];atol=1e-7,rtol=1e-12) || error("distance score mismatch")
            push!(observations,merge(event,Dict("routes"=>routes,"worker"=>worker["worker"],
                "distance"=>validation.objective.distance)))
        end
        sort!(observations;by=e->e["seconds"])
        trajectory=Any[Dict("seconds"=>0.,"vehicles"=>quality.vehicles,"distance"=>quality.distance,
            "routes"=>deepcopy(initial),"source"=>"common_start")]
        for event in observations
            if (event["vehicles"],event["distance"])<(quality.vehicles,quality.distance)
                best=deepcopy(event["routes"]);quality=validate_solution(p,best).objective;push!(trajectory,event)
            end
        end
        push!(trials,Dict("seed"=>trial["seed"],"vehicles"=>quality.vehicles,"distance"=>quality.distance,
            "routes"=>best,"trajectory"=>trajectory,"original_validation"=>true,
            "audited_incumbents"=>length(observations),"late_incumbents_censored"=>censored))
    end
    trials
end
"Hexaly exchange format is one-based including depot; do not silently shift IDs."
function audit_hexaly(p,output)
    output["schema"]=="li-lim-hexaly-native/2" || error("wrong Hexaly schema")
    routes=[Int.(r) for r in output["routes"]]
    validation=validate_solution(p,routes)
    validation.valid || error("Hexaly result violates original problem")
    validation.objective.vehicles==output["vehicles"] || error("Hexaly fleet mismatch")
    isapprox(validation.objective.distance,output["distance"];atol=1e-7,rtol=1e-12) || error("Hexaly distance mismatch")
    validation
end
"""Audit OR-Tools' result and each within-budget incumbent against Li-Lim."""
function audit_ortools_trial(p, initial, output; budget_seconds, common_start_seconds=0.,
        engine="routing", workers=1, gls_lambda=0.1)
    isfinite(budget_seconds) && budget_seconds >= 0 ||
        throw(ArgumentError("OR-Tools budget must be finite and nonnegative"))
    isfinite(common_start_seconds) && common_start_seconds >= 0 ||
        throw(ArgumentError("OR-Tools common start must be finite and nonnegative"))
    engine in ("routing","cpsat") || throw(ArgumentError("unknown OR-Tools engine"))
    workers isa Integer && workers >= 1 || throw(ArgumentError("invalid OR-Tools worker count"))
    schema = engine=="routing" ? "li-lim-ortools-native/1" : "li-lim-ortools-cpsat-native/1"
    output["schema"] == schema || error("wrong OR-Tools schema")
    output["ortools_version"] == "9.14.6206" || error("OR-Tools version differs from the frozen baseline")
    output["internal_search_threads"] == workers || error("OR-Tools worker allocation differs")
    if engine=="routing"
        workers==1 || error("Routing workers must be separate processes")
        output["guided_local_search"] || error("OR-Tools profile is not Guided Local Search")
        get(output,"gls_lambda",0.1)==gls_lambda || error("OR-Tools GLS coefficient differs")
    else
        !output["guided_local_search"] && !output["cp_local_search_enabled"] &&
            output["generalized_cp_sat_enabled"] && output["seed_used_by_cp_sat"] ||
            error("OR-Tools CP-SAT profile differs or CP local search is still enabled")
    end
    output["distance_scale"] == 1_000_000 && output["time_scale"] == 10_000 ||
        error("OR-Tools integer scales differ from the frozen model")
    output["seed_used_by_routing_search"] === false || error("OR-Tools default seed policy changed")
    output["objective_policy"] == "lexicographic vehicles then distance using a dominating fixed vehicle cost" ||
        error("OR-Tools objective policy changed")
    final_seconds = Float64(output["seconds"])
    isfinite(final_seconds) && final_seconds >= common_start_seconds || error("invalid OR-Tools final clock")
    solver_seconds = Float64(output["solver_seconds"])
    isfinite(solver_seconds) && 0 <= solver_seconds <= final_seconds + 1e-6 ||
        error("invalid OR-Tools search duration")
    initial_check = validate_solution(p, initial)
    initial_check.valid || error("invalid common-start fallback")
    final_routes = [Int.(route) for route in output["routes"]]
    final_check = validate_solution(p, final_routes)
    final_check.valid || error("OR-Tools final route violates the original Li-Lim problem")
    final_check.objective.vehicles == output["vehicles"] || error("OR-Tools final fleet mismatch")
    isapprox(final_check.objective.distance, output["distance"]; atol=1e-7, rtol=1e-12) ||
        error("OR-Tools final distance mismatch")

    best_routes = deepcopy(initial)
    best = initial_check.objective
    trajectory = Any[]
    censored = 0
    audited_count = 0
    if common_start_seconds <= budget_seconds
        push!(trajectory, Dict("seconds"=>common_start_seconds,"vehicles"=>best.vehicles,
            "distance"=>best.distance,"routes"=>deepcopy(initial),"source"=>"common_start"))
    end
    observations = sort(collect(get(output,"trajectory",Any[])); by=event->event["seconds"])
    for event in observations
        seconds = Float64(event["seconds"])
        isfinite(seconds) && common_start_seconds <= seconds <= final_seconds || error("invalid OR-Tools trajectory clock")
        if seconds > budget_seconds
            censored += 1
            continue
        end
        routes = [Int.(route) for route in event["routes"]]
        checked = validate_solution(p, routes)
        checked.valid || error("OR-Tools trajectory incumbent violates the original Li-Lim problem")
        checked.objective.vehicles == event["vehicles"] || error("OR-Tools trajectory fleet mismatch")
        isapprox(checked.objective.distance, event["distance"]; atol=1e-7, rtol=1e-12) ||
            error("OR-Tools trajectory distance mismatch")
        audited_count += 1
        if (checked.objective.vehicles,checked.objective.distance) < (best.vehicles,best.distance)
            best_routes = deepcopy(routes)
            best = checked.objective
            push!(trajectory, Dict("seconds"=>seconds,"vehicles"=>best.vehicles,
                "distance"=>best.distance,"routes"=>deepcopy(best_routes),"source"=>engine=="routing" ? "ortools_gls" : "ortools_cpsat"))
        end
    end
    if final_seconds > budget_seconds
        censored += 1
    elseif (final_check.objective.vehicles,final_check.objective.distance) < (best.vehicles,best.distance)
        best_routes = deepcopy(final_routes)
        best = final_check.objective
        push!(trajectory, Dict("seconds"=>final_seconds,"vehicles"=>best.vehicles,
            "distance"=>best.distance,"routes"=>deepcopy(best_routes),"source"=>"ortools_final"))
    end
    Dict("routes"=>best_routes,"vehicles"=>best.vehicles,"distance"=>best.distance,
        "trajectory"=>trajectory,"original_validation"=>true,
        "within_budget_feasible"=>!isempty(trajectory),"audited_incumbents"=>audited_count,
        "late_incumbents_censored"=>censored,
        "common_start_accepted"=>Bool(output["common_start_accepted"]))
end

"Launch OR-Tools with an explicit native worker budget and CPU allocation."
function ortools_command(python, script, input, output; seconds, seed, trial_start_epoch_ns, cpus,
        engine="routing", workers=1, gls_lambda=0.1, verify_cpsat=false)
    seconds isa Real && isfinite(seconds) && seconds >= 0 ||
        throw(ArgumentError("OR-Tools time limit must be finite and nonnegative"))
    seed isa Integer && seed > 0 || throw(ArgumentError("OR-Tools trial seed label must be positive"))
    trial_start_epoch_ns isa Integer && trial_start_epoch_ns > 0 ||
        throw(ArgumentError("OR-Tools needs a positive common-start epoch"))
    engine in ("routing","cpsat") || throw(ArgumentError("unknown OR-Tools engine"))
    workers isa Integer && workers >= 1 && length(cpus)==workers && allunique(cpus) &&
        all(c->c isa Integer && c >= 0,cpus) || throw(ArgumentError("workers need distinct allocated CPUs"))
    engine=="routing" && workers!=1 && throw(ArgumentError("Routing uses one CPU per process"))
    gls_lambda isa Real && isfinite(gls_lambda) && gls_lambda>0 || throw(ArgumentError("invalid GLS coefficient"))
    if Sys.islinux()
        all(c->c in PlatformResources.allowed_cpus(),cpus) || throw(ArgumentError("CPU outside current allocation"))
    end
    arguments = verify_cpsat ? ["--verify-cpsat"] : String[]
    command=PlatformResources.pin(`$python $script --input=$input --output=$output --seconds=$seconds --seed=$seed --trial-start-epoch-ns=$trial_start_epoch_ns --engine=$engine --workers=$workers --gls-lambda=$gls_lambda $arguments`,cpus)
    addenv(command,"OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1","OMP_THREAD_LIMIT"=>"1",
        "MKL_NUM_THREADS"=>"1","BLIS_NUM_THREADS"=>"1","VECLIB_MAXIMUM_THREADS"=>"1","NUMEXPR_NUM_THREADS"=>"1")
end

"Independent Routing searches with a common deadline and original-problem audit."
function ortools_portfolio(p,initial,identity;seconds,seed,cpus,
        script=normpath(joinpath(@__DIR__,"..","native","ortools","pdptw.py")),
        coefficients=[isodd(i) ? 0.1/2^((i-1)÷2) : 0.2*2^((i-2)÷2) for i in eachindex(cpus)])
    !isempty(cpus) && allunique(cpus) && length(coefficients)==length(cpus) ||
        throw(ArgumentError("portfolio needs one coefficient and distinct CPU per worker"))
    seconds isa Real && isfinite(seconds) && seconds>=0 || throw(ArgumentError("invalid portfolio budget"))
    mktempdir() do directory
        input=joinpath(directory,"input.txt")
        epoch=round(Int,time()*1e9)
        open(io->export_common_start(io,p,initial),input,"w")
        commands=Cmd[];outputs=String[]
        for i in eachindex(cpus)
            output=joinpath(directory,"worker-$i.toml");push!(outputs,output)
            command=ortools_command(identity["python"],script,input,output;seconds,seed,
                trial_start_epoch_ns=epoch,cpus=[cpus[i]],gls_lambda=coefficients[i])
            path=get(identity,"python_path","")
            isempty(path) || (command=addenv(command,"PYTHONPATH"=>path,"PYTHONNOUSERSITE"=>"1"))
            push!(commands,command)
        end
        processes=Base.Process[]
        try
            for command in commands
                push!(processes,run(pipeline(ignorestatus(command);stdout=devnull,stderr=stderr);wait=false))
            end
            timedwait(()->all(process_exited,processes),seconds+15;pollint=0.02)==:ok ||
                error("OR-Tools portfolio exceeded its supervisor deadline")
            foreach(wait,processes)
            all(success,processes) || error("an OR-Tools portfolio worker failed")
        finally
            for process in processes
                process_exited(process) || kill(process)
                wait(process)
            end
        end
        workers=Any[];observations=Any[]
        for i in eachindex(outputs)
            native=TOML.parsefile(outputs[i])
            audited=audit_ortools_trial(p,initial,native;budget_seconds=seconds,gls_lambda=coefficients[i])
            push!(workers,Dict("worker"=>i,"cpu"=>cpus[i],"native"=>native,"audit"=>audited))
            append!(observations,[merge(event,Dict("worker"=>i)) for event in audited["trajectory"]])
        end
        sort!(observations;by=e->e["seconds"])
        best=validate_solution(p,initial).objective;routes=deepcopy(initial)
        trajectory=Any[Dict("seconds"=>0.,"vehicles"=>best.vehicles,"distance"=>best.distance,
            "routes"=>deepcopy(initial),"source"=>"common_start")]
        for event in observations
            if (event["vehicles"],event["distance"])<(best.vehicles,best.distance)
                routes=deepcopy(event["routes"]);best=validate_solution(p,routes).objective;push!(trajectory,event)
            end
        end
        Dict("workers"=>workers,"routes"=>routes,"vehicles"=>best.vehicles,"distance"=>best.distance,
            "trajectory"=>trajectory,"original_validation"=>true,"budget_seconds"=>seconds,
            "allocation"=>"one process per CPU; native numerical libraries capped at one thread")
    end
end
"""Audit Hexaly's final solution and every within-budget anytime observation."""
function audit_hexaly_trial(p, initial, output, trace; budget_seconds, common_start_seconds=0.)
    budget_seconds isa Real && isfinite(budget_seconds) && budget_seconds >= 0 ||
        throw(ArgumentError("Hexaly budget must be finite and nonnegative"))
    common_start_seconds isa Real && isfinite(common_start_seconds) && common_start_seconds >= 0 ||
        throw(ArgumentError("Hexaly common start must be finite and nonnegative"))
    initial_check = validate_solution(p, initial)
    initial_check.valid || error("invalid common-start fallback")
    output["schema"] == "li-lim-hexaly-native/2" || error("wrong Hexaly schema")
    trace["schema"] == "li-lim-hexaly-trajectory/2" || error("wrong Hexaly trajectory schema")
    parameterization_elapsed = Float64(output["parameterization_elapsed_seconds"])
    remaining_wall = Float64(output["remaining_wall_budget_seconds"])
    search_budget_value = Float64(output["search_budget_seconds"])
    fleet_phase_value = Float64(output["fleet_phase_seconds"])
    distance_phase_value = Float64(output["distance_phase_seconds"])
    all(isfinite, (parameterization_elapsed, remaining_wall, search_budget_value,
        fleet_phase_value, distance_phase_value)) || error("non-finite Hexaly phase budget")
    parameterization_elapsed >= common_start_seconds || error("Hexaly parameterization precedes common-start export")
    isapprox(parameterization_elapsed + remaining_wall, budget_seconds; atol=1e-6, rtol=0) ||
        error("Hexaly remaining wall clock does not match the total budget")
    all(isinteger, (search_budget_value, fleet_phase_value, distance_phase_value)) ||
        error("Hexaly phase budgets must be whole seconds")
    search_budget = Int(search_budget_value)
    fleet_phase = Int(fleet_phase_value)
    distance_phase = Int(distance_phase_value)
    search_budget == max(0, floor(Int, remaining_wall)) ||
        error("Hexaly search budget differs from the remaining common wall time")
    fleet_phase + distance_phase == search_budget || error("Hexaly objective phase budgets do not sum to the search budget")
    expected_fleet_phase = search_budget == 0 ? 0 : max(1, fld(5 * search_budget, 6))
    fleet_phase == expected_fleet_phase || error("Hexaly fleet phase differs from the declared 5:1 policy")
    distance_phase == search_budget - fleet_phase || error("Hexaly distance phase differs from the declared 5:1 policy")
    final_check = audit_hexaly(p, output)
    records = Any[]
    censored = 0
    for event in get(trace, "trajectory", Any[])
        seconds = Float64(event["seconds"])
        isfinite(seconds) && seconds >= common_start_seconds || error("invalid Hexaly trajectory clock")
        if seconds > budget_seconds
            censored += 1
            continue
        end
        routes = [Int.(route) for route in event["routes"]]
        checked = validate_solution(p, routes)
        checked.valid || error("Hexaly trajectory incumbent violates original problem")
        checked.objective.vehicles == event["vehicles"] || error("Hexaly trajectory fleet mismatch")
        isapprox(checked.objective.distance, event["distance"]; atol=1e-7, rtol=1e-12) ||
            error("Hexaly trajectory distance mismatch")
        push!(records, Dict("seconds"=>seconds, "vehicles"=>checked.objective.vehicles,
            "distance"=>checked.objective.distance, "routes"=>routes))
    end
    final_seconds = Float64(get(output, "seconds", Inf))
    isfinite(final_seconds) && final_seconds >= common_start_seconds || error("invalid Hexaly final clock")
    best_routes = deepcopy(initial)
    best = nothing
    trajectory = Any[]
    if common_start_seconds <= budget_seconds
        best = initial_check.objective
        push!(trajectory, Dict("seconds"=>common_start_seconds, "vehicles"=>best.vehicles,
            "distance"=>best.distance, "routes"=>deepcopy(initial), "source"=>"common_start"))
    end
    sort!(records; by=event->event["seconds"])
    for event in records
        if best === nothing || (event["vehicles"], event["distance"]) < (best.vehicles, best.distance)
            best_routes = deepcopy(event["routes"])
            best = (vehicles=event["vehicles"], distance=event["distance"])
            push!(trajectory, merge(event, Dict("source"=>"hexaly_display")))
        end
    end
    if final_seconds > budget_seconds
        censored += 1
    elseif best === nothing ||
        (final_check.objective.vehicles, final_check.objective.distance) < (best.vehicles, best.distance)
        best_routes = deepcopy(output["routes"])
        best = final_check.objective
        push!(trajectory, Dict("seconds"=>final_seconds, "vehicles"=>best.vehicles,
            "distance"=>best.distance, "routes"=>deepcopy(best_routes), "source"=>"hexaly_final"))
    end
    best === nothing && (best=initial_check.objective)
    Dict("routes"=>best_routes, "vehicles"=>best.vehicles, "distance"=>best.distance,
        "trajectory"=>trajectory, "original_validation"=>true,
        "phase_budget"=>Dict("parameterization_elapsed_seconds"=>parameterization_elapsed,
            "remaining_wall_budget_seconds"=>remaining_wall,"search_budget_seconds"=>search_budget,
            "fleet_seconds"=>fleet_phase,"distance_seconds"=>distance_phase),
        "within_budget_feasible"=>!isempty(trajectory),
        "audited_incumbents"=>length(records), "late_incumbents_censored"=>censored)
end
"Build a CLI launch whose HXM model splits the remaining common wall budget 5:1."
function hexaly_command(executable,input,output;threads,seconds,seed,cpus,
    trial_start_epoch_ms, trajectory=output*".trajectory.toml", display_interval=1)
    threads isa Integer && (threads==0 || threads in (1,2,4,8,16)) ||
        throw(ArgumentError("Hexaly thread count must be 0 (automatic) or 1, 2, 4, 8 or 16"))
    !isempty(cpus) && all(cpu->cpu isa Integer && cpu>=0,cpus) && length(unique(cpus))==length(cpus) ||
        throw(ArgumentError("CPU affinity must contain unique nonnegative CPU IDs"))
    (threads==0 || length(cpus)==threads) ||
        throw(ArgumentError("explicit Hexaly thread count must match the CPU affinity width"))
    seconds isa Integer && seconds>=0 && seed isa Integer && seed>=0 ||
        throw(ArgumentError("Hexaly CLI needs integer seconds and a nonnegative seed"))
    trial_start_epoch_ms isa Integer && trial_start_epoch_ms>0 ||
        throw(ArgumentError("Hexaly needs the positive common wall-clock start in epoch milliseconds"))
    display_interval isa Integer && display_interval>0 ||
        throw(ArgumentError("Hexaly display interval must be a positive whole number of seconds"))
    abspath(trajectory)!=abspath(output) || throw(ArgumentError("Hexaly output and trajectory paths must differ"))
    fleet_seconds = seconds==0 ? 0 : max(1, fld(5seconds,6))
    distance_seconds = seconds-fleet_seconds
    phase_limits = string(fleet_seconds, ",", distance_seconds)
    model=normpath(joinpath(@__DIR__,"..","native","hexaly","pdptw.hxm"))
    PlatformResources.pin(`$executable $model inFileName=$input solFileName=$output trajectoryFileName=$trajectory trialStartEpochMilliseconds=$trial_start_epoch_ms totalWallBudgetSeconds=$seconds hxTimeLimit=$phase_limits hxNbThreads=$threads hxSeed=$seed hxTimeBetweenDisplays=$display_interval`,cpus)
end
end
