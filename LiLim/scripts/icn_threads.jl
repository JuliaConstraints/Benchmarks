# Explicit Linux campaign. No campaign starts when a package is imported.
using TOML, SHA, Dates, UUIDs, LinearAlgebra
const ROOT = normpath(joinpath(@__DIR__,"..",".."))
const CONFIG_PATH = joinpath(ROOT,"LiLim","config","icn-threads.toml")
const CONFIG = TOML.parsefile(CONFIG_PATH)
const BASELINE_PATH = joinpath(ROOT,"LiLim","config","current-pilot.toml")
const BASELINE = TOML.parsefile(BASELINE_PATH)
digest(path)=bytes2hex(sha256(read(path)))
function save(path,record)
    ispath(path) && error("refusing to overwrite evidence: $path")
    temporary=path*".partial"
    open(io->TOML.print(io,record;sorted=true),temporary,"w")
    mv(temporary,path)
end
function check_sources()
    string(VERSION)==CONFIG["julia"] || error("Julia version changed")
    BLAS.get_num_threads()==1 || error("BLAS must use one thread")
    env=dirname(Base.active_project())
    for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
        digest(joinpath(env,file))==BASELINE["environment"][key] || error("solver environment changed")
    end
    for (name,expected) in BASELINE["cohort"]
        repo=joinpath(homedir(),".julia","dev",name)
        strip(read(`git -C $repo rev-parse HEAD`,String))==expected || error("cohort changed: $name")
        isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`,String))) || error("tracked dependency changes: $name")
    end
    measured=["LiLim/src","LiLim/config/icn-threads.toml","LiLim/scripts/icn_threads.jl"]
    isempty(strip(read(`git -C $ROOT status --porcelain --untracked-files=no -- $measured`,String))) || error("commit measured sources first")
    for id in CONFIG["instances"]
        digest(joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt"))==CONFIG["source_sha256"][id] || error("instance changed")
    end
    bank_repo=joinpath(homedir(),".julia","dev","ConstraintLearningBenchmarks")
    strip(read(`git -C $bank_repo rev-parse HEAD`,String))==CONFIG["clb_commit"] || error("ICN bank repository changed")
    digest(joinpath(bank_repo,"scripts","xcsp3_core","learnable_catalog","weights.toml"))==CONFIG["icn_bank_sha256"] || error("ICN bank changed")
end
function metadata()
    files=[CONFIG_PATH,BASELINE_PATH,@__FILE__]
    append!(files,filter(f->endswith(f,".jl"),readdir(joinpath(ROOT,"LiLim","src");join=true)))
    bank=joinpath(homedir(),".julia","dev","ConstraintLearningBenchmarks","scripts","xcsp3_core","learnable_catalog","weights.toml")
    Dict("schema"=>CONFIG["schema"],"config"=>CONFIG,"baseline_environment"=>BASELINE,
        "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),
        "clb_commit"=>strip(read(`git -C $(joinpath(homedir(),".julia","dev","ConstraintLearningBenchmarks")) rev-parse HEAD`,String)),
        "icn_bank_sha256"=>digest(bank),"julia"=>string(VERSION),"cpu_name"=>Sys.CPU_NAME,
        "source_sha256"=>Dict(relpath(file,ROOT)=>digest(file) for file in files),
        "started_utc"=>string(now(UTC)))
end
function jobs(width)
    methods=copy(CONFIG["methods"])
    width>=4 && append!(methods,CONFIG["portfolio_methods"])
    result=Any[]
    for (instance_index,id) in enumerate(CONFIG["instances"]), (repetition,seed) in enumerate(CONFIG["seeds"])
        for method in circshift(methods,repetition-1+instance_index-1)
            prefix=lpad(length(result)+1,3,'0')*"-"*id*"-"*method*"-"*string(seed)
            push!(result,(;prefix,id,method,seed))
        end
    end
    result
end
function check_archive(output)
    isfile(joinpath(output,"completed.toml")) && error("campaign is already complete")
    original=TOML.parsefile(joinpath(output,"started.toml"))
    original["config"]==CONFIG && original["baseline_environment"]==BASELINE || error("resumption protocol changed")
    for (relative,hash) in original["source_sha256"]
        digest(joinpath(output,"snapshot",relative))==hash || error("source snapshot corrupted: $relative")
        relative=="LiLim/scripts/icn_threads.jl" && continue
        digest(joinpath(ROOT,relative))==hash || error("measured source changed: $relative")
    end
    missing=0
    for width in CONFIG["thread_counts"]
        target=joinpath(output,string(width))
        expected=jobs(width)
        expected_files=Set(job.prefix*".result.toml" for job in expected)
        actual=filter(f->endswith(f,".result.toml"),readdir(target))
        all(in(expected_files),actual) || error("unexpected result in width $width")
        for job in expected
            file=joinpath(target,job.prefix*".result.toml")
            seal=joinpath(target,job.prefix*".completed.toml")
            if isfile(file)
                isfile(seal) && TOML.parsefile(seal)["result_sha256"]==digest(file) || error("unsealed or corrupted result: $file")
                r=TOML.parsefile(file)
                (r["instance"],r["method"],r["seed"],r["threads_requested"])==(job.id,job.method,job.seed,width) || error("case identity changed")
            else
                isfile(seal) && error("missing sealed result: $file")
                missing+=1
            end
        end
        if isfile(joinpath(target,"completed.toml"))
            TOML.parsefile(joinpath(target,"completed.toml"))["jobs"]==length(expected)==length(actual) || error("completed width inventory changed")
        end
    end
    missing
end
function supervise(width,target;segment=nothing)
    cpus=join(CONFIG["cpu_order"][1:width],',')
    mode=segment===nothing ? "width" : "width-resume"
    command=`taskset --cpu-list $cpus $(Base.julia_cmd()) --startup-file=no --compiled-modules=existing -O1 --threads=$width,0 --gcthreads=1 --project=$(dirname(Base.active_project())) $(@__FILE__) $mode $width $target`
    segment===nothing || (command=`$command $segment`)
    evidence=segment===nothing ? target : segment
    open(joinpath(evidence,"console.log"),"w") do io
        process=run(pipeline(command;stdout=io,stderr=io);wait=false)
        pid=getpid(process);started=time();peak=0;peak_threads=0;reason="normal_exit"
        try
            while process_running(process)
                status=isfile("/proc/$pid/status") ? read("/proc/$pid/status",String) : ""
                found=match(r"VmRSS:\s+(\d+) kB",status)
                found===nothing || (peak=max(peak,parse(Int,found[1])*1024))
                found=match(r"Threads:\s+(\d+)",status)
                found===nothing || (peak_threads=max(peak_threads,parse(Int,found[1])))
                starts=sort(filter(f->endswith(f,".started.toml"),readdir(evidence)))
                elapsed_job=isempty(starts) ? 0. : time()-TOML.parsefile(joinpath(evidence,last(starts)))["start_unix"]
                if peak>CONFIG["memory_guard_bytes"] || time()-started>CONFIG["process_wall_guard_seconds"] || elapsed_job>CONFIG["job_wall_guard_seconds"]
                    reason=peak>CONFIG["memory_guard_bytes"] ? "memory_limit" : "wall_limit"
                    kill(process);break
                end
                sleep(0.5)
            end
            wait(process)
        finally
            # An interrupted supervisor must not leave an orphan computing.
            process_running(process) && kill(process)
        end
        save(joinpath(evidence,"supervision.toml"),Dict("pid"=>pid,"exitcode"=>process.exitcode,
            "reason"=>reason,"peak_rss_bytes"=>peak,"peak_os_threads"=>peak_threads,"wall_seconds"=>time()-started))
        process.exitcode==0 && reason=="normal_exit" || error("width failed: $width; see $evidence/console.log")
    end
end
length(ARGS)>=1 || error("usage: icn_threads.jl check | campaign [output] | check-resume output | resume output | width threads output")
check_sources()
if ARGS[1]=="check"
    println("Source and environment checks passed")
elseif ARGS[1] in ("width","width-resume")
    resumed=ARGS[1]=="width-resume"
    length(ARGS)==(resumed ? 4 : 3) || error("width needs thread count, directory and optional resumption segment")
    width=parse(Int,ARGS[2]);output=ARGS[3]
    segment=resumed ? ARGS[4] : output
    resumption_id=resumed ? basename(dirname(segment)) : ""
    width in CONFIG["thread_counts"] && Threads.nthreads()==width || error("thread count mismatch")
    affinity=strip(split(only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status"))),':')[2])
    # taskset reports compressed ranges; compare the actual CPU membership.
    allowed=Int[]
    for part in split(affinity,',')
        bounds=parse.(Int,split(part,'-'))
        append!(allowed,length(bounds)==1 ? bounds : first(bounds):last(bounds))
    end
    sort(allowed)==sort(CONFIG["cpu_order"][1:width]) || error("CPU affinity differs from protocol")
    loading=time_ns()
    using ConstraintModels, JuMP
    using ConstraintModels.Benchmarks
    include(joinpath(ROOT,"LiLim","src","Pilot.jl"))
    include(joinpath(ROOT,"LiLim","src","MetaRepair.jl"))
    include(joinpath(ROOT,"LiLim","src","ICNScoring.jl"))
    include(joinpath(ROOT,"LiLim","src","Hybrid.jl"))
    include(joinpath(ROOT,"LiLim","src","ResourceExperiment.jl"))
    banks=Dict(kind=>ICNScoring.load_backend(kind) for kind in (:naive,:icn,:direct))
    load_seconds=(time_ns()-loading)/1e9
    warm_seconds=mktemp() do path,io
        write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
        @elapsed Base.invokelatest(ResourceExperiment.warmup,path,CONFIG["policy"],banks;threads=width)
    end
    save(joinpath(segment,"runtime.toml"),Dict("threads"=>width,"affinity"=>affinity,
        "loading_seconds"=>load_seconds,"warmup_seconds"=>warm_seconds,
        "highs_package"=>string(pkgversion(Pilot.HiGHS)),"semantics"=>SEMANTICS_VERSION,
        "bank_sha256"=>banks[:icn].bank_sha256,"witness_indices"=>banks[:icn].witnesses))
    for job in jobs(width)
            (;prefix,id,method,seed)=job
            if resumed && isfile(joinpath(output,prefix*".result.toml"))
                TOML.parsefile(joinpath(output,prefix*".completed.toml"))["result_sha256"]==digest(joinpath(output,prefix*".result.toml")) || error("corrupted completed result")
                continue
            end
            save(joinpath(segment,prefix*".started.toml"),Dict("start_unix"=>time(),"instance"=>id,"method"=>method,"seed"=>seed))
            path=joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt")
            native_log=method=="highs_native" ? joinpath(segment,prefix*".highs.log") : nothing
            record=Base.invokelatest(ResourceExperiment.run_case,path,method,CONFIG["budget_seconds"],seed,
                CONFIG["policy"],banks;threads=width,id,logpath=native_log)
            save(joinpath(output,prefix*".result.toml"),record)
            seal=Dict("result_sha256"=>digest(joinpath(output,prefix*".result.toml")))
            if resumed
                seal["resumption_id"]=resumption_id
                native_log===nothing || (seal["native_log_relative"]=relpath(native_log,dirname(output)))
            end
            save(joinpath(output,prefix*".completed.toml"),seal)
            println(width,"T ",id," ",method," seed ",seed,": ",record["vehicles"]," vehicles, ",
                round(record["distance"];digits=3)," distance; active CPU ",round(record["mean_active_cpus"];digits=2));flush(stdout)
    end
    completion=Dict{String,Any}("jobs"=>length(jobs(width)),"finished_utc"=>string(now(UTC)))
    resumed && (completion["resumption_id"]=resumption_id)
    save(joinpath(output,"completed.toml"),completion)
elseif ARGS[1] in ("check-resume","resume")
    length(ARGS)==2 || error("resumption needs campaign directory")
    output=abspath(ARGS[2]);missing=check_archive(output)
    println("Verified archive: ",missing," missing trials");flush(stdout)
    if ARGS[1]=="resume"
        # Metadata records the controller change; solver sources and protocol stay frozen.
        resumption=joinpath(output,"resumptions",string(uuid4()));mkpath(resumption)
        info=metadata();info["missing_trials_before_resume"]=missing
        save(joinpath(resumption,"started.toml"),info)
        cp(@__FILE__,joinpath(resumption,"icn_threads.jl"))
        for width in CONFIG["thread_counts"]
            target=joinpath(output,string(width))
            isfile(joinpath(target,"completed.toml")) && continue
            check_sources();segment=joinpath(resumption,string(width));mkdir(segment)
            supervise(width,target;segment)
            println("Finished resumed ",width," threads");flush(stdout)
        end
        save(joinpath(resumption,"completed.toml"),Dict("finished_utc"=>string(now(UTC))))
        save(joinpath(output,"completed.toml"),Dict("finished_utc"=>string(now(UTC)),"widths"=>CONFIG["thread_counts"],"resumption_id"=>basename(resumption)))
    end
elseif ARGS[1]=="campaign"
    length(ARGS)<=2 || error("campaign accepts at most one output")
    output=length(ARGS)==2 ? abspath(ARGS[2]) : joinpath(ROOT,"LiLim","data","thread-pilots",string(uuid4()))
    ispath(output) && error("output exists")
    mkpath(output);info=metadata();save(joinpath(output,"started.toml"),info)
    for relative in keys(info["source_sha256"])
        target=joinpath(output,"snapshot",relative);mkpath(dirname(target));cp(joinpath(ROOT,relative),target)
    end
    for file in ("Project.toml","Manifest.toml")
        cp(joinpath(dirname(Base.active_project()),file),joinpath(output,"snapshot",file))
    end
    println("Campaign: ",output);flush(stdout)
    for width in CONFIG["thread_counts"]
        check_sources()
        target=joinpath(output,string(width));mkdir(target)
        supervise(width,target)
        println("Finished ",width," threads");flush(stdout)
    end
    save(joinpath(output,"completed.toml"),Dict("finished_utc"=>string(now(UTC)),"widths"=>CONFIG["thread_counts"]))
else
    error("unknown mode")
end
