include("activate.jl")
using TOML,Dates,UUIDs
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../src/AnytimeRunner.jl");using .AnytimeRunner
import .AnytimeRunner: save
function main()
    out=datadir("anytime-preflight",string(uuid4()));mkpath(out);warm=fixtures(out)
    ENV["ANYTIME_WARMUP_INPUT"]=warm
    println("PREFLIGHT=",out);flush(stdout)
    jobs=Dict{String,Any}[]
    for seed in 1:2
        push!(jobs,Dict("input"=>warm,"engine"=>"highs_control","profile"=>"compact_mip","budget"=>2.,"seed"=>seed,
            "out"=>joinpath(out,"highs-$seed.toml"),"require_solution"=>true))
    end
    cases=TOML.parsefile(datadir("anytime-inputs","cases.toml"))["cases"]
    # Actual, unreduced Li-Lim instances. Check all six sizes in each native engine
    # and the JuMP facade; a no-incumbent search is a valid functional outcome.
    for size in (100,200,400,600,800,1000)
        case=first(filter(c->c["nominal_tasks"]==size,cases))
        for c in filter(c->(c.engine in ("lss_native","cbls_jump","timefold_native") && c.profile=="default") || c.engine in ("juls_native","ghost_native_cpp"),configurations)
            push!(jobs,Dict("input"=>case["input"],"engine"=>c.engine,"profile"=>c.profile,"budget"=>.2,"seed"=>1,
                "out"=>joinpath(out,"$(case["id"])-$(c.engine).toml"),"require_solution"=>false,"size"=>size))
        end
    end
    save(joinpath(out,"jobs.toml"),Dict("jobs"=>jobs))
    results=Dict{String,Any}[]
    for job in jobs
        println("START ",basename(job["out"]));flush(stdout)
        process=execute(command(job,warm),job["out"]*".log";wall=180.)
        save(job["out"]*".process.toml",process)
        process["exitcode"]==0 || error("Preflight failed: $(job["out"])")
        validated=check_trace(job["input"],job["out"];require_solution=job["require_solution"])
        save(job["out"]*".validated.toml",validated)
        push!(results,Dict("engine"=>job["engine"],"size"=>get(job,"size",0),"found"=>validated["found"],
            "solve_call_seconds"=>validated["solve_call_seconds"],"input"=>job["input"],"result"=>job["out"]))
        save(joinpath(out,"progress.toml"),Dict("results"=>results))
    end
    save(joinpath(out,"passed.toml"),Dict("completed_utc"=>string(now(UTC)),"results"=>results))
    println("PREFLIGHT_PASSED=",out)
end
main()
