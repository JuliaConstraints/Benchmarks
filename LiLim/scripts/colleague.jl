# Public, pinned Linux handoff: setup, qualify, run, report, and export.
using TOML, SHA, Downloads
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CONFIG = TOML.parsefile(joinpath(ROOT,"LiLim/config/workspace-cohort.toml"))
const DEV = abspath(get(ENV,"JULIACONSTRAINTS_COHORT_ROOT",joinpath(homedir(),".julia/dev/JuliaConstraintsBench")))
const SOLVER_ENV = joinpath(DEV,"ConstraintModels/perf/pdptw")
const PYTHON = get(ENV,"ORTOOLS_PYTHON",joinpath(ROOT,"LiLim/native/ortools/.venv/bin/python"))
digest(path) = bytes2hex(sha256(read(path)))

function options(args)
    result = Dict{String,String}()
    for arg in args
        startswith(arg,"--") && occursin('=',arg) || error("use --name=value")
        key,value = split(arg[3:end],'=';limit=2)
        key in ("threads","cpus","budget","methods","instances","seeds","hexaly","output","resume") || error("unknown option: $key")
        haskey(result,key) && error("duplicate option: $key")
        result[key] = value
    end
    result
end

function topology()
    Sys.islinux() || error("This qualified handoff requires Linux (taskset and /proc CPU accounting).")
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
    cmd = `taskset --cpu-list $(join(selected,',')) $(Base.julia_cmd()) --startup-file=no --threads=$threads --gcthreads=1 --project=$environment $script $arguments`
    addenv(cmd,"OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1","MKL_NUM_THREADS"=>"1",
        "JULIA_NUM_PRECOMPILE_TASKS"=>"1","JULIACONSTRAINTS_COHORT_ROOT"=>DEV,
        "JULIACONSTRAINTS_CPU_ORDER"=>join(order,','),"JULIACONSTRAINTS_TEST_CPU"=>string(first(selected)),
        "ORTOOLS_PYTHON"=>PYTHON)
end

function setup()
    string(VERSION)=="1.13.1" || error("Install Julia 1.13.1 first; the solver manifest is frozen to that version.")
    for program in ("git","taskset","lscpu","unzip","python3")
        Sys.which(program)===nothing && error("Missing prerequisite: $program")
    end
    mkpath(DEV)
    for (name,sha) in sort!(collect(CONFIG["cohort"]))
        path = joinpath(DEV,name)
        if !ispath(path)
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
    if !isfile(PYTHON)
        venv = dirname(dirname(PYTHON))
        ispath(venv) && error("Incomplete existing Python environment preserved: $venv")
        run(`python3 -m venv $venv`)
        requirements = joinpath(ROOT,"LiLim/native/ortools/requirements.txt")
        run(`$PYTHON -m pip install -r $requirements`)
    end
    run(`$PYTHON -m pip check`)
    run(`$PYTHON -c "import ortools; from ortools.constraint_solver import pywrapcp; assert ortools.__version__ == '9.14.6206'; print('OR-Tools', ortools.__version__)"`)
    data_setup()
    println("Pinned source, environments and official data ready. Next: julia LiLim/scripts/colleague.jl qualify")
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
        entries = split(chomp(read(`unzip -Z -1 $archive`,String)),'\n')
        for id in keys(bks["instances"][size])
            path = joinpath(ROOT,"LiLim/data/raw/pdp_"*size,id*".txt")
            expected = bks["instance_sha256"][size*"."*id]
            if !isfile(path)
                entry = only(filter(e->lowercase(basename(e))==id*".txt",entries))
                bytes = read(`unzip -p $archive $entry`)
                bytes2hex(sha256(bytes))==expected || error("Official instance bytes differ: $id")
                mkpath(dirname(path)); write(path,bytes)
            end
            digest(path)==expected || error("Existing instance checksum mismatch: $id")
        end
    end
    println("All 354 official instances and six archives verified.")
end

function qualify(opts)
    for test in ("competitors.jl","hybrid.jl","icn_resources.jl","ortools_native.jl")
        run(launcher(opts,joinpath(ROOT,"LiLim/test",test),String[];threads=1))
    end
    run(launcher(opts,joinpath(ROOT,"LiLim/test/search_policies.jl"),["--routes"];threads=1))
    if haskey(opts,"hexaly")
        run(addenv(launcher(opts,joinpath(ROOT,"LiLim/test/hexaly_native.jl"),String[];threads=1),"HEXALY_EXECUTABLE"=>opts["hexaly"]))
    end
end

function report(opts)
    haskey(opts,"output") || error("report requires --output=CAMPAIGN_DIR")
    output = abspath(opts["output"])
    run(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_report.jl"),[output];threads=1))
    summary = joinpath(output,"summary.toml")
    for style in ("exact","xkcd")
        run(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_plots.jl"),[summary,joinpath(output,"figures-"*style),style];plot=true,threads=1))
    end
end

function campaign(opts)
    haskey(opts,"output") || error("run requires --output=NEW_DIR (existing campaigns need --resume=true)")
    width = parse(Int,get(opts,"threads","1"))
    methods = "ortools_native,cbls_icn,hybrid_specialized_icn,hybrid_bridged_icn,highs_native"
    width>=4 && (methods *= ",cbls_mix_strategy,mixed_balanced,mixed_ls_heavy")
    args = ["--threads=$width","--budget="*get(opts,"budget","60"),"--output="*abspath(opts["output"]),
        "--instances="*get(opts,"instances","lc101,lr101,lrc101"),"--methods="*get(opts,"methods",methods),
        "--seeds="*get(opts,"seeds","41,42,43"),"--ortools="*PYTHON]
    haskey(opts,"hexaly") && push!(args,"--hexaly="*opts["hexaly"])
    get(opts,"resume","false")=="true" && push!(args,"--resume")
    run(launcher(opts,joinpath(ROOT,"LiLim/scripts/full_corpus_campaign.jl"),args))
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

isempty(ARGS) && error("usage: colleague.jl setup|qualify|run|report|export [--name=value]")
command = first(ARGS); opts = options(ARGS[2:end])
if command=="setup"; setup()
elseif command=="qualify"; qualify(opts)
elseif command=="run"; campaign(opts)
elseif command=="report"; report(opts)
elseif command=="export"; export_results(opts)
else; error("unknown command: $command")
end
