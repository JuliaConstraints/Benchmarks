# JuLS pilot; the historical direct C++ GHOST path is no longer authorized.
# Check before loading packages or creating an output directory.
!isempty(ARGS) && first(ARGS)=="ghost" && error("GHOST must use the GHOST.jl wrapper. The Li-Lim wrapper adapter is pending source recovery and qualification; direct C++ execution is disabled.")
using ConstraintModels, JuMP, TOML, SHA, Dates
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
include(joinpath(@__DIR__,"..","competitors","Permutation.jl"))
length(ARGS)==5 || error("usage: juls workers seconds greedy|annealing new-output.toml")
const ENGINE=ARGS[1];const WIDTH=parse(Int,ARGS[2]);const BUDGET=parse(Float64,ARGS[3]);const PROFILE=ARGS[4];const OUT=abspath(ARGS[5])
ENGINE=="juls" && WIDTH in (1,2,4,8,16) && BUDGET>0 || error("invalid engine/resources")
PROFILE in ("greedy","annealing") || error("invalid profile")
ispath(OUT) && error("output exists")
const ROOT=normpath(joinpath(@__DIR__,"..",".."));const CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim/config/icn-threads.toml"))
const AFFINITY=join(CONFIG["cpu_order"][1:WIDTH],',')
const JULS=joinpath(homedir(),".julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia")
digest(p)=bytes2hex(sha256(read(p)))
const SOURCE=joinpath(ROOT,"LiLim/native/juls/pdptw.jl")
const UPSTREAM=joinpath(homedir(),".julia/dev/JuLS")
isempty(strip(read(`git -C $UPSTREAM status --porcelain --untracked-files=no`,String))) || error("dirty native dependency")
const RESULT=Dict{String,Any}("schema"=>"li-lim-native-local-search-qualified/1","started_utc"=>string(now(UTC)),
    "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),"engine"=>ENGINE,"profile"=>PROFILE,
    "threads"=>WIDTH,"budget_seconds"=>BUDGET,"affinity"=>AFFINITY,
    "upstream_commit"=>strip(read(`git -C $UPSTREAM rev-parse HEAD`,String)),
    "source_sha256"=>Dict(relpath(p,ROOT)=>digest(p) for p in (@__FILE__,SOURCE,joinpath(ROOT,"LiLim/competitors/Permutation.jl"),joinpath(ROOT,"LiLim/competitors/Adapters.jl"),joinpath(ROOT,"LiLim/src/Pilot.jl"))),
    "seed_controlled"=>ENGINE=="juls","instances"=>Any[])
RESULT["environment_sha256"]=Dict(f=>digest(joinpath(ROOT,"LiLim/native/juls",f)) for f in ("Project.toml","Manifest.toml"))
function campaign()
    p=read_benchmark(joinpath(ROOT,"LiLim/data/raw/pdp_100/lc101.txt"),:li_lim)
    initial=Pilot.insertion(p;starts=5,seed=41);CompetitorAdapters.export_common_start(devnull,p,initial)
    for id in CONFIG["instances"]
        path=joinpath(ROOT,"LiLim/data/raw/pdp_100",id*".txt");digest(path)==CONFIG["source_sha256"][id] || error("instance changed")
        prep=@timed begin
            p=read_benchmark(path,:li_lim;id);initial=Pilot.insertion(p;starts=5,seed=41)
            initial===nothing && error("no common start")
        end
        mktempdir() do exchange
            input=joinpath(exchange,"input.txt");output=joinpath(exchange,"native.toml")
            export_seconds=@elapsed open(io->CompetitorAdapters.export_common_start(io,p,initial),input,"w")
            prefix=prep.time+export_seconds;native_budget=BUDGET-prefix;native_budget>0 || error("late preparation")
            cmd=`taskset --cpu-list $AFFINITY timeout --kill-after=5s 120s $JULS --startup-file=no --threads=$WIDTH --gcthreads=1 --project=$(joinpath(ROOT,"LiLim/native/juls")) $SOURCE $input $native_budget $PROFILE $output`
            println(ENGINE," ",PROFILE," ",id," ",WIDTH,"t");flush(stdout)
            cold=@elapsed run(pipeline(cmd;stdout=devnull))
            native=TOML.parsefile(output);trials=Any[];d=PermutationRoutes.read_common(input)
            audit=@elapsed for trial in native["trials"]
                isempty(trial["trajectory"]) && error("native engine did not confirm its common start")
                trajectory=Any[];best=nothing;quality=(typemax(Int),Inf)
                for event in trial["trajectory"]
                    0<=event["seconds"]<=native_budget || error("late native incumbent")
                    routes=PermutationRoutes.decode(d,Int.(event["values"]));checked=validate_solution(p,routes)
                    checked.valid && checked.objective.vehicles==event["vehicles"] || error("invalid native incumbent")
                    isapprox(checked.objective.distance,event["distance"];atol=1e-7,rtol=1e-12) || error("native distance mismatch")
                    q=(checked.objective.vehicles,checked.objective.distance);q<quality || continue
                    best=deepcopy(routes);quality=q
                    push!(trajectory,Dict("seconds"=>prefix+event["seconds"],"vehicles"=>q[1],"distance"=>q[2],"routes"=>deepcopy(routes)))
                end
                push!(trials,merge(trial,Dict("trajectory"=>trajectory,"vehicles"=>quality[1],"distance"=>quality[2],
                    "routes"=>best,"original_validation"=>true,"initial_vehicles"=>validate_solution(p,initial).objective.vehicles,
                    "initial_distance"=>validate_solution(p,initial).objective.distance,"budget_seconds"=>BUDGET)))
            end
            push!(RESULT["instances"],Dict("id"=>id,"instance_sha256"=>digest(path),"export_sha256"=>digest(input),
                "common_initialization_seconds"=>prefix,"native_budget_seconds"=>native_budget,"initial_routes"=>initial,
                "cold_process_with_warmup_seconds"=>cold,"audit_seconds"=>audit,"native"=>native,"qualified_trials"=>trials))
            mkpath(dirname(OUT));open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
        end
    end
end
campaign();RESULT["complete"]=true;open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
