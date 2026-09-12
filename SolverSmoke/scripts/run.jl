include("activate.jl")
using TOML, SHA, UUIDs, Dates
root=projectdir();attempt=datadir("sims",string(uuid4()));mkpath(attempt)
lock=abspath(root,"..","_research","run.lock");mkdir(lock)
write(joinpath(lock,"owner.toml"),"pid = $(getpid())\nstudy = \"solver-smoke\"\n")
save(path,data)=open(io->TOML.print(io,data;sorted=true),path,"w")
function execute(label,command;wall=300.)
    log=joinpath(attempt,label*".log");println("START ",label);flush(stdout)
    start=time()
    open(log,"w") do io
        child=run(pipeline(command;stdout=io,stderr=io);wait=false)
        pid=getpid(child)
        while process_running(child)
            if time()-start>wall
                kill(child);wait(child);error("$label exceeded $wall seconds")
            end
            sleep(0.25)
        end
        wait(child)
        save(joinpath(attempt,label*"-process.toml"),Dict("pid"=>pid,"exitcode"=>child.exitcode,
            "wall_seconds"=>time()-start,"cpus"=>COMPARISON_CPUS,"affinity"=>string(COMPARISON_AFFINITY;base=16)))
        success(child) || error("$label failed; see $log")
    end
    println("DONE ",label);flush(stdout)
end
try
    hashes=Dict{String,String}()
    for folder in ("src","scripts","native","vendor","juls-env"), (dir,subdirs,files) in walkdir(joinpath(root,folder))
        filter!(x->x!=".git" && x!="target",subdirs)
        for file in files
            path=joinpath(dir,file);relative=relpath(path,root);target=joinpath(attempt,"snapshot",relative)
            mkpath(dirname(target));cp(path,target)
            hashes[replace(relative,'\\'=>'/')]=bytes2hex(sha256(read(path)))
        end
    end
    for file in ("Project.toml","Manifest.toml","vendor-inventory.toml")
        cp(projectdir(file),joinpath(attempt,"snapshot",file));hashes[file]=bytes2hex(sha256(read(projectdir(file))))
    end
    metadata=Dict("started_utc"=>string(now(UTC)),"source_sha256"=>hashes,"cpu_ceiling"=>4,
        "allocation"=>COMPARISON_CPUS,"concurrent_hpo"=>"Separate CPUs 0-3; shared memory/cache/frequency",
        "juls_revision"=>readchomp(`git -C $(projectdir("vendor","JuLS")) rev-parse HEAD`),
        "hexaly"=>"Excluded by user: license not activated","scope"=>"Functional pilot, 2 seconds, 3 repetitions; not a ranking")
    metadata["jdk"]=TOML.parsefile(projectdir("runtime","runtime.toml"))
    metadata["ghost_cpp"]=TOML.parsefile(projectdir("runtime","ghost-portable","build.toml"))
    metadata["timefold_jars_sha256"]=Dict(basename(path)=>bytes2hex(sha256(read(path))) for path in readdir(projectdir("native","timefold","target","dependency");join=true))
    save(joinpath(attempt,"started.toml"),metadata)
    println("ATTEMPT=",attempt);flush(stdout)
    base=`$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1 --project=$root`
    julia111=joinpath(homedir(),".julia","juliaup","julia-1.11.9+0.x64.w64.mingw32","bin","julia.exe")
    juls=`$julia111 --startup-file=no --compiled-modules=existing --threads=4 --gcthreads=1 --project=$(projectdir("juls-env"))`
    bag=joinpath(attempt,"knapsack");route=joinpath(attempt,"routing")
    execute("knapsack-julia",`$base $(scriptsdir("knapsack.jl")) $bag`)
    execute("knapsack-timefold",`$base $(scriptsdir("run_timefold.jl")) knapsack $(joinpath(bag,"timefold-instance.txt")) $bag`)
    execute("routing-cbls",`$base $(scriptsdir("routing.jl")) $route`)
    execute("routing-timefold",`$base $(scriptsdir("run_timefold.jl")) routing $(joinpath(route,"instance.txt")) $route`)
    execute("routing-ghost",`$base $(scriptsdir("run_ghost.jl")) $(joinpath(route,"instance.txt")) $route`)
    execute("juls-native",`$juls $(scriptsdir("juls_suite.jl")) $bag $route`)
    execute("validation",`$base $(scriptsdir("report.jl")) $attempt`)
    save(joinpath(attempt,"completed.toml"),Dict("completed_utc"=>string(now(UTC)),"pid"=>getpid()))
finally
    # Remove only this controller's two exact lock paths.
    rm(joinpath(lock,"owner.toml"));rm(lock)
end
