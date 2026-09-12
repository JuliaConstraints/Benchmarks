module LiLimSchedule
export thread_configurations, next_stage, observation_key

"Native capabilities; a process with four available CPUs is not four search threads."
function thread_configurations(profiles)
    ready=NamedTuple[];unavailable=NamedTuple[]
    for p in profiles, threads in (1,2,4)
        c=(engine=p.engine,profile=p.profile,threads=threads)
        if p.engine=="timefold_native" && threads!=1
            push!(unavailable,merge(c,(reason="Native multithreaded solving requires Timefold Enterprise; Community installed",)))
        else
            push!(ready,c)
        end
    end
    (;ready,unavailable)
end
observation_key(r)=(r["instance"],r["engine"],r["profile"],r["threads"],r["seed"],r["budget"])

"Decide only after a complete stage, with no unresolved technical failures."
function next_stage(budget,instances,configs,rows;seeds=1:3)
    indexed=Dict{Any,Any}()
    for row in rows
        key=observation_key(row)
        haskey(indexed,key) && error("Duplicate observation; do not merge repeated attempts")
        indexed[key]=row
    end
    stage=Any[]
    for id in instances,c in configs,seed in seeds
        key=(id,c.engine,c.profile,c.threads,seed,budget)
        haskey(indexed,key) || error("Incomplete stage: $key")
        row=indexed[key]
        row["state"] in ("execution_error","resource_censored") && error("Unresolved technical result: $key")
        push!(stage,row)
    end
    if budget<120
        budget in (30,60) || error("Unexpected mandatory budget")
        return (budget=2budget,instances=collect(instances),reason="mandatory stage")
    elseif budget==120
        # This is a global exception: every instance, repetition and supported configuration.
        all(r->r["state"]=="feasible_incumbent",stage) && return (budget=120,instances=String[],reason="all configurations feasible on all instances at 120 seconds")
        return (budget=240,instances=collect(instances),reason="240 seconds required unless complete success at 120")
    end
    budget>=240 && isinteger(log2(budget/30)) || error("Unexpected doubling budget")
    unresolved=filter(instances) do id
        !any(r->r["instance"]==id && r["budget"]<=budget && r["state"]=="feasible_incumbent",rows)
    end
    isempty(unresolved) && return (budget=budget,instances=String[],reason="at least one feasible configuration per instance; entire stage completed")
    budget<=typemax(Int)÷2 || error("Budget overflow")
    (budget=2budget,instances=collect(unresolved),reason="double for instances with no feasible solution in any completed stage")
end
end
