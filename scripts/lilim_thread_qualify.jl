include(joinpath(@__DIR__,"..","SolverSmoke","scripts","activate.jl"))
using TOML,Dates,UUIDs,SHA
include(projectdir("src","Anytime.jl"));using .Anytime
include(projectdir("src","AnytimeValidation.jl"));using .AnytimeValidation
include(projectdir("src","AnytimeRunner.jl"));using .AnytimeRunner
include(joinpath(@__DIR__,"..","src","LiLimSchedule.jl"));using .LiLimSchedule
import .AnytimeRunner: save
function main()
    repo=abspath(projectdir(),"..");lock=joinpath(repo,"_research","run.lock");mkdir(lock)
    out=datadir("thread-qualification",string(uuid4()));mkpath(out)
    save(joinpath(lock,"owner.toml"),Dict("pid"=>getpid(),"study"=>"thread-qualification","directory"=>out))
    println("QUALIFICATION=",out);flush(stdout)
    try
        before=qualify_hash();warm=fixtures(out);ENV["ANYTIME_WARMUP_INPUT"]=warm
        configs=thread_configurations(configurations)
        jobs=[Dict("input"=>warm,"engine"=>c.engine,"profile"=>c.profile,"threads"=>c.threads,
            "seed"=>s,"budget"=>2.,"out"=>joinpath(out,"$(c.engine)-$(c.profile)-t$(c.threads)-s$s.toml")) for c in configs.ready for s in 1:3]
        save(joinpath(out,"jobs.toml"),Dict("jobs"=>jobs))
        processes=Dict{String,Any}()
        for threads in (1,2,4)
            batchjobs=filter(j->j["engine"] in ("lss_native","cbls_jump") && j["threads"]==threads,jobs)
            batch=joinpath(out,"batch-$threads.toml");save(batch,Dict("jobs"=>batchjobs))
            cmd=addenv(`$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=$threads,0 --gcthreads=1 --project=$(projectdir()) $(scriptsdir("anytime_lss.jl")) $batch`,
                "SOLVER_COMPARISON_CPUS"=>join(4:3+threads,','))
            println("START LSS/CBLS batch threads=",threads);flush(stdout)
            proc=execute(cmd,batch*".log";wall=600.,threads=threads)
            save(batch*".process.toml",proc);proc["exitcode"]==0 || error("LSS threaded qualification failed")
            for job in batchjobs;processes[job["out"]]=proc;end
        end
        for job in filter(j->!(j["engine"] in ("lss_native","cbls_jump")),jobs)
            println("START ",job["engine"]," threads=",job["threads"]," seed=",job["seed"]);flush(stdout)
            proc=execute(command(job,warm),job["out"]*".log";wall=180.,threads=job["threads"])
            save(job["out"]*".process.toml",proc);proc["exitcode"]==0 || error("Native threaded qualification failed")
            processes[job["out"]]=proc
        end
        rows=Dict{String,Any}[]
        for job in jobs
            trace=check_trace(warm,job["out"];require_solution=true)
            trace["within_budget_feasible"] || error("No within-budget incumbent")
            trace["threads"]==job["threads"] || error("Thread declaration mismatch")
            proc=processes[job["out"]]
            proc["allocated_cpus"]==job["threads"] || error("CPU allocation mismatch")
            save(job["out"]*".validated.toml",trace)
            push!(rows,merge(job,Dict("first_feasible_seconds"=>trace["first_feasible_seconds"],"affinity"=>proc["affinity"],
                "raw_sha256"=>bytes2hex(sha256(read(job["out"]))))))
        end
        before==qualify_hash() || error("Qualified sources changed during qualification")
        save(joinpath(out,"passed.toml"),Dict("schema"=>"thread-qualification/1","code_sha256"=>before,
            "completed_utc"=>string(now(UTC)),"results"=>rows,"configurations"=>length(configs.ready),"runs"=>length(rows),
            "scope"=>"Three independently valid synthetic runs per supported profile/thread configuration, exact worker affinity checked"))
        println("THREAD_QUALIFIED=",out);flush(stdout)
    finally
        owner=TOML.parsefile(joinpath(lock,"owner.toml"))
        if owner["pid"]==getpid();rm(joinpath(lock,"owner.toml"));rm(lock);end
    end
end
main()
