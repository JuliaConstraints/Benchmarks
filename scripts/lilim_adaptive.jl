include(joinpath(@__DIR__,"..","SolverSmoke","scripts","activate.jl"))
using TOML,SHA,Dates,UUIDs
const repo=abspath(@__DIR__,"..")
const resume_dir=isempty(ARGS) ? nothing : abspath(only(ARGS))
const worker_root=resume_dir===nothing ? projectdir() : joinpath(resume_dir,"snapshot","Benchmarks","SolverSmoke")
include(joinpath(worker_root,"src","Anytime.jl"));using .Anytime
include(joinpath(worker_root,"src","AnytimeValidation.jl"));using .AnytimeValidation
include(joinpath(worker_root,"src","AnytimeRunner.jl"));using .AnytimeRunner
include(resume_dir===nothing ? joinpath(repo,"src","LiLimSchedule.jl") : joinpath(resume_dir,"schedule.jl"));using .LiLimSchedule
import .AnytimeRunner: save

function main()
    isempty(readchomp(`git -C $repo status --porcelain`)) || error("Commit controller and qualification before launch")
    revision=readchomp(`git -C $repo rev-parse HEAD`)
    startswith(readchomp(`git -C $repo ls-remote gitlab refs/heads/feat/solver-comparison-ilp`),revision*"\t") || error("Push to private GitLab before launch")
    configset=thread_configurations(configurations)
    qualification=TOML.parsefile(resume_dir===nothing ? projectdir("THREAD_QUALIFICATION.toml") : joinpath(resume_dir,"qualification.toml"))
    qualification["code_sha256"]==qualify_hash(source_root=worker_root) || error("Qualified adapter snapshot mismatch")
    qualification["configurations"]==length(configset.ready) || error("Incomplete thread qualification")
    out=resume_dir===nothing ? datadir("adaptive-campaign",string(uuid4())) : resume_dir
    lock=joinpath(repo,"_research","run.lock");mkdir(lock);mkpath(out)
    save(joinpath(lock,"owner.toml"),Dict("pid"=>getpid(),"study"=>"LiLim-adaptive","directory"=>out))
    try
        snapshot=joinpath(out,"snapshot","Benchmarks","SolverSmoke")
        if resume_dir===nothing
            cases=TOML.parsefile(datadir("anytime-inputs","cases.toml"))["cases"]
            length(cases)==354 && all(c->c["ready"],cases) || error("Need all 354 original instances")
            make_snapshot(snapshot)
            save(joinpath(out,"cases.toml"),Dict("cases"=>cases))
            cp(projectdir("THREAD_QUALIFICATION.toml"),joinpath(out,"qualification.toml"))
            cp(joinpath(repo,"src","LiLimSchedule.jl"),joinpath(out,"schedule.jl"))
            cp(@__FILE__,joinpath(out,"controller-source.jl"))
            save(joinpath(out,"availability.toml"),Dict("ready"=>[Dict(string(k)=>v for (k,v) in pairs(c)) for c in configset.ready],
                "unavailable"=>[Dict(string(k)=>v for (k,v) in pairs(c)) for c in configset.unavailable]))
            save(joinpath(out,"started.toml"),Dict("schema"=>"lilim-adaptive/1","revision"=>revision,"started_utc"=>string(now(UTC)),
                "code_sha256"=>qualification["code_sha256"],"schedule_sha256"=>bytes2hex(sha256(read(joinpath(out,"schedule.jl")))),
                "cases_sha256"=>bytes2hex(sha256(read(joinpath(out,"cases.toml")))),"instances"=>354,"configurations"=>length(configset.ready),
                "budgets"=>[30,60,120,240],"seeds"=>[1,2,3],"thread_counts"=>[1,2,4],"cpu_ceiling"=>4,
                "stop_rule"=>"240 minimum unless every observation at 120 is feasible; then double per unresolved instance, finishing each entire stage",
                "purpose"=>"Diagnostic baseline; no claim of optimized native formulations or solver ranking"))
        end
        started=TOML.parsefile(joinpath(out,"started.toml"));original=started["revision"]
        success(`git -C $repo merge-base --is-ancestor $original $revision`) || error("Original revision not in pushed history")
        committed=TOML.parse(read(`git -C $repo show $(original*":SolverSmoke/THREAD_QUALIFICATION.toml")`,String))
        committed["code_sha256"]==started["code_sha256"] || error("Original committed thread qualification disagrees")
        qualify_hash(source_root=snapshot)==started["code_sha256"] || error("Archived runtime modified")
        bytes2hex(sha256(read(joinpath(out,"schedule.jl"))))==started["schedule_sha256"] || error("Schedule changed")
        bytes2hex(sha256(read(joinpath(out,"cases.toml"))))==started["cases_sha256"] || error("Case list changed")
        cases=TOML.parsefile(joinpath(out,"cases.toml"))["cases"]
        allcases=Dict(c["id"]=>c for c in cases)
        controller=Dict("pid"=>getpid(),"resumed_utc"=>string(now(UTC)),"controller_revision"=>revision,"affinity"=>"f0")
        save(joinpath(out,"controller.toml"),controller)
        mkpath(joinpath(out,"sessions"));save(joinpath(out,"sessions",string(uuid4())*".toml"),controller)
        warm=fixtures(joinpath(out,"warmup"));ENV["ANYTIME_WARMUP_INPUT"]=warm
        groups=[sort(filter(c->c["nominal_tasks"]==n,cases);by=c->c["id"]) for n in (100,200,400,600,800,1000)]
        order=[g[i]["id"] for i in 1:maximum(length.(groups)) for g in groups if i<=length(g)]
        active=order;budget=30;finished=0;rows=Dict{String,Any}[]
        configs=sort(configset.ready;by=c->(c.threads,c.engine=="highs_control" ? 2 : c.profile=="default" ? 0 : 1,c.engine,c.profile))
        println("CAMPAIGN=",out," PID=",getpid()," CONFIGURATIONS=",length(configs));flush(stdout)
        while !isempty(active)
            for seed in 1:3,id in active,c in configs
                isfile(joinpath(out,"STOP")) && (println("Stopped between jobs.");return)
                case=allcases[id]
                key="$id-$(c.engine)-$(c.profile)-t$(c.threads)-b$budget-s$seed"
                dir=joinpath(out,"runs",key);status=joinpath(dir,"status.toml")
                job=Dict("input"=>case["input"],"engine"=>c.engine,"profile"=>c.profile,"threads"=>c.threads,"budget"=>budget,
                    "seed"=>seed,"out"=>joinpath(dir,"raw.toml"),"instance"=>id,"nominal_tasks"=>case["nominal_tasks"],
                    "actual_customers"=>case["actual_customers"],"source_sha256"=>case["source_sha256"])
                if !isfile(status)
                    # Never overwrite an interrupted attempt or guess that an orphan worker died.
                    isdir(dir) && !isempty(readdir(dir)) && error("Unfinished attempt requires diagnosis and archival before retry: $dir")
                    mkpath(dir)
                    bytes2hex(sha256(read(case["input"])))==case["input_sha256"] || error("Input changed")
                    save(joinpath(dir,"job.toml"),job)
                    println("START ",key);flush(stdout)
                    proc=execute(command(job,warm;worker_root=snapshot),joinpath(dir,"process.log");wall=budget+180.,threads=c.threads)
                    save(joinpath(dir,"process.toml"),proc)
                    if proc["exitcode"]!=0
                        save(status,Dict("state"=>proc["resource_censored"] ? "resource_censored" : "execution_error","completed_utc"=>string(now(UTC))))
                    else
                        validated=check_trace(case["input"],job["out"])
                        validated["threads"]==c.threads || error("Thread mismatch")
                        save(joinpath(dir,"validated.toml"),validated)
                        save(status,Dict("state"=>validated["within_budget_feasible"] ? "feasible_incumbent" : validated["found"] ? "feasible_only_after_budget" : "no_observed_feasible_incumbent","completed_utc"=>string(now(UTC))))
                    end
                    println("DONE ",key);flush(stdout)
                end
                stored=TOML.parsefile(joinpath(dir,"job.toml"))
                stored==job || error("Stored job disagrees with fixed campaign plan")
                push!(rows,merge(job,TOML.parsefile(status)));finished+=1
                save(joinpath(out,"progress.toml"),Dict("finished"=>finished,"budget"=>budget,"active_instances"=>length(active),
                    "base_grid_total"=>354*length(configs)*4*3,"last"=>key,"updated_utc"=>string(now(UTC))))
                last(rows)["state"] in ("execution_error","resource_censored") && error("Technical result requires diagnosis before continuing: $dir")
            end
            next=next_stage(budget,active,configs,rows)
            mkpath(joinpath(out,"stages"));save(joinpath(out,"stages","$budget.toml"),Dict("completed_utc"=>string(now(UTC)),
                "budget"=>budget,"instances"=>active,"next_budget"=>next.budget,"next_instances"=>next.instances,"reason"=>next.reason))
            budget=next.budget;active=next.instances
        end
        save(joinpath(out,"completed.toml"),Dict("finished"=>finished,"completed_utc"=>string(now(UTC))))
    finally
        owner=TOML.parsefile(joinpath(lock,"owner.toml"))
        if owner["pid"]==getpid();rm(joinpath(lock,"owner.toml"));rm(lock);end
    end
end
main()
