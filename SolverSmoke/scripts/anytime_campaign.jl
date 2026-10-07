include("activate.jl")
using TOML,SHA,Dates,UUIDs
const audit_only = "--audit-resume" in ARGS
const campaign_args = filter(!=("--audit-resume"), ARGS)
length(campaign_args)<=1 || error("Expected at most one campaign directory")
const resume_directory = isempty(campaign_args) ? nothing : abspath(only(campaign_args))
const resuming = resume_directory!==nothing && isfile(joinpath(resume_directory,"started.toml"))
audit_only && !resuming && error("Audit requires an existing campaign")
# A continuation executes and validates with the original qualified modules.
const execution_root = resuming ? joinpath(resume_directory,"snapshot","Benchmarks","SolverSmoke") : projectdir()
include(joinpath(execution_root,"src","Anytime.jl"));using .Anytime
include(joinpath(execution_root,"src","AnytimeValidation.jl"));using .AnytimeValidation
include(joinpath(execution_root,"src","AnytimeRunner.jl"));using .AnytimeRunner
import .AnytimeRunner: save
function main()
    repo=abspath(projectdir(),"..");revision=readchomp(`git -C $repo rev-parse HEAD`)
    (audit_only || isempty(readchomp(`git -C $repo status --porcelain`))) || error("Commit changes before campaign")
    remote=readchomp(`git -C $repo ls-remote gitlab refs/heads/feat/solver-comparison-ilp`)
    startswith(remote,revision*"\t") || error("Campaign revision is not on private GitLab")
    qualification=TOML.parsefile(joinpath(execution_root,"ANYTIME_QUALIFICATION.toml"))
    qualification["code_sha256"]==qualify_hash(source_root=execution_root) || error("Sources/runtime differ from qualification")
    if resuming
        old=TOML.parsefile(joinpath(resume_directory,"started.toml"))
        old["code_sha256"]==qualification["code_sha256"] || error("Snapshot differs from campaign qualification")
        original=old["revision"]
        # Later reporting/controller commits are allowed; the measured revision remains fixed.
        success(`git -C $repo merge-base --is-ancestor $original $revision`) || error("Original revision is not an ancestor of the pushed controller")
        committed=TOML.parse(read(`git -C $repo show $(original*":SolverSmoke/ANYTIME_QUALIFICATION.toml")`,String))
        committed["code_sha256"]==old["code_sha256"] || error("Original committed qualification disagrees")
        if audit_only
            println("RESUME_AUDIT_PASSED original=",original," controller=",revision," snapshot=",old["code_sha256"])
            return
        end
    end
    cases=TOML.parsefile(datadir("anytime-inputs","cases.toml"))["cases"]
    length(cases)==354 && all(c->c["ready"],cases) || error("All 354 original instances must be prepared")
    out=resume_directory===nothing ? datadir("anytime-campaign",string(uuid4())) : resume_directory;mkpath(out)
    lockdir=abspath(repo,"_research","run.lock");mkdir(lockdir)
    save(joinpath(lockdir,"owner.toml"),Dict("pid"=>getpid(),"study"=>"LiLim-anytime","directory"=>out))
    try
        snapshot=joinpath(out,"snapshot","Benchmarks","SolverSmoke")
        if !isfile(joinpath(out,"started.toml"))
            make_snapshot(snapshot)
            save(joinpath(out,"started.toml"),Dict("revision"=>revision,"code_sha256"=>qualification["code_sha256"],
                "started_utc"=>string(now(UTC)),"cpu_ceiling"=>4,"affinity"=>"f0","budgets"=>[30,60,120,240],
                "worker_rss_ceiling_bytes"=>4*1024^3,"minimum_host_free_bytes"=>512*1024^2,"timefold_max_heap"=>"1g",
                "seeds"=>[1,2,3],"instances"=>354,"configurations"=>length(configurations),"hpo_allocation"=>"Other task remains on CPUs 0-3",
                "purpose"=>"Diagnostic anytime baseline, not final solver ranking; native formulations require further tuning"))
        else
            old=TOML.parsefile(joinpath(out,"started.toml"))
            old["code_sha256"]==qualification["code_sha256"] || error("Resume requires the identical qualified snapshot")
        end
        qualify_hash(source_root=snapshot)==qualification["code_sha256"] || error("Archived execution snapshot differs from qualified sources/runtime")
        save(joinpath(out,"controller.toml"),Dict("pid"=>getpid(),"resumed_utc"=>string(now(UTC)),"affinity"=>"f0","controller_revision"=>revision))
        warm=fixtures(out);ENV["ANYTIME_WARMUP_INPUT"]=warm
        # Interleave sizes so all six size families get early observations.
        bysize=[sort(filter(c->c["nominal_tasks"]==n,cases);by=c->c["id"]) for n in (100,200,400,600,800,1000)]
        order=[group[i] for i in 1:maximum(length.(bysize)) for group in bysize if i<=length(group)]
        priority=[("timefold_native","default"),("cbls_jump","default"),
            ("juls_native","greedy_swap"),("lss_native","default")]
        configs=sort(configurations;by=c->something(findfirst(==((c.engine,c.profile)),priority),c.engine=="highs_control" ? 100 : 50),alg=Base.Sort.MergeSort)
        finished=0;total=354*length(configurations)*4*3
        println("CAMPAIGN=",out," PID=",getpid()," JOBS=",total);flush(stdout)
        for budget in (30,60,120,240), seed in 1:3, case in order, config in configs
            isfile(joinpath(out,"STOP")) && (println("Stopped between jobs; remove STOP to resume.");return)
            key="$(case["id"])-$(config.engine)-$(config.profile)-$(budget)-$(seed)"
            dir=joinpath(out,"runs",key);mkpath(dir);status=joinpath(dir,"status.toml")
            if isfile(status);finished+=1;continue;end
            bytes2hex(sha256(read(case["input"])))==case["input_sha256"] || error("Input modified after preparation")
            job=Dict("input"=>case["input"],"engine"=>config.engine,"profile"=>config.profile,"budget"=>budget,
                "seed"=>seed,"out"=>joinpath(dir,"raw.toml"),"instance"=>case["id"],"nominal_tasks"=>case["nominal_tasks"],
                "actual_customers"=>case["actual_customers"],"source_sha256"=>case["source_sha256"])
            save(joinpath(dir,"job.toml"),job)
            println("START ",finished+1,"/",total," ",key);flush(stdout)
            process=execute(command(job,warm;worker_root=snapshot),joinpath(dir,"process.log");wall=budget+180.)
            save(joinpath(dir,"process.toml"),process)
            if process["exitcode"]!=0
                result=Dict("state"=>process["resource_censored"] ? "resource_censored" : "execution_error",
                    "reason"=>process["resource_reason"]*"; see process.log; this is not a solver-quality loss", "completed_utc"=>string(now(UTC)))
                save(status,result)
            else
                # Fail closed on a false incumbent; do not continue a corrupted campaign.
                validated=check_trace(case["input"],job["out"])
                save(joinpath(dir,"validated.toml"),validated)
                save(status,Dict("state"=>validated["within_budget_feasible"] ? "feasible_incumbent" : validated["found"] ? "feasible_only_after_budget" : "no_observed_feasible_incumbent",
                    "completed_utc"=>string(now(UTC))))
            end
            finished+=1
            save(joinpath(out,"progress.toml"),Dict("finished"=>finished,"total"=>total,"last"=>key,"updated_utc"=>string(now(UTC))))
            println("DONE ",key);flush(stdout)
        end
        save(joinpath(out,"completed.toml"),Dict("completed_utc"=>string(now(UTC)),"finished"=>finished))
    finally
        owner=TOML.parsefile(joinpath(lockdir,"owner.toml"))
        if owner["pid"]==getpid();rm(joinpath(lockdir,"owner.toml"));rm(lockdir);end
    end
end
main()
