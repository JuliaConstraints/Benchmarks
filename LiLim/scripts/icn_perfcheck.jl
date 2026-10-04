# PerfChecker controller stays outside the frozen solver environment.
using PerfChecker, TOML, SHA, Dates
length(ARGS)==2 || error("usage: icn_perfcheck.jl label output.toml")
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const ENVIRONMENT=joinpath(homedir(),".julia","dev","ConstraintModels","perf","pdptw")
const OUT=abspath(ARGS[2]);ispath(OUT) && error("output exists")
digest(path)=bytes2hex(sha256(read(path)))
const SOURCES=Dict(relpath(path,ROOT)=>digest(path) for path in readdir(joinpath(ROOT,"LiLim","src");join=true) if endswith(path,".jl"))
const RESULT=Dict{String,Any}("schema"=>"li-lim-perfchecker/1","label"=>ARGS[1],
    "started_utc"=>string(now(UTC)),"benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),
    "solver_sources_sha256"=>SOURCES,"perfchecker_version"=>string(pkgversion(PerfChecker)),
    "perfchecker_revision"=>"1cc09a98db569b382f91dc10f6a569c1c728b6aa",
    "controller_project_sha256"=>digest(Base.active_project()),
    "controller_manifest_sha256"=>digest(joinpath(dirname(Base.active_project()),"Manifest.toml")),
    "solver_project_sha256"=>digest(joinpath(ENVIRONMENT,"Project.toml")),
    "solver_manifest_sha256"=>digest(joinpath(ENVIRONMENT,"Manifest.toml")),
    "worker_threads"=>1,"gc_threads_environment"=>get(ENV,"JULIA_NUM_GC_THREADS","default"),
    "note"=>"Isolated warmed one-worker ICN search. CPU/wall profiles sample stacks, not CPU occupancy. Allocation-site bytes/counts are sampled and rescaled by PerfChecker; useful CPU and throughput are measured separately.",
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
    const pc_policy=TOML.parsefile(joinpath($ROOT,"LiLim","config","icn-threads.toml"))["policy"]
    const pc_banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:icn,:direct))
    const pc_instance=joinpath($ROOT,"LiLim","data","raw","pdp_100","lc101.txt")
    # Compile the native search on a tiny case before warming the real shape.
    mktemp() do path,io
        write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
        Base.invokelatest(ResourceExperiment.run_case,path,"cbls_icn",2.,41,pc_policy,pc_banks)
    end
    Base.invokelatest(ResourceExperiment.run_case,pc_instance,"cbls_icn",1.,41,pc_policy,pc_banks)
end
const WORKLOAD=quote
    pc_trial=ResourceExperiment.run_case(pc_instance,"cbls_icn",2.,41,pc_policy,pc_banks)
    pc_trial["original_validation"] || error("invalid PerfChecker workload")
    pc_trial["workers"][1]["error_backend"]["icn_decoder_calls"]>0 || error("ICNs were not used")
end
function clean(value)
    value===nothing && return "unavailable"
    value isa NamedTuple || value isa AbstractDict ? Dict(string(k)=>clean(v) for (k,v) in pairs(value)) :
        value isa AbstractVector || value isa Tuple ? [clean(v) for v in value] :
        value isa Union{AbstractString,Number,Bool} ? value : string(value)
end
for backend in (:profile,:wall_profile,:profile_alloc)
    all(digest(joinpath(ROOT,path))==hash for (path,hash) in SOURCES) || error("solver source changed during profiling")
    println("PerfChecker collector: ",backend);flush(stdout)
    config=PerfConfig(backend;path=ENVIRONMENT,prepared_environment=ENVIRONMENT,
        threads=1,repeat=false,quiet=true,process_resources=true,
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
