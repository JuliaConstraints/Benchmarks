# Explicit Linux campaign; no work is launched by importing a package.
using TOML, SHA, Dates, UUIDs
const ROOT = normpath(joinpath(@__DIR__,"..",".."))
const CONFIG_PATH = joinpath(ROOT,"LiLim","config","current-pilot.toml")
const CONFIG = TOML.parsefile(CONFIG_PATH)
digest(path) = bytes2hex(sha256(read(path)))
function save(path,record)
    ispath(path) && error("refusing to overwrite evidence: $path")
    temporary = path*".partial"
    open(io->TOML.print(io,record;sorted=true),temporary,"w")
    mv(temporary,path)
end
function check_sources()
    string(VERSION)==CONFIG["julia"] || error("Julia version mismatch")
    Threads.nthreads()==1 || error("one Julia thread required")
    affinity = strip(split(only(filter(line->startswith(line,"Cpus_allowed_list:"),readlines("/proc/self/status"))),':')[2])
    affinity==string(CONFIG["cpu"]) || error("affinity must equal the configured CPU")
    env = dirname(Base.active_project())
    for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
        digest(joinpath(env,file))==CONFIG["environment"][key] || error("environment bytes changed: $file")
    end
    for (name,expected) in CONFIG["cohort"]
        repo = joinpath(homedir(),".julia","dev",name)
        strip(read(`git -C $repo rev-parse HEAD`,String))==expected || error("cohort revision mismatch: $name")
        isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) ||
            error("tracked dependency changes: $name")
    end
    measured = ["LiLim/src","LiLim/scripts/current_pilot.jl","LiLim/config/current-pilot.toml"]
    isempty(strip(read(`git -C $ROOT status --porcelain --untracked-files=no -- $measured`,String))) ||
        error("commit measured inputs before running")
    for id in CONFIG["instances"]
        path = joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt")
        digest(path)==CONFIG["source_sha256"][id] || error("instance bytes changed: $id")
    end
end
function source_metadata()
    env = dirname(Base.active_project())
    hashes = Dict("LiLim/config/current-pilot.toml"=>digest(CONFIG_PATH))
    for file in readdir(joinpath(ROOT,"LiLim","src");join=true)
        endswith(file,".jl") && (hashes[relpath(file,ROOT)]=digest(file))
    end
    hashes["LiLim/scripts/current_pilot.jl"] = digest(@__FILE__)
    Dict("schema"=>CONFIG["schema"],"config"=>CONFIG,"source_sha256"=>hashes,
        "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),
        "project_sha256"=>digest(joinpath(env,"Project.toml")),
        "manifest_sha256"=>digest(joinpath(env,"Manifest.toml")),
        "julia"=>string(VERSION),"cpu_name"=>Sys.CPU_NAME,"machine"=>Sys.MACHINE,
        "affinity"=>strip(only(filter(line->startswith(line,"Cpus_allowed_list:"),readlines("/proc/self/status")))),
        "started_utc"=>string(now(UTC)))
end
length(ARGS)>=1 || error("usage: current_pilot.jl check | campaign [output-directory] | case instance output-directory")
check_sources()
if ARGS[1]=="check"
    println("Frozen source, environment, instance and CPU checks passed")
elseif ARGS[1]=="case"
    length(ARGS)==3 || error("case needs instance and output directory")
    id,output = ARGS[2:3]
    id in CONFIG["instances"] || error("instance outside frozen diagnostic corpus")
    isdir(output) || error("supervisor must create output directory")
    loaded = time_ns()
    using ConstraintModels, JuMP
    using ConstraintModels.Benchmarks
    include(joinpath(ROOT,"LiLim","src","Pilot.jl"))
    include(joinpath(ROOT,"LiLim","src","MetaRepair.jl"))
    include(joinpath(ROOT,"LiLim","src","Hybrid.jl"))
    include(joinpath(ROOT,"LiLim","src","Experiment.jl"))
    load_seconds = (time_ns()-loaded)/1e9
    warm_seconds = @elapsed Experiment.warmup(CONFIG["policy"])
    save(joinpath(output,"runtime.toml"),Dict("loading_seconds"=>load_seconds,
        "warmup_seconds"=>warm_seconds,"highs_package"=>string(pkgversion(Pilot.HiGHS)),
        "jump_package"=>string(pkgversion(JuMP)),"semantics"=>SEMANTICS_VERSION))
    path = joinpath(output,"instance.txt")
    cp(joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt"),path)
    digest(path)==CONFIG["source_sha256"][id] || error("copied instance digest mismatch")
    ordinal = 0
    for budget in CONFIG["budgets_seconds"], (repetition,seed) in enumerate(CONFIG["seeds"])
        # Cyclic order set before observing results; each method occupies
        # different positions across the six budget/seed blocks.
        methods = circshift(CONFIG["methods"],repetition-1+(budget==last(CONFIG["budgets_seconds"]) ? 2 : 0))
        for method in methods
            global ordinal += 1
            prefix = lpad(ordinal,3,'0')*"-"*method*"-"*string(Int(budget))*"-"*string(seed)
            save(joinpath(output,prefix*".started.toml"),Dict("start_unix"=>time(),"method"=>method,
                "budget_seconds"=>budget,"seed"=>seed))
            record = Experiment.run_case(path,method,budget,seed,CONFIG["policy"];id)
            save(joinpath(output,prefix*".result.toml"),record)
            save(joinpath(output,prefix*".completed.toml"),Dict("result_sha256"=>digest(joinpath(output,prefix*".result.toml"))))
            println(id," ",ordinal,"/24 ",method," ",Int(budget),"s seed ",seed,
                ": ",record["vehicles"]," vehicles, ",round(record["distance"];digits=3),
                "; wall ",round(record["wall_seconds"];digits=3)); flush(stdout)
        end
    end
    save(joinpath(output,"completed.toml"),Dict("jobs"=>ordinal,"finished_utc"=>string(now(UTC))))
elseif ARGS[1]=="campaign"
    length(ARGS)<=2 || error("campaign accepts at most one output directory")
    output = length(ARGS)==2 ? abspath(ARGS[2]) : joinpath(ROOT,"LiLim","data","pilots",string(uuid4()))
    ispath(output) && error("campaign output already exists")
    mkpath(output)
    metadata = source_metadata()
    save(joinpath(output,"started.toml"),metadata)
    for relative in keys(metadata["source_sha256"])
        target = joinpath(output,"snapshot",relative); mkpath(dirname(target));cp(joinpath(ROOT,relative),target)
    end
    for file in ("Project.toml","Manifest.toml")
        cp(joinpath(dirname(Base.active_project()),file),joinpath(output,"snapshot",file))
    end
    println("Campaign: ",output);flush(stdout)
    for id in CONFIG["instances"]
        target = joinpath(output,id);mkdir(target)
        command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing -O1 --threads=1 --gcthreads=1 --project=$(dirname(Base.active_project())) $(@__FILE__) case $id $target`
        open(joinpath(target,"console.log"),"w") do io
            process = run(pipeline(command;stdout=io,stderr=io);wait=false)
            pid = getpid(process);started=time();peak=0;reason="normal_exit"
            while process_running(process)
                status = isfile("/proc/$pid/status") ? read("/proc/$pid/status",String) : ""
                found = match(r"VmRSS:\s+(\d+) kB",status)
                found===nothing || (peak=max(peak,parse(Int,found[1])*1024))
                starts = sort(filter(name->endswith(name,".started.toml"),readdir(target)))
                job_elapsed = isempty(starts) ? 0. : time()-TOML.parsefile(joinpath(target,last(starts)))["start_unix"]
                if peak>CONFIG["memory_guard_bytes"] || time()-started>CONFIG["instance_wall_guard_seconds"] || job_elapsed>CONFIG["job_wall_guard_seconds"]
                    reason = peak>CONFIG["memory_guard_bytes"] ? "memory_limit" : "wall_limit"
                    kill(process);break
                end
                sleep(1.)
            end
            wait(process)
            save(joinpath(target,"supervision.toml"),Dict("pid"=>pid,"exitcode"=>process.exitcode,
                "reason"=>reason,"peak_rss_bytes"=>peak,"wall_seconds"=>time()-started))
            process.exitcode==0 && reason=="normal_exit" || error("instance failed: $id, $reason, exit $(process.exitcode)")
        end
        println("Finished ",id);flush(stdout)
    end
    save(joinpath(output,"completed.toml"),Dict("finished_utc"=>string(now(UTC)),"instances"=>CONFIG["instances"]))
else
    error("unknown mode")
end
