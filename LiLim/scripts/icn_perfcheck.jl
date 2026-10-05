# PerfChecker controller stays outside the frozen solver environment.
using PerfChecker, TOML, SHA, Dates
length(ARGS)==2 || error("usage: icn_perfcheck.jl label output.toml")
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const ENVIRONMENT=joinpath(homedir(),".julia","dev","ConstraintModels","perf","pdptw")
const BASELINE=TOML.parsefile(joinpath(ROOT,"LiLim","config","current-pilot.toml"))
const THREAD_CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim","config","icn-threads.toml"))
const SOURCE_COHORT=TOML.parsefile(joinpath(ROOT,"LiLim","config","workspace-cohort.toml"))["cohort"]
const METHOD=get(ENV,"LILIM_PERFCHECK_METHOD","cbls_icn")
const THREADS=parse(Int,get(ENV,"LILIM_PERFCHECK_THREADS","1"))
const METHOD_BACKENDS=Dict("cbls_icn"=>"icn","cbls_icn_fused_scalar"=>"icn_fused_scalar",
    "cbls_icn_fused_all"=>"icn_fused_all","cbls_direct"=>"direct","cbls_naive"=>"naive")
const MIXED_METHODS=("mixed_balanced","mixed_ls_heavy")
const BACKEND=get(METHOD_BACKENDS,METHOD,"mixed")
METHOD in keys(METHOD_BACKENDS) || METHOD in MIXED_METHODS ||
    error("unsupported LILIM_PERFCHECK_METHOD: $METHOD")
THREADS in THREAD_CONFIG["thread_counts"] || error("unsupported LILIM_PERFCHECK_THREADS: $THREADS")
const COLLECTORS=Symbol[Symbol(x) for x in split(get(ENV,"LILIM_PERFCHECK_COLLECTORS",
    "profile,wall_profile,profile_alloc"),',') if !isempty(x)]
all(x->x in (:profile,:wall_profile,:profile_alloc),COLLECTORS) || error("unknown PerfChecker collector")
const OUT=abspath(ARGS[2]);ispath(OUT) && error("output exists")
digest(path)=bytes2hex(sha256(read(path)))
const SOURCES=Dict(relpath(path,ROOT)=>digest(path) for path in readdir(joinpath(ROOT,"LiLim","src");join=true) if endswith(path,".jl"))
const COHORT=Dict(name=>strip(read(`git -C $(joinpath(homedir(),".julia","dev",name)) rev-parse HEAD`,String))
    for name in keys(SOURCE_COHORT))
for (name,expected) in SOURCE_COHORT
    COHORT[name]==expected || error("development cohort changed: $name")
    repo=joinpath(homedir(),".julia","dev",name)
    isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) ||
        error("development source is dirty: $name")
end
for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
    digest(joinpath(ENVIRONMENT,file))==BASELINE["environment"][key] || error("solver environment changed")
end
const INSTANCE=joinpath(ROOT,"LiLim","data","raw","pdp_100","lc101.txt")
digest(INSTANCE)==BASELINE["source_sha256"]["lc101"] || error("LC101 source changed")
const BANK_SHA256=THREAD_CONFIG["icn_bank_sha256"]
const POLICY=THREAD_CONFIG["policy"]
const RESULT=Dict{String,Any}("schema"=>"li-lim-perfchecker/1","label"=>ARGS[1],
    "method"=>METHOD,"error_backend"=>BACKEND,
    "started_utc"=>string(now(UTC)),"benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),
    "solver_sources_sha256"=>SOURCES,"perfchecker_version"=>string(pkgversion(PerfChecker)),
    "measured_cohort"=>COHORT,
    "perfchecker_revision"=>"1cc09a98db569b382f91dc10f6a569c1c728b6aa",
    "controller_project_sha256"=>digest(Base.active_project()),
    "controller_manifest_sha256"=>digest(joinpath(dirname(Base.active_project()),"Manifest.toml")),
    "controller_source_sha256"=>digest(@__FILE__),
    "solver_project_sha256"=>digest(joinpath(ENVIRONMENT,"Project.toml")),
    "solver_manifest_sha256"=>digest(joinpath(ENVIRONMENT,"Manifest.toml")),
    "worker_threads"=>THREADS,"gc_threads_environment"=>get(ENV,"JULIA_NUM_GC_THREADS","default"),
    "note"=>"Isolated warmed Li-Lim search at the recorded Julia thread count. CPU/wall profiles sample stacks, not CPU occupancy. Allocation-site bytes/counts are sampled and rescaled by PerfChecker; useful CPU and throughput are measured separately.",
    "collectors"=>Any[])
const SETUP=quote
    # The RC copies prepared environments without rebasing relative dev paths.
    # Reactivate the original read-only frozen environment before importing them.
    import Pkg
    Pkg.activate($ENVIRONMENT;io=devnull)
    using ConstraintModels, JuMP, TOML
    using ConstraintModels.Benchmarks
    for source in ("Pilot","MetaRepair","ICNScoring","Hybrid","ResourceExperiment")
        include(joinpath($ROOT,"LiLim","src",source*".jl"))
    end
    const pc_policy=$POLICY
    const pc_banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:icn,:direct))
    pc_banks[:icn].bank_sha256==$BANK_SHA256 || error("ICN bank changed")
    const pc_method=$METHOD
    const pc_threads=$THREADS
    const pc_instance=$INSTANCE
    Threads.nthreads()==pc_threads || error("PerfChecker worker thread count mismatch")
    # Compile the native search on a tiny case before warming the real shape.
    mktemp() do path,io
        write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
        Base.invokelatest(ResourceExperiment.run_case,path,pc_method,2.,41,pc_policy,pc_banks;threads=pc_threads)
    end
    Base.invokelatest(ResourceExperiment.run_case,pc_instance,pc_method,1.,41,pc_policy,pc_banks;threads=pc_threads)
end
const WORKLOAD=quote
    let pc_trial=ResourceExperiment.run_case(pc_instance,pc_method,2.,41,pc_policy,pc_banks;threads=pc_threads)
        pc_trial["original_validation"] || error("invalid PerfChecker workload")
        if $METHOD in ("mixed_balanced","mixed_ls_heavy")
            pc_trial["metastrategist_executed"] && pc_trial["metastrategist_plan_reused"] || error("MetaStrategist plan was not reused")
            cbls_workers=filter(worker->worker["method"]=="cbls_icn",pc_trial["workers"])
            isempty(cbls_workers) && error("MetaStrategist did not execute an ICN CBLS worker")
            all(worker->worker["error_backend"]["backend"]=="icn" && worker["error_backend"]["icn_decoder_calls"]>0,cbls_workers) || error("MetaStrategist ICN scorer was not executed")
        else
            backend=pc_trial["workers"][1]["error_backend"]
            backend["backend"]==$BACKEND || error("unexpected error backend: "*backend["backend"])
            if startswith($BACKEND,"icn")
                backend["icn_decoder_calls"]>0 || error("ICNs were not used")
            else
                backend["icn_decoder_calls"]==0 || error("unexpected ICN execution in non-ICN profile")
            end
        end
    end
end
function clean(value)
    value===nothing && return "unavailable"
    value isa NamedTuple || value isa AbstractDict ? Dict(string(k)=>clean(v) for (k,v) in pairs(value)) :
        value isa AbstractVector || value isa Tuple ? [clean(v) for v in value] :
        value isa Union{AbstractString,Number,Bool} ? value : string(value)
end
for backend in COLLECTORS
    all(digest(joinpath(ROOT,path))==hash for (path,hash) in SOURCES) || error("solver source changed during profiling")
    println("PerfChecker collector: ",backend);flush(stdout)
    config=PerfConfig(backend;path=ENVIRONMENT,prepared_environment=ENVIRONMENT,
        threads=THREADS,repeat=false,quiet=true,process_resources=true,
        profile_seconds=2.,profile_delay=0.002,sample_rate=0.00001,max_profile_stacks=2000)
    captured=PerfChecker.check_function(config,SETUP,WORKLOAD)
    length(captured.tables)==1 || error("unexpected number of profiling workers")
    envelope=only(captured.resource_envelopes)
    push!(RESULT["collectors"],Dict("backend"=>string(backend),
        "rows"=>[clean(row) for row in only(captured.tables)],
        "resources"=>clean(PerfChecker.resource_envelope_dict(envelope)),
        "qualification"=>clean(only(captured.qualifications))))
    RESULT["updated_utc"]=string(now(UTC))
    open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
    println("Saved ",backend," (",length(only(captured.tables))," stacks)");flush(stdout)
end
RESULT["complete"]=true
open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
