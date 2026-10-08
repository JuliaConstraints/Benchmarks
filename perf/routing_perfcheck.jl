# Run in the frozen solver project. PerfChecker's dependency-free scenario runtime
# keeps its controller dependencies out of the measured solver environment.
using Profile, TOML, SHA, Dates

function options(args)
    out=Dict{String,String}()
    for arg in args
        startswith(arg,"--") && occursin('=',arg) || error("expected --name=value")
        key,value=split(arg[3:end],'=';limit=2);out[key]=value
    end
    out
end

function runtime_source(opts)
    haskey(opts,"runtime") && return abspath(opts["runtime"])
    path=Base.find_package("PerfChecker")
    if path===nothing
        push!(LOAD_PATH,"@v$(VERSION.major).$(VERSION.minor)")
        try;path=Base.find_package("PerfChecker");finally;pop!(LOAD_PATH);end
    end
    path===nothing && error("PerfChecker is absent; provide --runtime=/path/to/PerfChecker/src/scenario_runtime.jl")
    joinpath(dirname(path),"scenario_runtime.jl")
end

function allocation_frames(events)
    groups=Dict{Tuple{String,Int,String},Tuple{Int,Int}}()
    root=normpath(joinpath(@__DIR__,".."))
    for a in events
        i=findfirst(f->!f.from_c && f.line>0 &&
            (startswith(string(f.file),root) || occursin("LocalSearchSolvers/src/",string(f.file))),a.stacktrace)
        i===nothing && continue
        f=a.stacktrace[i];key=(string(f.file),f.line,string(f.func));old=get(groups,key,(0,0))
        groups[key]=(old[1]+a.size,old[2]+1)
    end
    rows=sort!(collect(groups);by=x->last(x)[1],rev=true)
    [Dict("file"=>relpath(k[1],root),"line"=>k[2],"function"=>k[3],
        "sampled_bytes"=>v[1],"sampled_events"=>v[2]) for (k,v) in rows[1:min(10,end)]]
end

function observation(case,rate;totals_only=false,native=false,warmup_case=case)
    RT=SharedScenarioRuntime
    Base.invokelatest(RT.once,warmup_case) # Warm this strategy, including its actual error backend and master.
    e=Base.invokelatest(RT.prepare,case)
    timed=@timed Base.invokelatest(RT.operation!,e)
    Base.invokelatest(RT.verify!,e)
    timed_state=e.state
    objects=Base.gc_alloc_count(timed.gcstats);events=Any[];native_allocations=nothing;native_cpu=nothing
    if native
        native_result=Base.invokelatest(RT.profile_case,case,1,true)
        native_allocations=native_result["allocation_profile"]
        objects=native_allocations["total_allocations"]
        events=Profile.Allocs.fetch().allocs
        native_cpu=Base.invokelatest(RT.profile_case,case,1,false)
    elseif !totals_only
        e=Base.invokelatest(RT.prepare,case)
        objects=@allocations Base.invokelatest(RT.operation!,e)
        Base.invokelatest(RT.verify!,e)
        e=Base.invokelatest(RT.prepare,case)
        Profile.Allocs.clear()
        Profile.Allocs.@profile sample_rate=rate Base.invokelatest(RT.operation!,e)
        Base.invokelatest(RT.verify!,e)
        events=Profile.Allocs.fetch().allocs
    end
    row=Dict{String,Any}("bytes"=>timed.bytes,"objects"=>objects,"observed_gc_seconds"=>timed.gctime,
        "correctness"=>"passed","sample_rate"=>native ? 1. : totals_only ? 0. : rate,"sampled_events"=>length(events),
        "observation_scope"=>native ? "Native PerfChecker profile/profile_alloc runtime APIs with independent fresh observations; full allocation stacks aggregated" : totals_only ? "Bytes, objects and GC from one uninstrumented operation via @timed.gcstats; no stack sampling" :
            "Independent fresh-state byte, object and sampled-stack observations",
        "allocation_frames"=>allocation_frames(events))
    if native
        row["native_allocation_profile"]=native_allocations
        row["native_cpu_stack_count"]=length(native_cpu["cpu_stacks"])
        row["native_cpu_profile_scope"]=isempty(native_cpu["cpu_stacks"]) ? "No CPU samples: fixed-work operation too short; functional oracle passed" : "Native CPU stacks captured; no scaling conclusion"
    end
    result=timed.value
    workers=result isa NamedTuple && hasproperty(result,:workers) ? result.workers :
        result isa AbstractDict && haskey(result,"workers") ? result["workers"] : nothing
    if workers!==nothing
        counters=("steps","summary_evaluations","unchanged_proposals","completed_resets","tabu_hits","ejection_attempts","accepted_meta_moves","thread_cpu_seconds")
        row["worker_diagnostics"]=[Dict{String,Any}(key=>get(w["trace"],key,0) for key in counters) for w in workers]
    elseif hasproperty(timed_state,:lanes)
        row["worker_diagnostics"]=[Dict("steps"=>l.steps,"completed_resets"=>get(l.trace,"completed_resets",0)) for l in timed_state.lanes]
    end
    if result isa NamedTuple && hasproperty(result,:coordination)
        row["episodes"]=result.coordination["episodes"]
        row["steps_per_worker"]=[w["trace"]["steps"] for w in result.workers]
        row["role_episode_counts"]=result.coordination["role_episode_counts"]
        row["master_resolver_calls"]=get(result.coordination,"master_resolver_calls",0)
    elseif result isa AbstractDict && haskey(result,"search_gc_seconds")
        row["search_gc_seconds"]=result["search_gc_seconds"]
        row["gc_scope"]="Whole-operation GC includes explicit precollection; search_gc_seconds excludes precollection and final audit"
        row["search_wall_seconds"]=result["wall_seconds"]
        row["initial_seconds"]=result["initial_seconds"]
        row["process_cpu_seconds"]=result["process_cpu_seconds"]
        row["operational_mean_active_cpus"]=result["mean_active_cpus"]
        row["telemetry_scope"]="Diagnostic observation only; not a controlled scaling/throughput comparison"
    end
    Profile.Allocs.clear()
    row
end

function main(args)
    opts=options(args);width=parse(Int,get(opts,"width","2"))
    width==Threads.nthreads() || error("--width must match Julia --threads")
    width in (1,2,4) || error("diagnostics support 1/2/4 workers")
    seconds=parse(Float64,get(opts,"seconds","30"));0<seconds<=30 || error("diagnostic cap must be in (0,30] seconds")
    rate=parse(Float64,get(opts,"sample-rate","0.001"));0<rate<=0.01 || error("bounded sampling requires a rate in (0,0.01]")
    haskey(opts,"output") && ispath(abspath(opts["output"])) && error("refusing to overwrite an existing diagnostic")
    runtime=runtime_source(opts);isfile(runtime) || error("missing PerfChecker scenario runtime")
    Base.include(@__MODULE__,runtime)
    Base.include(@__MODULE__,joinpath(@__DIR__,"routing_scenarios.jl"))
    Base.invokelatest(measure,opts,runtime,width,seconds,rate)
end

function measure(opts,runtime,width,seconds,rate)
    panel=StructuredRouting.RoutingPanel
    instance=get(opts,"instance",nothing)
    mode=get(opts,"observations","sampled")
    mode in ("sampled","totals","native") || error("--observations must be sampled, totals or native")
    totals_only=mode=="totals"
    native=mode=="native"
    native && instance!==nothing && error("native full-stack capture is for fixed-work fixtures; use sampled or totals for original instances")
    instance===nothing || isfile(instance) || error("missing original instance")
    methods=Base.invokelatest(panel.expand,split(get(opts,"methods","routing-panel"),','))
    all(id->haskey(panel.CATALOG,id),methods) || error("unknown routing configuration")
    report=Dict{String,Any}("schema"=>"routing-sampled-perfcheck/1","date_utc"=>string(now(UTC)),
        "julia"=>string(VERSION),"workers"=>width,"operation_budget_cap_seconds"=>seconds,
        "collector"=>native ? "Native PerfChecker SharedScenarioRuntime profile/profile_alloc APIs" : totals_only ? "PerfChecker SharedScenarioRuntime + direct @timed allocation/GC totals" : "PerfChecker SharedScenarioRuntime + direct sampled Julia Profile.Allocs",
        "collector_scope"=>native ? "Native full-stack collection at rate 1.0; in-process fresh scenario state, no run_scenarios process orchestration" : totals_only ? "Same-observation process byte/object/GC totals; no native allocation stacks" : "Bounded top application frame aggregation; not the native full-stack profile_alloc collector",
        "oracle"=>"Original Li-Lim validator and actual configured error backend",
        "fixture"=>instance===nothing ? "Three pickup-delivery requests; functional/allocation qualification, not search-quality evidence" :
            "Original Li-Lim instance; bounded pipeline diagnostics, not a comparative campaign",
        "timing_qualification"=>"No timing/scaling conclusions; other chats may be active",
        "sample_scope"=>"Top frames contain raw sampled bytes/events, not exact allocation percentages",
        "runtime_sha256"=>bytes2hex(sha256(read(runtime))),
        "factory_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__,"routing_scenarios.jl")))),
        "source_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__,"../LiLim/src/StructuredRouting.jl")))),
        "ICNScoring_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__,"../LiLim/src/ICNScoring.jl")))),
        "MetaRepair_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__,"../LiLim/src/MetaRepair.jl")))),
        "bank_sha256"=>bytes2hex(sha256(read(ICNScoring.BANK))),
        "solver_project_sha256"=>bytes2hex(sha256(read(Base.active_project()))),
        "solver_manifest_sha256"=>bytes2hex(sha256(read(joinpath(dirname(Base.active_project()),"Manifest.toml")))),
        "config_sha256"=>bytes2hex(sha256(read(panel.CONFIG_PATH))),"strategies"=>Any[])
    if instance!==nothing
        report["instance_name"]=basename(instance);report["instance_sha256"]=bytes2hex(sha256(read(instance)))
    end
    for id in methods
        meta=panel.CATALOG[id].category==:meta
        factory=instance!==nothing ? routing_instance_case : meta ? routing_meta_case : routing_solver_case
        parameters=Dict{String,Any}("method"=>id,"width"=>width,"steps"=>meta ? 8 : 40,"episodes"=>8,"seconds"=>seconds)
        if instance!==nothing
            # Compile the concrete controller on the independently validated small fixture first.
            tiny=Base.invokelatest(meta ? routing_meta_case : routing_solver_case,parameters)
            Base.invokelatest(SharedScenarioRuntime.once,tiny)
            parameters["instance"]=abspath(instance)
        end
        case=Base.invokelatest(factory,parameters)
        warmup_case=if totals_only && instance!==nothing
            warm_parameters=copy(parameters);warm_parameters["seconds"]=min(1.,seconds)
            Base.invokelatest(factory,warm_parameters)
        else;case;end
        row=Base.invokelatest(observation,case,rate;totals_only,native,warmup_case)
        row["method"]=id;row["category"]=meta ? "meta" : "search"
        row["allocation_scope"]=instance!==nothing ? "Complete instance import, insertion, original CBLS/MetaStrategist search and final audit; prepared banks/plan excluded" :
            meta ? "Lane construction plus eight real typed cooperative episodes; prepare/verify excluded" :
            "Forty steps per prepared private lane; prepare/verify excluded"
        push!(report["strategies"],row)
        if haskey(opts,"output")
            output=abspath(opts["output"]);temp,io=mktemp(dirname(output))
            try
                TOML.print(io,report;sorted=true);close(io);mv(temp,output;force=true)
            finally
                isopen(io) && close(io)
                isfile(temp) && rm(temp)
            end
        end
        println(id,": correctness passed; ",row["bytes"]," bytes; ",row["objects"]," objects")
        flush(stdout)
    end
    if !haskey(opts,"output")
        TOML.print(stdout,report;sorted=true)
    end
    report
end

abspath(PROGRAM_FILE)==(@__FILE__) && main(ARGS)
