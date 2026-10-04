# Current-cohort pilot: all homogeneous profiles and both actual MetaStrategist mixes.
using ConstraintModels, JuMP, TOML, SHA, Dates, LinearAlgebra
using ConstraintModels.Benchmarks
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
for source in ("Pilot","MetaRepair","ICNScoring","Hybrid","ResourceExperiment")
    include(joinpath(ROOT,"LiLim","src",source*".jl"))
end
length(ARGS)==2 || error("usage: all_variants.jl seconds new-output.toml")
const BUDGET=parse(Float64,ARGS[1]);const OUT=abspath(ARGS[2])
ispath(OUT) && error("output exists")
isfinite(BUDGET) && BUDGET>0 && BLAS.get_num_threads()==1 || error("invalid runtime")
digest(path)=bytes2hex(sha256(read(path)))
const CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim/config/icn-threads.toml"))
const BASELINE=TOML.parsefile(joinpath(ROOT,"LiLim/config/current-pilot.toml"))
const COHORT=TOML.parsefile(joinpath(ROOT,"LiLim/config/workspace-cohort.toml"))["cohort"]
for (name,head) in COHORT
    repo=joinpath(homedir(),".julia/dev",name)
    strip(read(`git -C $repo rev-parse HEAD`,String))==head || error("cohort changed: $name")
    isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) || error("dirty dependency: $name")
end
for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
    digest(joinpath(dirname(Base.active_project()),file))==BASELINE["environment"][key] || error("environment changed")
end
const METHODS=copy(CONFIG["methods"])
push!(METHODS,"cbls_mix_strategy")
Threads.nthreads()>=4 && append!(METHODS,CONFIG["portfolio_methods"])
const BANKS=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:icn,:direct))
BANKS[:icn].bank_sha256==CONFIG["icn_bank_sha256"] || error("bank changed")
const PLANS=Dict(m=>ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(m,Threads.nthreads())) for m in METHODS if m!="highs_native")
const RESULT=Dict{String,Any}("schema"=>"li-lim-all-variants-current/1","started_utc"=>string(now(UTC)),
    "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),"cohort"=>COHORT,
    "source_sha256"=>merge(Dict(relpath(p,ROOT)=>digest(p) for p in readdir(joinpath(ROOT,"LiLim/src");join=true) if endswith(p,".jl")),
        Dict(relpath(@__FILE__,ROOT)=>digest(@__FILE__))),"icn_bank_sha256"=>BANKS[:icn].bank_sha256,
    "threads"=>Threads.nthreads(),"gc_threads"=>Threads.ngcthreads(),"budget_seconds"=>BUDGET,
    "methods"=>METHODS,"config"=>CONFIG,"environment"=>BASELINE["environment"],
    "affinity"=>only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status"))),
    "preparation_policy"=>"packages, fixed bank and immutable prepared MetaStrategist kernels warmed once; each trial owns models, buffers, RNG and incumbent snapshots; read/insertion/model/search charged to shared clock",
    "trials"=>Any[],"warmups"=>Any[])
function save()
    RESULT["updated_utc"]=string(now(UTC));mkpath(dirname(OUT))
    temporary=OUT*".partial"
    open(io->TOML.print(io,RESULT;sorted=true),temporary,"w");mv(temporary,OUT;force=true)
end
function campaign()
    for (index,id) in enumerate(CONFIG["instances"])
        path=joinpath(ROOT,"LiLim/data/raw/pdp_100",id*".txt")
        digest(path)==CONFIG["source_sha256"][id] || error("instance changed")
        for method in METHODS
            for pass in 1:2
                t=@timed ResourceExperiment.run_case(path,method,1.,0,CONFIG["policy"],BANKS;portfolio=get(PLANS,method,nothing))
                push!(RESULT["warmups"],Dict("instance"=>id,"method"=>method,"pass"=>pass,"wall_seconds"=>t.time,"allocated_bytes"=>t.bytes,"gc_seconds"=>t.gctime))
            end
        end
        for (repeat,seed) in enumerate(CONFIG["seeds"]),method in circshift(METHODS,repeat-1+index-1)
            record=ResourceExperiment.run_case(path,method,BUDGET,seed,CONFIG["policy"],BANKS;portfolio=get(PLANS,method,nothing))
            record["original_validation"] || error("invalid result")
            all(e["seconds"]<=BUDGET for e in record["trajectory"]) || error("late event")
            push!(RESULT["trials"],record);save()
            println("CURRENT ",Threads.nthreads(),"t ",id," ",method," rep ",seed,": ",record["vehicles"]," / ",record["distance"]," CPU ",round(record["mean_active_cpus"];digits=2));flush(stdout)
        end
    end
end
campaign();RESULT["complete"]=true;save()
