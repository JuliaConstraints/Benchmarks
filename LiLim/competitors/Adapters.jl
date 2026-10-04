module CompetitorAdapters
using TOML, SHA
using ..Benchmarks, ..Pilot
export export_common_start, audit_timefold, audit_hexaly

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
    output["schema"]=="li-lim-hexaly-native/1" || error("wrong Hexaly schema")
    routes=[Int.(r) for r in output["routes"]]
    validation=validate_solution(p,routes)
    validation.valid || error("Hexaly result violates original problem")
    validation.objective.vehicles==output["vehicles"] || error("Hexaly fleet mismatch")
    isapprox(validation.objective.distance,output["distance"];atol=1e-7,rtol=1e-12) || error("Hexaly distance mismatch")
    validation
end
end
