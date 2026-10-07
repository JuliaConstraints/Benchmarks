"One colleague entry point. Preparation and preflight never start a comparative campaign."
module LiLimKit
include("../../LiLim/scripts/colleague.jl")
end
include("../src/Sources.jl")
include("../src/Problems.jl")
include("../src/Readers.jl")
include("../src/Selections.jl")
using TOML,Dates
using .ReproductionSources,.ReproductionSelections
const ROOT=LiLimKit.ROOT
function verify_environment()
    string(VERSION)=="1.13.1" || error("Julia 1.13.1 required")
    for (name,sha) in LiLimKit.CONFIG["cohort"]
        path=joinpath(LiLimKit.DEV,name)
        isdir(path) && strip(read(`git -C $path rev-parse HEAD`,String))==sha &&
            isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String))) || error("Frozen source differs; existing files preserved: $name")
    end
    for (name,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
        path=joinpath(LiLimKit.SOLVER_ENV,name)
        isfile(path) && LiLimKit.digest(path)==LiLimKit.CONFIG["environment"][key] || error("Frozen $name differs")
    end
    LiLimKit.digest(joinpath(ROOT,"LiLim/resources/icn-pdptw-witnesses.toml"))==LiLimKit.CONFIG["portable_icn_bank_sha256"] || error("Frozen ICN bank differs")
end
function options(args)
    opts=Dict{String,String}()
    for arg in args
        startswith(arg,"--") && occursin('=',arg) || error("Use --name=value")
        k,v=split(arg[3:end],'=';limit=2)
        k in ("threads","cpus","budget","methods","instances","seeds","hexaly","output","resume","ortools",
            "missing-solvers","prepare","qualify","gurobi","cplex","cpoptimizer","selection","sources","max-cells","java") || error("Unknown option $k")
        haskey(opts,k) && error("Duplicate option $k");opts[k]=v
    end
    opts
end
function preflight(opts)
    output=abspath(get(opts,"output",joinpath(ROOT,"LiLim/results/preflight-"*Dates.format(now(UTC),"yyyymmdd-HHMMSS"))))
    ispath(output) && error("Choose a new preflight output directory; previous evidence is preserved")
    original=copy(opts);original["output"]=output
    for k in ("selection","sources","max-cells");pop!(original,k,nothing);end
    code=LiLimKit.preflight(original)
    lock=TOML.parsefile(joinpath(ROOT,"Hexaly/config/sources.toml"))
    prepared=parse(Bool,get(opts,"prepare","true"))
    source_state=prepared ? fetch_sources(ROOT,lock;select=get(opts,"sources","all")) : verify_sources(ROOT,lock)
    manifest=selection(get(opts,"selection",joinpath(ROOT,"Hexaly/config/instances.toml")))
    inputs=verify_instances(ROOT,manifest)
    worker=joinpath(output,"classical-qualification.toml")
    state="not_run"
    if parse(Bool,get(opts,"qualify","true"))
        child=LiLimKit.launcher(opts,joinpath(ROOT,"Hexaly/scripts/qualify.jl"),["--output="*worker];
            threads=LiLimKit.qualification_width(opts,"classical_strategy_panel"))
        haskey(opts,"hexaly") && (child=addenv(child,"HEXALY_EXECUTABLE"=>opts["hexaly"]))
        r=LiLimKit.NativeSolvers.capture(child;timeout=600)
        state=r.code==0 && isfile(worker) ? "passed" : "failed"
    end
    report=TOML.parsefile(joinpath(output,"report.toml"))
    report["classical_qualification"]=isfile(worker) ? TOML.parsefile(worker) : Dict("status"=>state)
    report["sources"]=source_state;report["selected_original_inputs"]=inputs
    report["active_entry_count"]=19;report["continuous_deferred"]= ["irp"]
    checks=get(report["classical_qualification"],"checks",Dict{String,Any}())
    LiLimKit.HexalyPreflight.discrete_evidence!(report,checks;core_state=state)
    for row in report["benchmarks"]
        row["id"] in ("pdptw","irp") && continue
        row["functional_inputs"]=filter(r->r["entry"]==row["id"],inputs)
    end
    report["published_reproduction_status"]="incomplete_published_reproduction"
    report["status"]=code==1 ? "qualification_failed" : LiLimKit.HexalyPreflight.kit_status(report;qualify=parse(Bool,get(opts,"qualify","true")))
    LiLimKit.HexalyPreflight.save_report(output,report;refresh=true)
    write_discrete_detail(output,report,state,inputs)
    println("Preflight status: ",report["status"],"; report: ",joinpath(output,"report.md"))
    report["status"]=="qualification_failed" ? 1 : report["status"] in ("ready_available_solvers","inventory_complete") ? 0 : 2
end
function write_discrete_detail(output,report,state,inputs)
    open(joinpath(output,"report.md"),"a") do io
        println(io,"\n## Discrete toolkit qualification\n\nActive entries: 19. IRP is deferred because original delivery quantities are continuous. ",
            "Classical model/validator tests: **$state**. The committed instance selection is a functional smoke set, not the exact published cohorts. ",
            "Complete published selections and reference records remain mandatory before claiming reproduction.\n")
        println(io,"| Original input | Scope | Bytes |\n|---|---|---|")
        for r in inputs;println(io,"| $(r["id"]) | $(r["scope"]) | $(r["status"]) |");end
        if haskey(get(report,"classical_qualification",Dict()),"checks")
            println(io,"\n| Native adapter | Qualification | Scope |\n|---|---|---|")
            for (name,check) in sort!(collect(report["classical_qualification"]["checks"]);by=first)
                println(io,"| $name | $(check["status"]) | $(get(check,"scope",get(check,"reason","see machine-readable evidence"))) |")
            end
        end
    end
end
function main(args=ARGS)
    isempty(args) && error("Usage: colleague.jl preflight|prepare|qualify|run|lilim|report [--name=value]")
    cmd=first(args);opts=options(args[2:end])
    if cmd=="preflight";return preflight(opts)
    elseif cmd=="prepare"
        original=Dict(k=>v for(k,v)in opts if !(k in ("selection","sources","max-cells")))
        LiLimKit.setup(original);fetch_sources(ROOT,TOML.parsefile(joinpath(ROOT,"Hexaly/config/sources.toml"));select=get(opts,"sources","all"))
    elseif cmd=="qualify"
        arguments=haskey(opts,"output") ? ["--output="*abspath(opts["output"])] : String[]
        child=LiLimKit.launcher(opts,joinpath(ROOT,"Hexaly/scripts/qualify.jl"),arguments;
            threads=LiLimKit.qualification_width(opts,"classical_strategy_panel"))
        haskey(opts,"hexaly") && (child=addenv(child,"HEXALY_EXECUTABLE"=>opts["hexaly"]))
        LiLimKit.launch(child)
    elseif cmd=="run"
        verify_environment()
        haskey(opts,"instances") && haskey(opts,"output") || error("Explicit --instances and --output required")
        arguments=["--$k=$v" for(k,v)in opts if k in ("selection","instances","methods","budget","threads","seeds","output","resume","max-cells")]
        child=LiLimKit.launcher(opts,joinpath(ROOT,"Hexaly/scripts/run.jl"),arguments)
        haskey(opts,"hexaly") && (child=addenv(child,"HEXALY_EXECUTABLE"=>opts["hexaly"]))
        LiLimKit.launch(child)
    elseif cmd=="lilim"
        verify_environment()
        LiLimKit.campaign(opts)
    elseif cmd=="report"
        haskey(opts,"output") || error("--output required")
        LiLimKit.launch(LiLimKit.launcher(opts,joinpath(ROOT,"Hexaly/scripts/report.jl"),[abspath(opts["output"])];threads=1))
        for style in ("exact","xkcd")
            directory=abspath(opts["output"])
            LiLimKit.launch(LiLimKit.launcher(opts,joinpath(ROOT,"Hexaly/scripts/plots.jl"),
                [joinpath(directory,"summary.toml"),joinpath(directory,"figures-"*style),style];plot=true,threads=1))
        end
    else;error("Unknown command $cmd");end
    0
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && exit(main())
