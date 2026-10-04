# Fresh CBLS/ICN controls for the competitor pilot, separate from the 369 trials.
using ConstraintModels, JuMP, TOML, SHA, Dates, LinearAlgebra
using ConstraintModels.Benchmarks
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
for source in ("Pilot","MetaRepair","ICNScoring","Hybrid","ResourceExperiment")
    include(joinpath(ROOT,"LiLim","src",source*".jl"))
end
length(ARGS)==2 || error("usage: competitor_cbls.jl seconds output.toml")
const BUDGET=parse(Float64,ARGS[1]);const OUT=abspath(ARGS[2]);ispath(OUT) && error("output exists")
isfinite(BUDGET) && BUDGET>0 && BLAS.get_num_threads()==1 || error("invalid runtime")
digest(path)=bytes2hex(sha256(read(path)))
const CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim","config","icn-threads.toml"))
const BASELINE=TOML.parsefile(joinpath(ROOT,"LiLim","config","current-pilot.toml"))
const COHORT=TOML.parsefile(joinpath(ROOT,"LiLim","config","workspace-cohort.toml"))["cohort"]
for (name,head) in COHORT
    repo=joinpath(homedir(),".julia","dev",name)
    strip(read(`git -C $repo rev-parse HEAD`,String))==head || error("cohort changed")
    isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) || error("dirty dependency")
end
for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
    digest(joinpath(dirname(Base.active_project()),file))==BASELINE["environment"][key] || error("environment changed")
end
const BANKS=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:icn,:direct))
BANKS[:icn].bank_sha256==CONFIG["icn_bank_sha256"] || error("bank changed")
const RESULT=Dict{String,Any}("schema"=>"li-lim-competitor-cbls-control/1","started_utc"=>string(now(UTC)),
    "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),"cohort"=>COHORT,
    "source_sha256"=>merge(Dict(relpath(p,ROOT)=>digest(p) for p in readdir(joinpath(ROOT,"LiLim","src");join=true) if endswith(p,".jl")),
        Dict(relpath(@__FILE__,ROOT)=>digest(@__FILE__))),"icn_bank_sha256"=>BANKS[:icn].bank_sha256,
    "threads"=>Threads.nthreads(),"gc_threads"=>Threads.ngcthreads(),"budget_seconds"=>BUDGET,"config"=>CONFIG,
    "affinity"=>only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status"))),"trials"=>Any[])
function campaign()
    mktemp() do path,io
        write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
        ResourceExperiment.run_case(path,"cbls_icn",2.,41,CONFIG["policy"],BANKS)
    end
    for id in CONFIG["instances"]
        path=joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt")
        digest(path)==CONFIG["source_sha256"][id] || error("instance changed")
        ResourceExperiment.run_case(path,"cbls_icn",1.,0,CONFIG["policy"],BANKS)
        for seed in CONFIG["seeds"]
            r=ResourceExperiment.run_case(path,"cbls_icn",BUDGET,seed,CONFIG["policy"],BANKS)
            r["original_validation"] || error("invalid control")
            push!(RESULT["trials"],r);RESULT["updated_utc"]=string(now(UTC))
            mkpath(dirname(OUT));open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
            println("CBLS ICN ",id," seed ",seed,": ",r["vehicles"]," / ",r["distance"]);flush(stdout)
        end
    end
end
campaign();RESULT["complete"]=true;open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
