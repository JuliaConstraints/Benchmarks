# Pinned handoff: setup, qualify, run, report, and export.
using TOML, SHA, Downloads, Pkg
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))
include(joinpath(@__DIR__,"..","src","PlatformResources.jl"))
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CONFIG = TOML.parsefile(joinpath(ROOT,"LiLim/config/workspace-cohort.toml"))
const DEV = abspath(get(ENV,"JULIACONSTRAINTS_COHORT_ROOT",joinpath(homedir(),".julia/dev/JuliaConstraintsBench")))
const SOLVER_ENV = joinpath(DEV,"ConstraintModels/perf/pdptw")
const PYTHON=NativeSolvers.default_python(ROOT)
digest(path) = bytes2hex(sha256(read(path)))

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
        key in ("threads","cpus","budget","methods","instances","seeds","hexaly","output","resume","ortools","missing-solvers") || error("unknown option: $key")
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
        "ORTOOLS_PYTHON"=>get(options,"ortools",PYTHON))
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
            branch = CONFIG["public_branch"]
            run(`git clone --single-branch --branch $branch $url $path`)
        end
        isdir(joinpath(path,".git")) || error("Not a development clone: $path")
        strip(read(`git -C $path rev-parse HEAD`,String))==sha || error("Cohort mismatch at $path; existing files were preserved.")
        isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String))) || error("Dirty dependency: $path")
    end
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
    data_setup()
    println("Pinned source, environments and official data ready. Next: julia LiLim/scripts/colleague.jl qualify")
end

"Derive the optional wrapper environment without changing the frozen core."
function setup_ghost()
    entries = CONFIG["optional_cohort"]
    sources = Dict{String,String}()
    for (name,entry) in sort!(collect(entries);by=first)
        path = joinpath(DEV,name)
        if !ispath(path)
            run(`git clone --single-branch --branch $(entry["branch"]) $(entry["url"]) $path`)
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

function qualify(opts)
    for test in ("ghost_frontend.jl","native_solvers.jl","campaign_catalog.jl","competitors.jl","hybrid.jl","icn_resources.jl","ortools_native.jl")
        launch(launcher(opts,joinpath(ROOT,"LiLim/test",test),String[];threads=1))
    end
    launch(launcher(opts,joinpath(ROOT,"LiLim/test/search_policies.jl"),["--routes"];threads=1))
    launch(launcher(opts,joinpath(ROOT,"LiLim/test/ghost_native.jl"),String[];threads=1))
    launch(addenv(launcher(opts,joinpath(ROOT,"LiLim/test/hexaly_native.jl"),String[];threads=1),
        "HEXALY_EXECUTABLE"=>get(opts,"hexaly",get(ENV,"HEXALY_EXECUTABLE","hexaly"))))
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

function campaign(opts)
    haskey(opts,"output") || error("run requires --output=NEW_DIR (existing campaigns need --resume=true)")
    width = parse(Int,get(opts,"threads","1"))
    methods = "panel"
    args = ["--threads=$width","--budget="*get(opts,"budget","60"),"--output="*abspath(opts["output"]),
        "--instances="*get(opts,"instances","lc101,lr101,lrc101"),"--methods="*get(opts,"methods",methods),
        "--seeds="*get(opts,"seeds","41,42,43"),"--ortools="*get(opts,"ortools",PYTHON),"--missing-solvers="*get(opts,"missing-solvers","skip")]
    haskey(opts,"hexaly") && push!(args,"--hexaly="*opts["hexaly"])
    get(opts,"resume","false")=="true" && push!(args,"--resume")
    launch(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_campaign.jl"),args))
    report(opts)
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
    isempty(args) && error("usage: colleague.jl setup|qualify|run|report|export [--name=value]")
    command=first(args); opts=options(args[2:end])
    if command=="setup"; setup(opts)
    elseif command=="qualify"; qualify(opts)
    elseif command=="run"; campaign(opts)
    elseif command=="report"; report(opts)
    elseif command=="export"; export_results(opts)
    else; error("unknown command: "*command)
    end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && main()
