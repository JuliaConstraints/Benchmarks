# Reproducible diagnostics, separate from the frozen quality campaign.
const STDLIB_LOAD=@timed @eval using TOML, SHA, Dates, Statistics, LinearAlgebra, Random, Profile
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim","config","icn-threads.toml"))
const BASELINE=TOML.parsefile(joinpath(ROOT,"LiLim","config","current-pilot.toml"))
const COHORT_PATH=get(ENV,"LILIM_DIAGNOSTIC_COHORT","")
const COHORT=isempty(COHORT_PATH) ? BASELINE["cohort"] : TOML.parsefile(COHORT_PATH)["cohort"]
const EVENTS=Any[]
const SNOOP_TIMINGS=Any[]
length(ARGS)==2 && ARGS[1] in ("startup","throughput","snoop") || error("usage: icn_performance.jl startup|throughput|snoop output.toml")
if ARGS[1]=="snoop"
    push!(LOAD_PATH,joinpath(ROOT,"LiLim","perfcheck"))
    @eval using SnoopCompileCore
    @eval function snooped_call(f)
        stats=nothing
        tree=SnoopCompileCore.@snoop_inference begin
            stats=@timed Base.invokelatest(f)
        end
        stats,tree
    end
end
digest(path)=bytes2hex(sha256(read(path)))
function measure(name,f;sample=1,extra=Dict{String,Any}())
    GC.gc()
    stats=if ARGS[1]=="snoop"
        captured,tree=snooped_call(f)
        push!(SNOOP_TIMINGS,(;name,sample,tree))
        captured
    else
        @timed Base.invokelatest(f)
    end
    record=merge(Dict("phase"=>name,"sample"=>sample,"seconds"=>stats.time,
        "allocated_bytes"=>stats.bytes,"gc_seconds"=>stats.gctime,
        "compile_seconds"=>stats.compile_time,"recompile_seconds"=>stats.recompile_time),extra)
    push!(EVENTS,record)
    println(name," #",sample,": ",round(stats.time;digits=4)," s; GC ",round(stats.gctime;digits=4)," s; compile ",round(stats.compile_time;digits=4)," s");flush(stdout)
    stats.value,record
end
const OUT=abspath(ARGS[2]);ispath(OUT) && error("output exists")
string(VERSION)==CONFIG["julia"] && BLAS.get_num_threads()==1 || error("runtime differs")
for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
    digest(joinpath(dirname(Base.active_project()),file))==BASELINE["environment"][key] || error("environment changed")
end
for (name,head) in COHORT
    repo=joinpath(homedir(),".julia","dev",name)
    strip(read(`git -C $repo rev-parse HEAD`,String))==head || error("cohort changed: $name")
    isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) || error("dirty dependency: $name")
end
const META=Dict("schema"=>"li-lim-performance-diagnostic/1","mode"=>ARGS[1],"julia"=>string(VERSION),
    "started_utc"=>string(now(UTC)),"threads"=>Threads.nthreads(),"gc_threads"=>Threads.ngcthreads(),
    "julia_gc_option"=>string(Base.JLOptions().nmarkthreads),"cpu_name"=>Sys.CPU_NAME,
    "affinity"=>only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status"))),
    "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),"baseline"=>BASELINE,
    "measured_cohort"=>COHORT,"cohort_override_sha256"=>isempty(COHORT_PATH) ? "" : digest(COHORT_PATH),
    "profile_source_sha256"=>digest(@__FILE__),"config"=>CONFIG,
    "stdlib_loading_seconds"=>STDLIB_LOAD.time,"gc_precollection"=>"full GC before each measured phase, excluded from phase timing")
measure("load ConstraintModels",()->Core.eval(Main,:(using ConstraintModels)))
measure("load JuMP and Benchmarks",()->Core.eval(Main,:(using JuMP, ConstraintModels.Benchmarks)))
for source in ("Pilot","MetaRepair","ICNScoring","Hybrid","ResourceExperiment")
    measure("include "*source,()->include(joinpath(ROOT,"LiLim","src",source*".jl")))
end
META["solver_source_sha256"]=Dict(relpath(path,ROOT)=>digest(path) for path in readdir(joinpath(ROOT,"LiLim","src");join=true) if endswith(path,".jl"))
const BANKS,_=measure("decode error backends",()->Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:icn,:direct)))
BANKS[:icn].bank_sha256==CONFIG["icn_bank_sha256"] || error("bank changed")

function synthetic(f)
    mktemp() do path,io
        write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
        f(path)
    end
end
function case_details!(event,r)
    r["original_validation"] || error("invalid diagnostic result")
    event["mean_active_cpus"]=r["mean_active_cpus"]
    event["process_cpu_seconds"]=r["process_cpu_seconds"]
    event["pair_candidates"]=sum(get(w["trace"],"pair_candidates",0) for w in r["workers"])
    event["steps"]=sum(get(w["trace"],"steps",0) for w in r["workers"])
    event["candidates_per_second"]=event["pair_candidates"]/r["budget_seconds"]
    event["vehicles"]=r["vehicles"];event["distance"]=r["distance"]
    event["icn_calls"]=sum(w["error_backend"]["icn_decoder_calls"] for w in r["workers"])
    event["repair_calls"]=sum(length(get(w["trace"],"repairs",Any[])) for w in r["workers"])
    event["median_parent_initialization_seconds"]=median(get(w["trace"],"initialization_seconds",0.) for w in r["workers"])
    event["workers"]=[Dict("worker"=>w["worker"],"os_thread_id"=>w["os_thread_id"],
        "julia_thread_id"=>w["julia_thread_id"],"thread_cpu_seconds"=>w["thread_cpu_seconds"],
        "search_wall_seconds"=>w["finished_seconds"]-w["started_seconds"],
        "cpu_fraction"=>w["thread_cpu_seconds"]/(w["finished_seconds"]-w["started_seconds"]),
        "pair_candidates"=>get(w["trace"],"pair_candidates",0),
        "icn_calls"=>w["error_backend"]["icn_decoder_calls"]) for w in r["workers"]]
    nothing
end
function startup()
    synthetic() do path
        methods=copy(CONFIG["methods"])
        Threads.nthreads()>=4 && append!(methods,CONFIG["portfolio_methods"])
        for pass in 1:2,method in methods
            r,e=measure("warmup "*method,()->ResourceExperiment.run_case(path,method,2.,41,CONFIG["policy"],BANKS);sample=pass)
            case_details!(e,r)
        end
    end
    p,_=measure("read lrc101",()->read_benchmark(joinpath(ROOT,"LiLim","data","raw","pdp_100","lrc101.txt"),:li_lim;id="lrc101"))
    initial,_=measure("common insertion lrc101",()->Pilot.insertion(p;starts=5,seed=41))
    for kind in (:naive,:icn,:direct),sample in 1:4
        parent,_=measure("prepare parent "*string(kind),()->Hybrid.prepare_parent(p,initial;seed=41,
            scorer=kind==:direct ? nothing : ICNScoring.clone_backend(BANKS[kind]));sample)
        iszero(Hybrid.LS.get_error(parent.solver.state)) || error("prepared parent infeasible")
    end
    workers=ResourceExperiment.allocation(Threads.nthreads()>=4 ? "mixed_balanced" : "cbls_icn",Threads.nthreads())
    plan=nothing
    for sample in 1:6
        plan,_=measure("prepare MetaStrategist plan",()->ResourceExperiment.prepare_portfolio(workers);sample)
    end
    # The prepared phase only contains immutable worker labels. Mutable records
    # and invocation captures belong to the fresh context, not the reused plan.
    for sample in 1:6
        invoke=(i,worker)->(sample,i,worker)
        context=ResourceExperiment.ExecutionContext(invoke,Vector{Any}(undef,length(workers)))
        measure("reuse MetaStrategist kernel",()->ResourceExperiment.MS.execute!(plan.prepared.kernel,context);sample)
        context.records==[(sample,i,worker) for (i,worker) in enumerate(workers)] || error("reused plan leaked state")
    end
    groups=Hybrid.route_groups(initial,20);isempty(groups) && error("no qualified fragment")
    group=first(groups);ids=sort!([node-1 for route in group for node in initial[route]])
    snapshot,_=measure("capture route snapshot",()->MetaRepair.RouteSnapshot(p,initial))
    variable=Hybrid.LS.MetaVariable(:startup_repair,ids)
    for bridged in (false,true),sample in 1:4
        resolver=MetaRepair.HighsRouteResolver(;bridged,max_visits=20)
        request=Hybrid.LS.MetaVariableRequest(variable,snapshot,0.5,Xoshiro(41))
        outcome,event=measure(bridged ? "bridged RO repair" : "specialized RO repair",()->Hybrid.LS.resolve_meta_variable(resolver,request);sample)
        event["status"]=string(outcome.status);event["repair_trace"]=outcome.trace
    end
end
function throughput()
    synthetic(path->ResourceExperiment.warmup(path,CONFIG["policy"],BANKS))
    path=joinpath(ROOT,"LiLim","data","raw","pdp_100","lc101.txt")
    digest(path)==CONFIG["source_sha256"]["lc101"] || error("instance changed")
    # Warm the actual 106-visit shape before instrumented trials.
    ResourceExperiment.run_case(path,"cbls_icn",1.,41,CONFIG["policy"],BANKS)
    for seed in CONFIG["seeds"]
        r,event=measure("hot CBLS ICN lc101",()->ResourceExperiment.run_case(path,"cbls_icn",5.,seed,CONFIG["policy"],BANKS);sample=seed)
        case_details!(event,r)
    end
    if Threads.nthreads()==16 && Base.JLOptions().nmarkthreads==1
        Profile.init(n=4_000_000,delay=0.002);Profile.clear()
        Profile.@profile ResourceExperiment.run_case(path,"cbls_icn",3.,41,CONFIG["policy"],BANKS)
        io=IOBuffer();Profile.print(IOContext(io,:displaysize=>(10000,180));format=:flat,C=true,sortedby=:count,mincount=20)
        META["cpu_profile_flat"]=String(take!(io))
        Profile.Allocs.clear()
        Profile.Allocs.@profile sample_rate=0.00001 ResourceExperiment.run_case(path,"cbls_icn",3.,41,CONFIG["policy"],BANKS)
        sampled=Profile.Allocs.fetch().allocs;counts=Dict{String,Tuple{Int,Int}}()
        for allocation in sampled
            frame=findfirst(f->occursin("/LiLim/src/",string(f.file)),allocation.stacktrace)
            site=frame===nothing ? "outside LiLim" : string(allocation.stacktrace[frame].file,":",allocation.stacktrace[frame].line)
            old=get(counts,site,(0,0));counts[site]=(old[1]+1,old[2]+allocation.size)
        end
        META["allocation_sample_rate"]=0.00001
        META["sampled_allocation_sites"]=[Dict("site"=>site,"count"=>count,"bytes"=>bytes) for (site,(count,bytes)) in sort(collect(counts);by=x->last(x)[2],rev=true)]
        Profile.Allocs.clear()
    end
end
Base.invokelatest(ARGS[1]=="throughput" ? throughput : startup)
if ARGS[1]=="snoop"
    # Load the analysis library after instrumentation to avoid its load-time
    # invalidations contaminating first-call inference measurements.
    @eval using SnoopCompile
    function summarize_snoop(captured)
        rows=Any[]
        function visit(node)
            for child in node.children
                method=Core.MethodInstance(child)
                push!(rows,Dict("method"=>string(method),
                    "exclusive_inference_seconds"=>SnoopCompileCore.exclusive(child;include_llvm=false),
                    "exclusive_with_llvm_seconds"=>SnoopCompileCore.exclusive(child)))
                visit(child)
            end
        end
        visit(captured.tree)
        sort!(rows;by=r->r["exclusive_with_llvm_seconds"],rev=true)
        Dict("phase"=>captured.name,"sample"=>captured.sample,"method_instances"=>length(rows),
            "inference_seconds"=>SnoopCompileCore.inclusive(captured.tree;include_llvm=false),
            "with_llvm_seconds"=>SnoopCompileCore.inclusive(captured.tree),
            "stale_instances"=>length(SnoopCompile.staleinstances(captured.tree)),
            "top_methods"=>first(rows,min(50,length(rows))))
    end
    META["snoopcompile_version"]=string(pkgversion(SnoopCompile))
    META["snoopcompilecore_version"]=string(pkgversion(SnoopCompileCore))
    META["snoop_controller_manifest_sha256"]=digest(joinpath(ROOT,"LiLim","perfcheck","Manifest.toml"))
    META["snoop_note"]="instrumented fresh-session inference and LLVM timing; not an uninstrumented startup-speed comparison; compiler per-method durations are quantized"
    META["snoop_phases"]=[Base.invokelatest(summarize_snoop,c) for c in SNOOP_TIMINGS]
end
META["finished_utc"]=string(now(UTC));META["events"]=EVENTS
mkpath(dirname(OUT));open(io->TOML.print(io,META;sorted=true),OUT,"w")
println("Saved performance diagnostic: ",OUT)
