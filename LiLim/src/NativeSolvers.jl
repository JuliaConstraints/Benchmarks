module NativeSolvers
using SHA, TOML, Pkg
include("SolverArtifacts.jl")
include("PlatformResources.jl")

struct UnavailableSolver <: Exception
    method::String
    reason::String
end
Base.showerror(io::IO, e::UnavailableSolver) = print(io, e.method, ": ", e.reason)
digest(path) = bytes2hex(sha256(read(path)))

function default_python(root)
    haskey(ENV,"ORTOOLS_PYTHON") && return ENV["ORTOOLS_PYTHON"]
    local_python=joinpath(root,"LiLim/native/ortools/.venv",Sys.iswindows() ? "Scripts/python.exe" : "bin/python")
    isfile(local_python) && return local_python
    # setup-python and the standard Windows installer expose python.exe;
    # an unrelated python3 alias can point to another ABI on the same PATH.
    for name in (Sys.iswindows() ? ("python","python3") : ("python3","python"))
        path=Sys.which(name)
        path===nothing || return path
    end
    "python3"
end

function executable(name)
    path = isfile(name) ? abspath(name) : Sys.which(name)
    path === nothing && return nothing
    (Sys.iswindows() || (stat(path).mode & 0o111) != 0) || return nothing
    path
end

"Bounded installation probes; do not copy vendor diagnostics or license content."
function capture(command; timeout=15)
    mktemp() do _, io
        process = run(pipeline(ignorestatus(command), stdout=io, stderr=io); wait=false)
        state = timedwait(() -> process_exited(process), timeout; pollint=0.02)
        if state === :timed_out
            kill(process)
            wait(process)
            return (; code=-1, output="", timed_out=true)
        end
        wait(process)
        seekstart(io)
        (; code=process.exitcode, output=String(read(io, 32_768)), timed_out=false)
    end
end

function python_command(identity, arguments...)
    command = `$(identity["python"]) $arguments`
    path = get(identity, "python_path", "")
    isempty(path) ? command : addenv(command, "PYTHONPATH"=>path, "PYTHONNOUSERSITE"=>"1")
end

function ortools_identity(python; python_path="", probe=capture)
    candidate = executable(python)
    candidate === nothing && throw(UnavailableSolver("ortools_native", "python_not_found"))
    code = "import sys, importlib.util; print('PYTHON|' + sys.version.split()[0]); spec=importlib.util.find_spec('ortools'); print('MISSING' if spec is None else 'PRESENT'); " *
        "import ortools; from ortools.constraint_solver import _pywrapcp; print('ORTOOLS|' + ortools.__version__ + '|' + _pywrapcp.__file__)"
    command = isempty(python_path) ? `$candidate -c $code` :
        addenv(`$candidate -c $code`, "PYTHONPATH"=>python_path, "PYTHONNOUSERSITE"=>"1")
    result = probe(command)
    result.timed_out && throw(UnavailableSolver("ortools_native", "import_probe_timed_out"))
    lines = strip.(split(result.output, '\n'))
    version_line = findfirst(l->startswith(l, "PYTHON|"), lines)
    python_version = version_line === nothing ? "unknown" : split(lines[version_line], '|')[2]
    result.code == 0 || throw(UnavailableSolver("ortools_native",
        "MISSING" in lines ? "package_not_installed" : "native_import_failed"))
    line = findfirst(l->startswith(l, "ORTOOLS|"), lines)
    line === nothing && error("Malformed OR-Tools installation probe")
    parts = split(lines[line], '|'; limit=3)
    length(parts)==3 || error("Malformed OR-Tools version response")
    parts[2]=="9.14.6206" || throw(UnavailableSolver("ortools_native", "unsupported_version_" * parts[2]))
    Dict{String,Any}("python"=>abspath(candidate), "python_version"=>python_version,
        "python_path"=>python_path, "python_executable_sha256"=>digest(realpath(candidate)),
        "ortools_version"=>parts[2], "native_module_sha256"=>digest(parts[3]))
end

"Try an existing installation first, then an already-cached artifact SDK. Never install here."
function resolve_ortools(python; root, probe=capture)
    explicit_path = get(ENV, "ORTOOLS_PYTHONPATH", "")
    identity = try
        ortools_identity(python; python_path=explicit_path, probe)
    catch e
        e isa UnavailableSolver || rethrow()
        e.reason=="package_not_installed" || rethrow()
        paths = SolverArtifacts.python_paths()
        paths === nothing && rethrow()
        ortools_identity(python; python_path=SolverArtifacts.python_path(paths), probe)
    end
    identity["runner_sha256"] = digest(joinpath(root,"LiLim/native/ortools/pdptw.py"))
    identity["requirements_sha256"] = digest(joinpath(root,"LiLim/native/ortools/requirements.txt"))
    identity
end

"Install only a missing SDK; an existing incompatible or broken installation is preserved."
function install_ortools(python; root, resolver=resolve_ortools,
    installer=()->SolverArtifacts.python_paths(;install=true))
    try
        return resolver(python; root)
    catch e
        e isa UnavailableSolver || rethrow()
        e.reason=="package_not_installed" || rethrow()
    end
    candidate = executable(python)
    version = capture(`$candidate -c "import sys; print(str(sys.version_info.major) + '.' + str(sys.version_info.minor))"`)
    version.code==0 && strip(version.output)=="3.12" ||
        throw(UnavailableSolver("ortools_native", "missing_sdk_requires_python_3.12"))
    paths = installer()
    paths === nothing && throw(UnavailableSolver("ortools_native", "no_artifact_for_host_platform"))
    resolver(python; root)
end

function resolve_hexaly(name; probe=capture)
    candidate = executable(name)
    candidate === nothing && throw(UnavailableSolver("hexaly_native", "executable_not_found"))
    # Vendor-documented license test, with a tiny original model and a one-second cap.
    result = mktempdir() do directory
        model = joinpath(directory,"availability.hxm")
        write(model, "function model() { x = bool(); minimize(x); }\nfunction output() { println(\"JULIACONSTRAINTS_HEXALY_READY\"); }\n")
        probe(`$candidate $model hxTimeLimit=1 hxNbThreads=1`)
    end
    result.timed_out && throw(UnavailableSolver("hexaly_native", "license_probe_timed_out"))
    if result.code != 0
        occursin(r"(?i)licen[cs]e", result.output) &&
            throw(UnavailableSolver("hexaly_native", "license_unavailable"))
        error("Hexaly availability model failed; this is a qualification error, not a missing solver")
    end
    occursin("JULIACONSTRAINTS_HEXALY_READY", result.output) || error("Hexaly probe did not execute its output callback")
    version = match(r"(?i)(?:hexaly(?: optimizer)?|version)\s+(\d+\.\d+)",result.output)
    version === nothing && throw(UnavailableSolver("hexaly_native","version_not_reported"))
    version[1]!="15.0" &&
        throw(UnavailableSolver("hexaly_native", "unsupported_version_" * version[1]))
    realpath(candidate)
end

"Only explicitly unavailable optional solvers may be skipped; defects still fail."
function resolve_ghost(; root, install=false)
    environment = joinpath(root,"LiLim/native/ghost/environment")
    metadata = joinpath(environment,"qualification.toml")
    isfile(metadata) || throw(UnavailableSolver("ghost_icn","run_setup_for_ghost_environment"))
    saved = TOML.parsefile(metadata)
    for name in ("Project.toml","Manifest.toml")
        digest(joinpath(environment,name)) == saved[name] || error("GHOST optional environment changed: $name")
    end
    cohort = TOML.parsefile(joinpath(root,"LiLim/config/workspace-cohort.toml"))["optional_cohort"]
    for (name,entry) in cohort
        path = saved["sources"][name]
        strip(read(`git -C $path rev-parse HEAD`,String)) == entry["commit"] || error("GHOST source cohort changed: $name")
        isempty(strip(read(`git -C $path status --porcelain --untracked-files=no`,String))) || error("Dirty optional source: $name")
    end
    environment in LOAD_PATH || push!(LOAD_PATH,environment)
    @eval import GHOST_jll
    path_resolver = @eval GHOST_jll.library_path
    library = try
        Base.invokelatest(path_resolver; install)
    catch exception
        message = sprint(showerror,exception)
        occursin("not installed",message) && throw(UnavailableSolver("ghost_icn","artifact_not_installed"))
        occursin("no qualified Artifact",message) && throw(UnavailableSolver("ghost_icn","no_artifact_for_host_platform"))
        rethrow()
    end
    merge(saved,Dict("library_sha256"=>digest(library),"native_library"=>library))
end

function resolve_requested(methods; missing="skip", ortools_resolver, hexaly_resolver,
    ghost_resolver=()->throw(UnavailableSolver("ghost_icn","wrapper_environment_unavailable")))
    missing in ("skip","error") || throw(ArgumentError("missing-solvers must be skip or error"))
    selected = String[]; skipped = Dict{String,String}[]
    ortools = nothing; hexaly = nothing; ghost = nothing
    for method in methods
        try
            method=="ortools_native" && (ortools=ortools_resolver())
            method=="hexaly_native" && (hexaly=hexaly_resolver())
            method=="ghost_icn" && (ghost=ghost_resolver())
            push!(selected,method)
        catch e
            e isa UnavailableSolver && missing=="skip" || rethrow()
            push!(skipped,Dict("method"=>method,"status"=>"skipped","reason"=>e.reason))
        end
    end
    (; methods=selected, skipped, ortools, hexaly, ghost)
end
include("TimefoldRuntime.jl")
end
