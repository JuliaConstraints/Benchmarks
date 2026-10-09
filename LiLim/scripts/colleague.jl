# Pinned handoff: check, setup, qualify, run, report, and export.
using TOML, SHA, Downloads, Pkg
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))
include(joinpath(@__DIR__,"..","src","PlatformResources.jl"))
include(joinpath(@__DIR__,"..","src","HexalyPreflight.jl"))
include(joinpath(@__DIR__,"..","src","ScreeningControl.jl"))
include(joinpath(@__DIR__,"..","src","CampaignCatalog.jl"))
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CONFIG = TOML.parsefile(joinpath(ROOT,"LiLim/config/workspace-cohort.toml"))
const DEV = abspath(get(ENV,"JULIACONSTRAINTS_COHORT_ROOT",joinpath(homedir(),".julia/dev/JuliaConstraintsBench")))
const SOLVER_ENV = joinpath(DEV,"ConstraintModels/perf/pdptw")
const PYTHON=NativeSolvers.default_python(ROOT)
digest(path) = bytes2hex(sha256(read(path)))

function clone_cohort(url, branch, path;commit=nothing)
    # A Windows global autocrlf setting must not change the frozen source bytes.
    # This setting belongs only to a newly created checkout.
    run(`git clone --config core.autocrlf=false --single-branch --branch $branch $url $path`)
    # A development branch may advance after this cohort was qualified. Only
    # a newly created checkout is moved to its exact published source snapshot.
    commit===nothing || run(`git -C $path checkout --detach $commit`)
end

cohort_branch(name,config=CONFIG)=get(get(config,"cohort_branches",Dict{String,String}()),name,config["public_branch"])

"Accept regular clones and linked worktrees, never a directory inside another checkout."
function development_checkout(path)
    isdir(path) && ispath(joinpath(path,".git")) || return false
    try
        root=strip(read(pipeline(`git -C $path rev-parse --show-toplevel`;stderr=devnull),String))
        realpath(root)==realpath(path)
    catch e
        e isa ProcessFailedException || rethrow()
        false
    end
end

function launch(command)
    try
        run(command)
    catch exception
        exception isa ProcessFailedException || rethrow()
        error("Child command failed; see its diagnostics above. Environment variable values are omitted.")
    end
end

function options(args)
    result = Dict{String,String}()
    for arg in args
        startswith(arg,"--") && occursin('=',arg) || error("use --name=value")
        key,value = split(arg[3:end],'=';limit=2)
        key in ("threads","cpus","budget","methods","instances","seeds","hexaly","output","resume","ortools","missing-solvers","prepare","qualify","gurobi","cplex","cpoptimizer","java","widths","cpu-slots",
            "selection-seed","gc-threshold","resource-interval","order","control-dir","worker-slot") || error("unknown option: $key")
        haskey(result,key) && error("duplicate option: $key")
        result[key] = value
    end
    result
end

function topology()
    Sys.islinux() || return PlatformResources.allowed_cpus()
    allowed = Int[]
    line = only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status")))
    for item in split(strip(split(line,':')[2]),',')
        bounds = parse.(Int,split(item,'-'))
        append!(allowed,length(bounds)==1 ? bounds : first(bounds):last(bounds))
    end
    primary = Int[]; siblings = Int[]; seen = Set{Tuple{Int,Int}}()
    for line in split(read(`lscpu --parse=CPU,CORE,SOCKET,ONLINE`,String),'\n')
        isempty(line) || startswith(line,'#') && continue
        isempty(line) && continue
        fields = split(line,','); fields[4]=="Y" || continue
        cpu,core,socket = parse.(Int,fields[1:3]); cpu in allowed || continue
        key = (socket,core)
        push!(key in seen ? siblings : primary,cpu); push!(seen,key)
    end
    vcat(primary,siblings)
end

function launcher(options, script, arguments; plot=false, threads=parse(Int,get(options,"threads","1")))
    order = haskey(options,"cpus") ? parse.(Int,split(options["cpus"],',')) : topology()
    allunique(order) && length(order)>=threads && all(>=(0),order) || error("not enough distinct CPU IDs")
    selected = order[1:threads]
    environment = plot ? joinpath(ROOT,"LiLim/plotting") : SOLVER_ENV
    cmd = PlatformResources.pin(`$(Base.julia_cmd()) --startup-file=no --threads=$threads --gcthreads=1 --project=$environment $script $arguments`,selected)
    addenv(cmd,"OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1","MKL_NUM_THREADS"=>"1",
        "JULIA_NUM_PRECOMPILE_TASKS"=>"1","JULIACONSTRAINTS_COHORT_ROOT"=>DEV,
        "JULIACONSTRAINTS_CPU_ORDER"=>join(order,','),"JULIACONSTRAINTS_TEST_CPU"=>string(first(selected)),
        "ORTOOLS_PYTHON"=>get(options,"ortools",PYTHON),
        "JAVA_EXECUTABLE"=>get(options,"java",get(ENV,"JAVA_EXECUTABLE","java")))
end

function setup(opts=Dict{String,String}())
    string(VERSION)=="1.13.1" || error("Install Julia 1.13.1 first; the solver manifest is frozen to that version.")
    for program in (Sys.islinux() ? ("git","taskset","lscpu") : ("git",))
        Sys.which(program)===nothing && error("Missing prerequisite: $program")
    end
    mkpath(DEV)
    for (name,sha) in sort!(collect(CONFIG["cohort"]))
        path = joinpath(DEV,name)
        if !ispath(path)
            get(CONFIG,"public_status","published")=="published" || error("This source cohort has not been published; existing development checkouts were preserved.")
            url = "https://github.com/JuliaConstraints/"*name*".jl.git"
            branch = cohort_branch(name)
            clone_cohort(url, branch, path;commit=sha)
        end
        development_checkout(path) || error("Not a development checkout: $path")
        strip(read(`git -C $path rev-parse HEAD`,String))==sha || error("Cohort mismatch at $path; existing files were preserved.")
        isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String))) || error("Dirty dependency: $path")
    end
    for (file, key) in (("Project.toml", "project_sha256"), ("Manifest.toml", "manifest_sha256"))
        digest(joinpath(SOLVER_ENV, file)) == CONFIG["environment"][key] ||
            error("Frozen solver environment bytes differ: $file. Git newline conversion can cause this; the existing checkout was preserved. Use a fresh cohort checkout with core.autocrlf=false.")
    end
    digest(joinpath(ROOT,"LiLim/resources/icn-pdptw-witnesses.toml")) == CONFIG["portable_icn_bank_sha256"] ||
        error("Frozen ICN bank bytes differ. Existing files were preserved; use a clean handoff checkout with core.autocrlf=false.")
    import_code = "using Pkg; Pkg.instantiate(;allow_autoprecomp=false); Pkg.precompile()"
    for environment in (SOLVER_ENV,joinpath(ROOT,"LiLim/plotting"))
        manifest = joinpath(environment,"Manifest.toml"); before = digest(manifest)
        run(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $import_code`,
            "JULIA_PKG_PRECOMPILE_AUTO"=>"0","JULIA_NUM_PRECOMPILE_TASKS"=>"1","OPENBLAS_NUM_THREADS"=>"1"))
        digest(manifest)==before || error("Package setup changed the frozen manifest")
    end
    missing=get(opts,"missing-solvers","skip")
    missing in ("skip","error") || error("missing-solvers must be skip or error")
    try
        setup_ghost()
    catch e
        e isa NativeSolvers.UnavailableSolver && missing=="skip" || rethrow()
        println("Skipped ",e.method,": ",e.reason)
    end
    python=get(opts,"ortools",PYTHON)
    missing=get(opts,"missing-solvers","skip")
    missing in ("skip","error") || error("missing-solvers must be skip or error")
    try
        identity=NativeSolvers.install_ortools(python;root=ROOT)
        println("OR-Tools ready: ",identity["ortools_version"],"; existing installations are preserved.")
    catch e
        e isa NativeSolvers.UnavailableSolver && missing=="skip" || rethrow()
        println("Skipped ",e.method,": ",e.reason)
    end
    try
        cpu = haskey(opts,"cpus") ? first(parse.(Int,split(opts["cpus"],','))) : first(topology())
        NativeSolvers.resolve_timefold(get(opts,"java",get(ENV,"JAVA_EXECUTABLE","java"));root=ROOT,install=true,cpus=[cpu])
        println("Timefold ready; existing Java and SDK archives reused where present.")
    catch e
        e isa NativeSolvers.UnavailableSolver && missing=="skip" || rethrow()
        println("Skipped ",e.method,": ",e.reason)
    end
    data_setup()
    println("Pinned sources, solvers and official Li-Lim inputs verified.")
end

"Derive the optional wrapper environment without changing the frozen core."
function setup_ghost()
    entries = CONFIG["optional_cohort"]
    sources = Dict{String,String}()
    for (name,entry) in sort!(collect(entries);by=first)
        path = joinpath(DEV,name)
        if !ispath(path)
            clone_cohort(entry["url"], entry["branch"], path)
            run(`git -C $path checkout --detach $(entry["commit"])`)
        end
        strip(read(`git -C $path rev-parse HEAD`,String)) == entry["commit"] || error("Optional cohort mismatch at $path; existing checkout preserved")
        isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String))) || error("Dirty optional dependency: $name")
        sources[name] = path
    end
    environment = joinpath(ROOT,"LiLim/native/ghost/environment")
    metadata = joinpath(environment,"qualification.toml")
    if isdir(environment)
        NativeSolvers.resolve_ghost(;root=ROOT,install=true)
        println("Existing GHOST wrapper environment reused.")
        return
    end
    mkpath(environment)
    baseline = TOML.parsefile(joinpath(SOLVER_ENV,"Manifest.toml"))
    project = TOML.parsefile(joinpath(SOLVER_ENV,"Project.toml"))
    for (name,source) in project["sources"]
        source["path"] = joinpath(DEV,name)
    end
    derived = deepcopy(baseline)
    for (name,rows) in derived["deps"], row in rows
        haskey(row,"path") && (row["path"] = joinpath(DEV,name))
    end
    open(io->TOML.print(io,project;sorted=true),joinpath(environment,"Project.toml"),"w")
    open(io->TOML.print(io,derived;sorted=true),joinpath(environment,"Manifest.toml"),"w")
    Pkg.activate(environment)
    Pkg.develop([Pkg.PackageSpec(path=sources[name]) for name in sort!(collect(keys(sources)))];preserve=Pkg.PRESERVE_ALL)
    Pkg.instantiate(;allow_autoprecomp=false)
    resolved = TOML.parsefile(joinpath(environment,"Manifest.toml"))
    for (name,rows) in baseline["deps"], row in rows
        actual = only(filter(r->r["uuid"]==row["uuid"],resolved["deps"][name]))
        get(actual,"version",nothing) == get(row,"version",nothing) || error("Optional GHOST setup changed frozen dependency: $name")
    end
    Pkg.precompile()
    environment in LOAD_PATH || push!(LOAD_PATH,environment)
    @eval import GHOST_jll
    saved = Dict("Project.toml"=>digest(joinpath(environment,"Project.toml")),
        "Manifest.toml"=>digest(joinpath(environment,"Manifest.toml")),"sources"=>sources,
        "core_manifest_sha256"=>digest(joinpath(SOLVER_ENV,"Manifest.toml")),
        "cohort"=>entries)
    open(io->TOML.print(io,saved;sorted=true),metadata,"w")
    NativeSolvers.resolve_ghost(;root=ROOT,install=true)
    println("GHOST.jl and matching platform Artifact ready; all frozen core versions retained.")
end

function data_setup()
    bks = TOML.parsefile(joinpath(ROOT,"LiLim/config/sintef-pdptw-bks-20261004.toml"))
    filenames = Dict("100"=>"pdp_100.zip","200"=>"pdp_200.zip","400"=>"pdp_400.zip",
        "600"=>"pdp_600.zip","800"=>"pdptw800.zip","1000"=>"pdptw1000.zip")
    for size in sort!(collect(keys(filenames));by=x->parse(Int,x))
        filename = filenames[size]; archive = joinpath(ROOT,"LiLim/data/raw/sintef-archives",filename)
        if !isfile(archive)
            mkpath(dirname(archive))
            temporary = archive*".partial"
            ispath(temporary) && error("Pre-existing partial download preserved: $temporary")
            try
                Downloads.download("https://www.sintef.no/contentassets/1338af68996841d3922bc8e87adc430c/"*filename,temporary)
                digest(temporary)==bks["archive_sha256"][filename] || error("Official archive checksum changed: $filename")
                mv(temporary,archive)
            finally
                isfile(temporary) && rm(temporary)
            end
        end
        digest(archive)==bks["archive_sha256"][filename] || error("Archive checksum mismatch: $archive")
        mktempdir() do extracted
            run(pipeline(`$(Pkg.PlatformEngines.exe7z()) x -y -o$extracted $archive`;stdout=devnull))
            entries=[joinpath(d,f) for (d,_,files) in walkdir(extracted) for f in files]
            for id in keys(bks["instances"][size])
                path=joinpath(ROOT,"LiLim/data/raw/pdp_"*size,id*".txt")
                expected=bks["instance_sha256"][size*"."*id]
                if !isfile(path)
                    entry=only(filter(e->lowercase(basename(e))==id*".txt",entries))
                    digest(entry)==expected || error("Official instance bytes differ: $id")
                    mkpath(dirname(path)); cp(entry,path)
                end
                digest(path)==expected || error("Existing instance checksum mismatch: $id")
            end
        end
    end
    println("All 354 official instances and six archives verified.")
end

const CORE_QUALIFICATION_TESTS = ("cohort_checkout.jl","hexaly_preflight.jl","ghost_frontend.jl","native_solvers.jl","campaign_catalog.jl","competitors.jl","hybrid.jl","icn_resources.jl","ortools_native.jl","ortools_parallel.jl","strategy_panel.jl","ro_fragments.jl","structured_routing.jl")
function qualification_width(opts,test)
    test in ("ortools_parallel.jl","icn_resources.jl","classical_strategy_panel","structured_routing.jl") || return 1
    cpus=haskey(opts,"cpus") ? parse.(Int,split(opts["cpus"],',')) : topology()
    min(2,length(cpus))
end
function qualify_ortools_parallel(opts)
    mktempdir() do directory
        output=joinpath(directory,"profiles.toml")
        command=launcher(opts,joinpath(ROOT,"LiLim/test/ortools_parallel.jl"),["--output="*output];
            threads=qualification_width(opts,"ortools_parallel.jl"))
        result=NativeSolvers.capture(command;timeout=120)
        evidence=isfile(output) ? TOML.parsefile(output) : Dict{String,Any}()
        (;result,evidence)
    end
end
function qualify(opts; require_hexaly=false)
    for test in CORE_QUALIFICATION_TESTS
        launch(launcher(opts,joinpath(ROOT,"LiLim/test",test),String[];threads=qualification_width(opts,test)))
    end
    launch(launcher(opts,joinpath(ROOT,"LiLim/test/search_policies.jl"),["--routes"];threads=1))
    launch(launcher(opts,joinpath(ROOT,"LiLim/test/ghost_native.jl"),String[];threads=1))
    launch(launcher(opts,joinpath(ROOT,"LiLim/test/timefold_native.jl"),String[];threads=1))
    launch(addenv(launcher(opts,joinpath(ROOT,"LiLim/test/hexaly_native.jl"),String[];threads=1),
        "HEXALY_EXECUTABLE"=>get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly")),
        "JULIACONSTRAINTS_REQUIRE_HEXALY"=>(require_hexaly ? "1" : "0")))
end

"Native report rows accept structured evidence, not only strings."
function available_solver_record(name,identity;fingerprint=digest)
    row=Dict{String,Any}("status"=>"available","reason"=>"installation_probe_passed")
    name=="hexaly" && (row["version"]="15.0";row["executable_sha256"]=fingerprint(identity))
    name=="ortools" && (row["version"]=identity["ortools_version"])
    name=="timefold" && (row["version"]=identity["version"])
    row
end

"Inspect every published benchmark and save a complete report even when a solver is absent."
function preflight(opts)
    prepare = parse(Bool,get(opts,"prepare","true"))
    qualify_models = parse(Bool,get(opts,"qualify","true"))
    output = abspath(get(opts,"output",joinpath(ROOT,"LiLim/results/preflight-"*
        HexalyPreflight.Dates.format(HexalyPreflight.Dates.now(HexalyPreflight.Dates.UTC),"yyyymmdd-HHMMSS"))))
    ispath(output) && error("Preflight output already exists; choose a new --output directory")
    c = HexalyPreflight.catalogue(joinpath(ROOT,"LiLim/config/hexaly-benchmark-catalog.toml"))
    checks = Dict{String,Any}()
    solvers = Dict{String,Any}()
    qualified = Dict{String,String}()
    host_cpus = PlatformResources.allowed_cpus()
    host_ok = string(VERSION)=="1.13.1" && all(p->Sys.which(p)!==nothing,
        Sys.islinux() ? ("git","taskset","lscpu") : ("git",))
    checks["host"] = Dict("status"=>host_ok ? "passed" : "failed",
        "reason"=>host_ok ? "prerequisites_present" : "Julia_1.13.1_or_host_utilities_missing")
    if prepare && host_ok
        try
            setup(opts)
            checks["setup"] = Dict("status"=>"passed","reason"=>"existing_installations_reused")
        catch
            checks["setup"] = Dict("status"=>"failed","reason"=>"setup_failed_existing_files_preserved")
        end
    else
        checks["setup"] = Dict("status"=>"not_run","reason"=>prepare ? "host_prerequisites_missing" : "prepare_false")
    end
    environment_ok = host_ok
    for (name,expected) in CONFIG["cohort"]
        path = joinpath(DEV,name)
        ok = development_checkout(path) &&
            strip(read(`git -C $path rev-parse HEAD`,String))==expected &&
            isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String)))
        checks["source:"*name] = Dict("status"=>ok ? "passed" : "failed","expected_commit"=>expected)
        environment_ok &= ok
    end
    for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
        path = joinpath(SOLVER_ENV,file)
        ok = isfile(path) && digest(path)==CONFIG["environment"][key]
        checks["environment:"*file] = Dict("status"=>ok ? "passed" : "failed","expected_sha256"=>CONFIG["environment"][key])
        environment_ok &= ok
    end
    bank = joinpath(ROOT,"LiLim/resources/icn-pdptw-witnesses.toml")
    bank_ok = isfile(bank) && digest(bank)==CONFIG["portable_icn_bank_sha256"]
    checks["ICN_bank"] = Dict("status"=>bank_ok ? "passed" : "failed")
    environment_ok &= bank_ok
    for (name,resolver) in (("hexaly",()->NativeSolvers.resolve_hexaly(get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly")))),
            ("ortools",()->NativeSolvers.resolve_ortools(get(opts,"ortools",PYTHON);root=ROOT)),
            ("timefold",()->NativeSolvers.resolve_timefold(get(opts,"java",get(ENV,"JAVA_EXECUTABLE","java"));root=ROOT)),
            ("ghost",()->NativeSolvers.resolve_ghost(;root=ROOT)))
        if name=="hexaly" && !qualify_models
            path=NativeSolvers.executable(get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly")))
            solvers[name]=Dict{String,Any}("status"=>path===nothing ? "skipped" : "detected_unqualified",
                "reason"=>path===nothing ? "executable_not_found" : "license_probe_not_run")
            continue
        end
        try
            identity = resolver()
            solvers[name] = available_solver_record(name,identity)
        catch e
            solvers[name] = Dict{String,Any}("status"=>e isa NativeSolvers.UnavailableSolver ? "skipped" : "failed",
                "reason"=>e isa NativeSolvers.UnavailableSolver ? e.reason : "installation_probe_failed")
        end
    end
    juls_path = joinpath(homedir(),".julia/dev/JuLS/Project.toml")
    solvers["juls"] = Dict{String,Any}("status"=>isfile(juls_path) ? "detected_unqualified" : "skipped",
        "reason"=>isfile(juls_path) ? "historical_adapter_not_in_frozen_public_cohort" : "package_not_detected")
    for (name,default) in (("gurobi","gurobi_cl"),("cplex","cplex"),("cpoptimizer","cpoptimizer"))
        path = NativeSolvers.executable(get(opts,name,default))
        solvers[name] = Dict{String,Any}("status"=>path===nothing ? "not_detected" : "detected_unqualified",
            "reason"=>path===nothing ? "CLI_not_found_API_installation_not_ruled_out" : "license_and_original_models_not_qualified")
    end
    for name in ("cbls","local_search","icn","metastrategist","highs")
        solvers[name] = Dict{String,Any}("status"=>environment_ok ? "prepared" : "blocked","reason"=>"original_model_tests_required")
    end
    solvers["ortools"]["profiles"]=Dict{String,Any}(name=>Dict{String,Any}("status"=>"not_run","reason"=>"functional_qualification_required")
        for name in ("routing_gls","routing_portfolio","cpsat"))
    if qualify_models && environment_ok
        tests = [(test,String[]) for test in CORE_QUALIFICATION_TESTS]
        push!(tests,("search_policies.jl",["--routes"]))
        solvers["ghost"]["status"]=="available" && push!(tests,("ghost_native.jl",String[]))
        solvers["timefold"]["status"]=="available" && push!(tests,("timefold_native.jl",String[]))
        core_ok = true
        for (test,args) in tests
            if test=="ortools_parallel.jl"
                parallel=qualify_ortools_parallel(opts);result=parallel.result
                merge!(solvers["ortools"]["profiles"],parallel.evidence)
            else
                result = NativeSolvers.capture(launcher(opts,joinpath(ROOT,"LiLim/test",test),args;
                    threads=qualification_width(opts,test));timeout=300)
            end
            ok = result.code==0 && !result.timed_out
            checks["test:"*test] = Dict("status"=>ok ? "passed" : "failed",
                "reason"=>result.timed_out ? "qualification_timeout" : "exit_code_"*string(result.code))
            test in ("ortools_native.jl","ortools_parallel.jl","ghost_native.jl","timefold_native.jl") || (core_ok &= ok)
            if test=="ortools_parallel.jl" && !ok
                for name in ("routing_portfolio","cpsat")
                    solvers["ortools"]["profiles"][name]=Dict("status"=>"failed","reason"=>"parallel_qualification_failed")
                end
            end
        end
        qualified["pdptw:core"] = core_ok ? "passed" : "failed"
        solvers["ortools"]["status"]=="available" &&
            (qualified["pdptw:ortools"]=checks["test:ortools_native.jl"]["status"])
        if solvers["ortools"]["status"]=="available"
            solvers["ortools"]["qualification"]=qualified["pdptw:ortools"]
            solvers["ortools"]["qualification_scope"]="original_PDPTW_functional_tests"
            solvers["ortools"]["profiles"]["routing_gls"]=Dict("status"=>qualified["pdptw:ortools"],
                "processes"=>1,"workers"=>1,"scope"=>"small_original_PDPTW_models")
        end
        for name in ("cbls","local_search","icn","metastrategist","highs")
            solvers[name]["status"] = core_ok ? "available" : "failed"
            solvers[name]["reason"] = core_ok ? "PDPTW_functional_suite_passed" : "PDPTW_functional_suite_failed"
            solvers[name]["qualification"] = core_ok ? "passed" : "failed"
        end
        for (name,test) in (("ghost","ghost_native.jl"),("timefold","timefold_native.jl"))
            solvers[name]["status"]=="available" || continue
            qualified["pdptw:"*name] = checks["test:"*test]["status"]
            solvers[name]["qualification"] = qualified["pdptw:"*name]
            solvers[name]["qualification_scope"] = "original_PDPTW_functional_tests"
        end
        if solvers["hexaly"]["status"]=="available"
            command = addenv(launcher(opts,joinpath(ROOT,"LiLim/test/hexaly_native.jl"),String[];threads=1),
                "HEXALY_EXECUTABLE"=>get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly")),
                "JULIACONSTRAINTS_REQUIRE_HEXALY"=>"1")
            result = NativeSolvers.capture(command;timeout=300)
            ok = result.code==0 && !result.timed_out
            qualified["pdptw:hexaly"] = ok ? "passed" : "failed"
            solvers["hexaly"]["qualification"] = qualified["pdptw:hexaly"]
            solvers["hexaly"]["qualification_scope"] = "original_PDPTW_functional_tests"
            checks["test:hexaly_native.jl"] = Dict("status"=>qualified["pdptw:hexaly"],
                "reason"=>result.timed_out ? "qualification_timeout" : "exit_code_"*string(result.code))
        end
    end
    if solvers["ortools"]["status"]=="skipped"
        for name in keys(solvers["ortools"]["profiles"])
            solvers["ortools"]["profiles"][name]=Dict("status"=>"skipped","reason"=>solvers["ortools"]["reason"])
        end
    end
    rows = HexalyPreflight.coverage(ROOT,DEV,c;solvers,qualification=qualified,environment_ok)
    ready = count(row->row["status"]=="ready_available_solvers",rows)
    failed = any(state->state["status"]=="failed",values(checks)) ||
        any(state->state["status"]=="failed",values(solvers))
    active=count(row->row["status"]!="deferred_continuous",rows)
    report = Dict{String,Any}("schema"=>"solver-benchmark-preflight/1","source"=>c["source"],
        "catalogue_sha256"=>digest(joinpath(ROOT,"LiLim/config/hexaly-benchmark-catalog.toml")),
        "checked_at_utc"=>string(HexalyPreflight.Dates.now(HexalyPreflight.Dates.UTC)),"entry_count"=>length(rows),
        "status"=>failed ? "failed" : ready==active ? "ready" : "blocked",
        "host"=>Dict("os"=>string(Sys.KERNEL),"architecture"=>string(Sys.ARCH),"julia"=>string(VERSION),
            "cpus"=>host_cpus,"ram_gib"=>round(Sys.total_memory()/2.0^30;digits=1)),
        "checks"=>checks,"solvers"=>solvers,"benchmarks"=>rows)
    HexalyPreflight.save_report(output,report)
    println("Li-Lim original-model checks: ",get(qualified,"pdptw:core","not_run"),"; report: ",joinpath(output,"report.md"))
    report["status"]=="ready" ? 0 : report["status"]=="failed" ? 1 : 2
end

"Prepare the colleague's host and require actual licensed Hexaly qualification."
function check(opts; hexaly_resolver=NativeSolvers.resolve_hexaly,
        setup_runner=setup, qualification_runner=qualify)
    string(VERSION)=="1.13.1" || error("Install Julia 1.13.1 first.")
    for program in (Sys.islinux() ? ("git","taskset","lscpu") : ("git",))
        Sys.which(program)===nothing && error("Missing prerequisite: $program")
    end
    order=topology()
    width=parse(Int,get(opts,"threads","1"))
    1<=width<=length(order) || error("Requested worker count exceeds available CPUs")
    println("Host: ",Sys.KERNEL," / ",Sys.ARCH,"; Julia ",VERSION,
        "; available logical CPUs: ",length(order),"; RAM: ",round(Sys.total_memory()/2.0^30;digits=1)," GiB")
    # Fail before setup if Hexaly cannot execute a licensed 15.0 model.
    prepared=copy(opts)
    prepared["hexaly"]=hexaly_resolver(get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly")))
    setup_runner(prepared)
    qualification_runner(prepared; require_hexaly=true)
    println("READY: Hexaly 15.0 and original PDPTW model qualification passed. No comparative campaign was started.")
end

function report(opts)
    haskey(opts,"output") || error("report requires --output=CAMPAIGN_DIR")
    output = abspath(opts["output"])
    launch(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_report.jl"),[output];threads=1))
    summary = joinpath(output,"summary.toml")
    isempty(TOML.parsefile(summary)["methods"]) && return
    for style in ("exact","xkcd")
        launch(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_plots.jl"),[summary,joinpath(output,"figures-"*style),style];plot=true,threads=1))
    end
end

function campaign_arguments(opts)
    haskey(opts,"output") || error("run requires --output=NEW_DIR (existing campaigns need --resume=true)")
    width = parse(Int,get(opts,"threads","1"))
    methods = "panel"
    args = ["--threads=$width","--budget="*get(opts,"budget","60"),"--output="*abspath(opts["output"]),
        "--instances="*get(opts,"instances","lc101,lr101,lrc101"),"--methods="*get(opts,"methods",methods),
        "--seeds="*get(opts,"seeds","41,42,43"),"--ortools="*get(opts,"ortools",PYTHON),"--missing-solvers="*get(opts,"missing-solvers","skip")]
    haskey(opts,"hexaly") && push!(args,"--hexaly="*opts["hexaly"])
    get(opts,"resume","false")=="true" && push!(args,"--resume")
    for key in ("order","control-dir","worker-slot","gc-threshold")
        haskey(opts,key) && push!(args,"--$key="*opts[key])
    end
    args
end
function campaign(opts)
    args=campaign_arguments(opts)
    launch(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_campaign.jl"),args))
    report(opts)
end

"Disjoint CPU masks and a hard total slot cap; small hosts get successive waves."
function matrix_waves(cpus,widths=[1,2,4];slots=4)
    allunique(cpus) && !isempty(cpus) && all(>=(0),cpus) || throw(ArgumentError("distinct allocated CPU IDs required"))
    allunique(widths) && !isempty(widths) && all(w->w in (1,2,4),widths) || throw(ArgumentError("matrix widths are 1/2/4"))
    1<=slots<=8 || throw(ArgumentError("CPU slot cap must be between 1 and 8"))
    capacity=min(slots,length(cpus));maximum(widths)<=capacity || throw(ArgumentError("insufficient allocated CPUs"))
    waves=Vector{NamedTuple}[];wave=NamedTuple[];used=0
    for width in widths
        if used+width>capacity;push!(waves,wave);wave=NamedTuple[];used=0;end
        push!(wave,(;width,cpus=cpus[used+1:used+width]));used+=width
    end
    isempty(wave) || push!(waves,wave)
    waves
end

"Explicit future campaign command; reports/rendering run only after every solve has joined."
function campaign_matrix(opts)
    all(k->haskey(opts,k),("output","instances","methods")) || error("matrix requires explicit --output, --instances and --methods")
    widths=parse.(Int,split(get(opts,"widths","1,2,4"),','));slots=parse(Int,get(opts,"cpu-slots","4"))
    cpus=haskey(opts,"cpus") ? parse.(Int,split(opts["cpus"],',')) : topology()
    waves=matrix_waves(cpus,widths;slots)
    output=abspath(opts["output"]);resume=get(opts,"resume","false")=="true"
    ispath(output) && !resume && error("Existing matrix preserved; use --resume=true")
    plan=Dict("schema"=>"li-lim-worker-matrix/1","widths"=>widths,"seeds"=>parse.(Int,split(get(opts,"seeds","41,42"),',')),
        "budget_seconds"=>parse(Float64,get(opts,"budget","60")),"instances"=>opts["instances"],"methods"=>opts["methods"],
        "cpu_slot_cap"=>slots,"waves"=>[[Dict("width"=>job.width,"cpus"=>job.cpus) for job in wave] for wave in waves],
        "comparison_scope"=>"concurrent disjoint masks; shared cache and memory bandwidth can still affect timings")
    path=joinpath(output,"matrix-plan.toml")
    isfile(path) && TOML.parsefile(path)!=plan && error("Matrix identity changed; sealed trials are preserved")
    mkpath(output);isfile(path) || open(io->TOML.print(io,plan;sorted=true),path,"w")
    children=Dict{String,String}[]
    for wave in waves
        running=Pair{Dict{String,String},Any}[]
        for job in wave
            child=Dict(k=>v for (k,v) in opts if !(k in ("widths","cpu-slots")))
            child["threads"]=string(job.width);child["cpus"]=join(job.cpus,',')
            child["seeds"]=get(opts,"seeds","41,42");child["budget"]=get(opts,"budget","60")
            child["output"]=joinpath(output,"workers-"*string(job.width))
            push!(children,child)
            manifest=joinpath(child["output"],"manifest.toml")
            isfile(manifest) && get(TOML.parsefile(manifest),"complete",false) && continue
            child["resume"]=isdir(child["output"]) ? "true" : "false"
            command=launcher(child,joinpath(ROOT,"LiLim/scripts/full_corpus_campaign.jl"),campaign_arguments(child))
            println("Starting ",job.width," workers on CPU IDs ",join(job.cpus,','),"; two default repetition seeds.")
            push!(running,child=>run(command;wait=false))
        end
        # Join the entire wave even on failure, preserving every child's sealed trials.
        for (_,process) in running;wait(process);end
        all(pair->success(last(pair)),running) || error("A matrix child failed; sealed trials preserved, later waves deferred")
    end
    for child in children;report(child);end
end

"Six-size, configuration-first screening, with two persistent four-core workers."
function screening(opts)
    Sys.islinux() || error("Adaptive resource admission requires Linux")
    isempty(strip(read(`git -C $ROOT status --porcelain --untracked-files=no`,String))) ||
        error("Commit screening sources before launch; existing changes are preserved")
    haskey(opts,"output") || error("screening requires --output=NEW_DIRECTORY")
    output=abspath(opts["output"]);resume=get(opts,"resume","false")=="true"
    ispath(output) && !resume && error("Existing screening preserved; use an explicit matching resume")
    for marker in ("STOP_AFTER_TRIAL","PROCESS_FAILURE.toml")
        isfile(joinpath(output,marker)) && error("Resolve the existing stop explicitly before resuming: $marker")
    end
    if isdir(output)
        isempty(ScreeningControl.halt_reason(output)) || error("GC review is unresolved; preserve this cohort and qualify a correction")
    end
    interval=parse(Float64,get(opts,"resource-interval","30"))
    1<=interval<=30 || error("Resource checks must recur at least every 30 seconds")
    cpus=haskey(opts,"cpus") ? parse.(Int,split(opts["cpus"],',')) : topology()[1:8]
    length(cpus)==8 && allunique(cpus) || error("Screening requires eight distinct allocated CPU IDs")
    # Refuse P-core sibling overlap even when logical IDs differ.
    core_keys=[(read("/sys/devices/system/cpu/cpu$c/topology/physical_package_id",String),
        read("/sys/devices/system/cpu/cpu$c/topology/core_id",String)) for c in cpus]
    allunique(core_keys) || error("Two screening lanes cannot share a physical core")
    methods=CampaignCatalog.select_methods(4,"extended-panel,routing-panel")
    length(methods)==548 || error("Screening must contain exactly the authorized 548 existing configurations")
    selection_seed=parse(Int,get(opts,"selection-seed","20261009"))
    selected=ScreeningControl.sample_instances(TOML.parsefile(joinpath(ROOT,"LiLim/config/sintef-pdptw-bks-20261004.toml")),selection_seed)
    methods=ScreeningControl.Random.shuffle(ScreeningControl.Random.Xoshiro(selection_seed+1),methods)
    budget=parse(Float64,get(opts,"budget","60"));budget==60 || error("Screening trial duration is exactly 60 seconds")
    seeds=parse.(Int,split(get(opts,"seeds","41"),','));length(seeds)==1 || error("Preliminary screening uses one repetition")
    threshold=parse(Float64,get(opts,"gc-threshold","0.10"));0<threshold<=1 || error("Invalid GC threshold")
    plan=Dict{String,Any}("schema"=>"li-lim-six-size-screening/1", "selection_seed"=>selection_seed,
        "instances"=>selected,"methods"=>methods,"threads"=>4,"maximum_concurrent_configurations"=>2,
        "budget_seconds"=>budget,"seeds"=>seeds,"gc_alert_fraction"=>threshold,
        "resource_interval_seconds"=>interval,"cpu_masks"=>[cpus[1:4],cpus[5:8]],
        "benchmarks_commit"=>strip(read(`git -C $ROOT rev-parse HEAD`,String)),
        "cohort"=>CONFIG["cohort"],"total_trials"=>548*6,
        "early_bks_stop"=>false,"report_policy"=>"Each configuration after its six validated trials; per-instance values, one repetition.",
        "resource_policy"=>"Two/one/zero configurations; recheck within 30 seconds. Human stops and GC reviews require explicit resolution.")
    path=joinpath(output,"screening-plan.toml")
    if resume
        isfile(path) || error("Cannot resume without the frozen screening plan")
        TOML.parsefile(path)==plan || error("Screening source/selection/protocol changed; preserve existing evidence")
    else
        mkpath(output);ScreeningControl.atomic(path,plan)
    end
    jobs=[(;slot,cpus=cpus[(4slot-3):4slot],methods=methods[slot:2:end],output=joinpath(output,"slot-$slot")) for slot in 1:2]
    function child_command(job)
        child=copy(opts)
        child["threads"]="4";child["cpus"]=join(job.cpus,',');child["output"]=job.output
        child["methods"]=join(job.methods,',');child["instances"]=join(getindex.(selected,"id"),',')
        child["budget"]="60";child["seeds"]=join(seeds,',');child["order"]="method"
        child["control-dir"]=output;child["worker-slot"]=string(job.slot)
        child["gc-threshold"]=string(threshold);child["missing-solvers"]="error"
        child["resume"]=isfile(joinpath(job.output,"manifest.toml")) ? "true" : "false"
        launcher(child,joinpath(ROOT,"LiLim/scripts/full_corpus_campaign.jl"),campaign_arguments(child))
    end
    println("Screening: 548 configurations × six instances × one four-core run; full 60-second budget.")
    println("Instances: ",join([string(r["size"])*":"*r["id"] for r in selected],", "));flush(stdout)
    ScreeningControl.controller(output,jobs,child_command;interval)
end

function export_results(opts)
    haskey(opts,"output") || error("export requires --output=CAMPAIGN_DIR")
    directory = abspath(opts["output"])
    TOML.parsefile(joinpath(directory,"manifest.toml"))["complete"] || error("Complete and validate the campaign before export")
    report(opts)
    archive = directory*".tar.gz"
    ispath(archive) && error("Existing result archive preserved: $archive")
    # Sealed route evidence is required for independent verification. It is sent
    # as an archive, never pushed as bulk data into the source repository.
    run(`tar -czf $archive -C $(dirname(directory)) $(basename(directory))`)
    println("Return this evidence archive: ",archive)
end

function main(args=ARGS)
    isempty(args) && error("usage: colleague.jl preflight|check|setup|qualify|run|lilim-screening|report|export [--name=value]")
    command=first(args); opts=options(args[2:end])
    if command=="preflight"; exit(preflight(opts))
    elseif command=="check"; check(opts)
    elseif command=="setup"; setup(opts)
    elseif command=="qualify"; qualify(opts)
    elseif command=="run"; campaign(opts)
    elseif command=="lilim-screening"; screening(opts)
    elseif command=="report"; report(opts)
    elseif command=="export"; export_results(opts)
    else; error("unknown command: "*command)
    end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && main()
