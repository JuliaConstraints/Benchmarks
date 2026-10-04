module CompetitorAdapters
using TOML, SHA
using ..Benchmarks, ..Pilot
export export_common_start, audit_timefold, audit_hexaly, audit_hexaly_trial, hexaly_command

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
    `taskset --cpu-list $(join(cpus,',')) $executable $model inFileName=$input solFileName=$output trajectoryFileName=$trajectory trialStartEpochMilliseconds=$trial_start_epoch_ms totalWallBudgetSeconds=$seconds hxTimeLimit=$phase_limits hxNbThreads=$threads hxSeed=$seed hxTimeBetweenDisplays=$display_interval`
end
end
