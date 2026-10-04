# Native Timefold runs; exchange files are temporary, qualified evidence is retained.
using ConstraintModels, JuMP, TOML, SHA, Dates
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
length(ARGS)==4 || error("usage: timefold_pilot.jl workers seconds default|late_acceptance_400 output.toml")
const WIDTH=parse(Int,ARGS[1]);const BUDGET=parse(Float64,ARGS[2]);const PROFILE=ARGS[3];const OUT=abspath(ARGS[4])
WIDTH in (1,2,4,8,16) && isfinite(BUDGET) && BUDGET>0 || error("invalid resources")
PROFILE in ("default","late_acceptance_400") || error("invalid profile")
ispath(OUT) && error("output exists")
const ROOT=normpath(joinpath(@__DIR__,"..",".."));const NATIVE=joinpath(ROOT,"LiLim","native","timefold")
const TARGET=joinpath(NATIVE,"target");isdir(joinpath(TARGET,"dependency")) || error("build the pinned Maven project first")
digest(path)=bytes2hex(sha256(read(path)))
const CPU_ORDER=[8,10,0,2,4,6,12,14,16,17,18,19,9,11,1,3]
const AFFINITY=join(CPU_ORDER[1:WIDTH],',')
const CONFIG=TOML.parsefile(joinpath(ROOT,"LiLim","config","icn-threads.toml"))
const RESULT=Dict{String,Any}("schema"=>"li-lim-timefold-qualified-pilot/1","started_utc"=>string(now(UTC)),
    "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),"workers"=>WIDTH,"budget_seconds"=>BUDGET,
    "profile"=>PROFILE,"cpu_affinity"=>AFFINITY,"julia"=>string(VERSION),
    "java_runtime"=>read(`java --version`,String),
    "jvm_options"=>["-XX:ActiveProcessorCount=$WIDTH","-XX:+UseSerialGC","-Xmx2g"],
    "source_sha256"=>Dict(relpath(p,ROOT)=>digest(p) for p in (
        @__FILE__,joinpath(ROOT,"LiLim","competitors","Adapters.jl"),joinpath(ROOT,"LiLim","src","Pilot.jl"),
        joinpath(NATIVE,"pom.xml"),joinpath(NATIVE,"src","main","java","bench","Pdptw.java"))),
    "jars_sha256"=>Dict(basename(p)=>digest(p) for p in readdir(joinpath(TARGET,"dependency");join=true)),
    "comparison_scope"=>"diagnostic common-start native Timefold Community; not an Enterprise benchmark; native clock includes input/model/factory/solve/incumbent checks, Julia common start and final audit are separately reported",
    "instances"=>Any[])
function campaign()
    # Compile controller-side parsing/insertion/export before charging common preparation.
    path=joinpath(ROOT,"LiLim","data","raw","pdp_100","lc101.txt")
    p=read_benchmark(path,:li_lim);initial=Pilot.insertion(p;starts=5,seed=41)
    CompetitorAdapters.export_common_start(devnull,p,initial)
    for id in ("lc101","lr101","lrc101")
        path=joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt")
        digest(path)==CONFIG["source_sha256"][id] || error("instance changed")
        preparation=@timed begin
            p=read_benchmark(path,:li_lim;id);initial=Pilot.insertion(p;starts=5,seed=41)
            initial===nothing && error("no common start")
        end
        mktempdir() do exchange
            input=joinpath(exchange,"instance.txt");output=joinpath(exchange,"native.toml")
            open(io->CompetitorAdapters.export_common_start(io,p,initial),input,"w")
            classpath=join([joinpath(TARGET,"classes"),joinpath(TARGET,"dependency","*")],Sys.iswindows() ? ';' : ':')
            cmd=`taskset --cpu-list $AFFINITY timeout --signal=TERM --kill-after=5s 120s java -XX:ActiveProcessorCount=$WIDTH -XX:+UseSerialGC -Xmx2g -Dorg.slf4j.simpleLogger.defaultLogLevel=warn -cp $classpath bench.Pdptw $input $PROFILE $BUDGET $WIDTH 41,42,43 $output`
            println("Timefold ",id," · ",WIDTH," worker(s) · ",BUDGET," s");flush(stdout)
            wall=@elapsed run(cmd)
            native=TOML.parsefile(output);audited=@timed CompetitorAdapters.audit_timefold(p,initial,native)
            push!(RESULT["instances"],Dict("id"=>id,"instance_sha256"=>digest(path),
                "export_sha256"=>digest(input),"common_initialization_seconds"=>preparation.time,
                "cold_process_with_warmup_seconds"=>wall,"final_audit_seconds"=>audited.time,
                "initial_routes"=>initial,"native"=>native,"qualified_trials"=>audited.value))
            RESULT["updated_utc"]=string(now(UTC));mkpath(dirname(OUT));open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
        end
    end
end
campaign();RESULT["complete"]=true;open(io->TOML.print(io,RESULT;sorted=true),OUT,"w")
