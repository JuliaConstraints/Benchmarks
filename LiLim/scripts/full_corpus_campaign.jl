using ConstraintModels, JuMP, TOML, SHA, Dates, LinearAlgebra, Pkg
using ConstraintModels.Benchmarks

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RUNNER_PATH = abspath(@__FILE__)
include(joinpath(ROOT, "LiLim", "src", "BenchmarkTargets.jl"))
for source in ("Pilot", "MetaRepair", "ICNScoring", "Hybrid", "ResourceExperiment")
    include(joinpath(ROOT, "LiLim", "src", source * ".jl"))
end
include(joinpath(ROOT, "LiLim", "competitors", "Adapters.jl"))
include(joinpath(ROOT, "LiLim", "src", "NativeSolvers.jl"))
include(joinpath(ROOT, "LiLim", "src", "CampaignCatalog.jl"))
using .CampaignCatalog: select_methods, available_methods
const PlatformResources=ResourceExperiment.PlatformResources

const THREAD_CONFIG = TOML.parsefile(joinpath(ROOT, "LiLim", "config", "icn-threads.toml"))
const CAMPAIGN_CONFIG_PATH = joinpath(ROOT, "LiLim", "config", "full-corpus-campaign.toml")
const CAMPAIGN_CONFIG = TOML.parsefile(CAMPAIGN_CONFIG_PATH)
const BASELINE_PATH = joinpath(ROOT, "LiLim", "config", "current-pilot.toml")
const BASELINE = TOML.parsefile(BASELINE_PATH)
const COHORT_PATH = joinpath(ROOT, "LiLim", "config", "workspace-cohort.toml")
const COHORT_CONFIG = TOML.parsefile(COHORT_PATH)
const COHORT = COHORT_CONFIG["cohort"]
const SOLVER_ENVIRONMENT = get(COHORT_CONFIG,"environment",BASELINE["environment"])
const COHORT_ROOT = get(ENV, "JULIACONSTRAINTS_COHORT_ROOT", dirname(pkgdir(ConstraintModels)))
const CPU_ORDER = haskey(ENV, "JULIACONSTRAINTS_CPU_ORDER") ?
    parse.(Int, split(ENV["JULIACONSTRAINTS_CPU_ORDER"], ',')) : (Sys.islinux() ? CAMPAIGN_CONFIG["cpu_order"] : PlatformResources.allowed_cpus())
const BKS_PATH = joinpath(ROOT, "LiLim", "config", "sintef-pdptw-bks-20261004.toml")
const BKS = TOML.parsefile(BKS_PATH)
const HEXALY_CONFIG_PATH = joinpath(ROOT, "LiLim", "config", "competitors.toml")
const HEXALY_CONFIG = TOML.parsefile(HEXALY_CONFIG_PATH)["hexaly"]
digest(path) = bytes2hex(sha256(read(path)))

function cli(args)
    values = Dict{String,String}()
    resume = false
    for arg in args
        if arg == "--resume"
            resume = true
            continue
        end
        startswith(arg, "--") && occursin('=', arg) || error("options must use --name=value")
        name, value = split(arg[3:end], '='; limit=2)
        name in ("budget", "output", "threads", "instances", "methods", "seeds", "hexaly", "ortools", "missing-solvers") || error("unknown option --$name")
        haskey(values, name) && error("duplicate option --$name")
        values[name] = value
    end
    all(key -> haskey(values, key), ("budget", "output", "threads")) ||
        error("usage: full_corpus_campaign.jl --budget=SECONDS --output=DIR --threads=N [--instances=all|ID,...] [--methods=all|strategies|NAME,...] [--seeds=41,42,43] [--hexaly=PATH] [--ortools=PYTHON] [--resume]")
    budget = parse(Float64, values["budget"])
    isfinite(budget) && budget > 0 || error("budget must be positive and finite")
    default_ortools = NativeSolvers.default_python(ROOT)
    (; budget, output=abspath(values["output"]), threads=parse(Int, values["threads"]),
       instances=get(values, "instances", "all"), methods=get(values, "methods", "all"),
       hexaly=get(values, "hexaly", get(ENV, "HEXALY_EXECUTABLE", "hexaly")),
       ortools=get(values, "ortools", get(ENV, "ORTOOLS_PYTHON", default_ortools)),
       missing_solvers=get(values, "missing-solvers", "skip"),
       seeds=parse.(Int, split(get(values, "seeds", join(THREAD_CONFIG["seeds"], ",")), ',')), resume)
end

function archive_path(size)
    filename = Dict("100"=>"pdp_100.zip", "200"=>"pdp_200.zip", "400"=>"pdp_400.zip",
        "600"=>"pdp_600.zip", "800"=>"pdptw800.zip", "1000"=>"pdptw1000.zip")[size]
    joinpath(ROOT, "LiLim", "data", "raw", "sintef-archives", filename)
end

function corpus()
    rows = NamedTuple[]
    for size in sort(collect(keys(BKS["instances"])); by=x->parse(Int, x))
        archive = archive_path(size)
        isfile(archive) || error("missing official corpus archive: $archive")
        expected_archive = BKS["archive_sha256"][basename(archive)]
        digest(archive) == expected_archive || error("official archive checksum mismatch: $archive")
        group = BKS["instances"][size]
        expected_count = CAMPAIGN_CONFIG["expected_by_size"][size]
        length(group) == expected_count || error("BKS inventory mismatch for size $size")
        for id in sort(collect(keys(group)))
            source_key = size * "." * id
            expected_source = BKS["instance_sha256"][source_key]
            path = joinpath(ROOT, "LiLim", "data", "raw", "pdp_" * size, id * ".txt")
            isfile(path) || error("missing official instance $source_key at $path")
            actual_source = digest(path)
            actual_source == expected_source || error("instance checksum mismatch: $source_key")
            target = group[id]
            push!(rows, (; id, size=parse(Int, size), path, source_sha256=actual_source,
                bks_vehicles=target["vehicles"], bks_distance=target["distance"]))
        end
    end
    length(rows) == CAMPAIGN_CONFIG["expected_instances"] || error("official instance count mismatch")
    rows
end

function select_instances(rows, selector)
    selector == "all" && return rows
    wanted = Set(strip.(split(selector, ',')))
    isempty(wanted) && error("empty instance selection")
    selected = filter(row -> row.id in wanted, rows)
    found = Set(row.id for row in selected)
    missing = setdiff(wanted, found)
    isempty(missing) || error("unknown SINTEF instance names: " * join(sort!(collect(missing)), ", "))
    selected
end

function resolve_hexaly(opts)
    candidate = NativeSolvers.resolve_hexaly(opts.hexaly)
    isinteger(opts.budget) || error("Hexaly requires a whole-second wall budget")
    opts.threads in (1,2,4,8,16) || error("Unsupported Hexaly thread width")
    candidate
end

allowed_cpus()=PlatformResources.allowed_cpus()

function check_environment(threads)
    string(VERSION) == THREAD_CONFIG["julia"] || error("Julia version differs from the qualified campaign")
    Threads.nthreads() == threads || error("launched Julia thread count differs from --threads")
    threads in CAMPAIGN_CONFIG["thread_counts"] || error("thread width is not in the frozen protocol")
    BLAS.get_num_threads() == 1 || error("BLAS must be single-threaded")
    length(CPU_ORDER) >= threads && allunique(CPU_ORDER) || error("invalid CPU order")
    if Sys.islinux()
        sort(allowed_cpus()) == sort(CPU_ORDER[1:threads]) || error("CPU affinity differs from the selected topology order")
    else
        all(c->c in allowed_cpus(),CPU_ORDER[1:threads]) || error("CPU selection exceeds host capacity")
    end
    env = dirname(Base.active_project())
    for (file, key) in (("Project.toml", "project_sha256"), ("Manifest.toml", "manifest_sha256"))
        digest(joinpath(env, file)) == SOLVER_ENVIRONMENT[key] || error("solver environment changed: $file")
    end
    dependencies = Dict(info.name=>info for info in values(Pkg.dependencies()))
    for (name, expected) in COHORT
        repo = joinpath(COHORT_ROOT, name)
        realpath(dependencies[name].source) == realpath(repo) || error("loaded dependency path differs from the checked cohort: $name")
        strip(read(`git -C $repo rev-parse HEAD`, String)) == expected || error("development cohort changed: $name")
        isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`, String))) || error("dirty dependency: $name")
    end
    digest(ICNScoring.BANK) in (THREAD_CONFIG["icn_bank_sha256"], COHORT_CONFIG["portable_icn_bank_sha256"]) || error("recovered ICN bank changed")
    measured = vcat(filter(path -> endswith(path, ".jl"), readdir(joinpath(ROOT, "LiLim", "src"); join=true)),
        [joinpath(ROOT,"LiLim","Artifacts.toml"), CAMPAIGN_CONFIG_PATH, BKS_PATH, BASELINE_PATH, COHORT_PATH,
         joinpath(ROOT, "LiLim", "config", "icn-threads.toml"),
         Hybrid.SearchPolicies.CONFIG_PATH,
         ResourceExperiment.StrategyPanel.CONFIG_PATH,
         joinpath(ROOT, "SolverSmoke", "src", "Profiles.jl"),
         joinpath(ROOT, "LiLim", "test", "search_policies.jl"),
         joinpath(ROOT, "LiLim", "test", "strategy_panel.jl"),
         joinpath(ROOT, "LiLim", "test", "ro_fragments.jl"),
         joinpath(ROOT, "LiLim", "test", "icn_resources.jl"),
         joinpath(ROOT, "LiLim", "test", "competitors.jl"),
         joinpath(ROOT, "LiLim", "competitors", "Adapters.jl"),
         joinpath(ROOT, "LiLim", "native", "ortools", "pdptw.py"),
         joinpath(ROOT, "LiLim", "native", "ortools", "requirements.txt"),
         joinpath(ROOT, "LiLim", "native", "hexaly", "pdptw.hxm"), HEXALY_CONFIG_PATH,
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_report.jl"),
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_plots.jl"), RUNNER_PATH])
    measured_relative = relpath.(measured, ROOT)
    isempty(strip(read(`git -C $ROOT status --porcelain -- $measured_relative`, String))) ||
        error("commit measured Benchmarks sources and configurations before the run")
    nothing
end

function atomic(path, writer)
    mkpath(dirname(path))
    temporary = path * ".partial-" * string(getpid())
    open(temporary, "w") do io
        writer(io)
        flush(io)
    end
    mv(temporary, path; force=true)
    path
end

function stable_sha(value)
    io = IOBuffer()
    TOML.print(io, value; sorted=true)
    bytes2hex(sha256(take!(io)))
end

function source_manifest()
    files = vcat(filter(path -> endswith(path, ".jl"), readdir(joinpath(ROOT, "LiLim", "src"); join=true)),
        [joinpath(ROOT,"LiLim","Artifacts.toml"), RUNNER_PATH, CAMPAIGN_CONFIG_PATH, BKS_PATH, BASELINE_PATH, COHORT_PATH,
         joinpath(ROOT, "LiLim", "config", "icn-threads.toml"),
         Hybrid.SearchPolicies.CONFIG_PATH,
         ResourceExperiment.StrategyPanel.CONFIG_PATH,
         joinpath(ROOT, "SolverSmoke", "src", "Profiles.jl"),
         joinpath(ROOT, "LiLim", "test", "search_policies.jl"),
         joinpath(ROOT, "LiLim", "test", "icn_resources.jl"),
         joinpath(ROOT, "LiLim", "test", "strategy_panel.jl"),
         joinpath(ROOT, "LiLim", "test", "ro_fragments.jl"),
         joinpath(ROOT, "LiLim", "test", "competitors.jl"),
         joinpath(ROOT, "LiLim", "competitors", "Adapters.jl"),
         joinpath(ROOT, "LiLim", "native", "ortools", "pdptw.py"),
         joinpath(ROOT, "LiLim", "native", "ortools", "requirements.txt"),
         joinpath(ROOT, "LiLim", "native", "hexaly", "pdptw.hxm"), HEXALY_CONFIG_PATH,
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_report.jl"),
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_plots.jl")])
    Dict(relpath(abspath(path), ROOT) => digest(path) for path in files)
end

function campaign_identity(opts, instances, methods, hexaly_executable, ortools_identity; requested_methods=methods, skipped_methods=[], ghost_identity=nothing)
    hexaly_identity = hexaly_executable === nothing ? Dict{String,Any}() : Dict{String,Any}(
        "path"=>hexaly_executable,
        "target_version"=>HEXALY_CONFIG["target_version"],
        "binary_sha256"=>digest(hexaly_executable))
    Dict{String,Any}(
        "schema" => CAMPAIGN_CONFIG["schema"],
        "julia" => string(VERSION),
        "benchmarks_commit" => strip(read(`git -C $ROOT rev-parse HEAD`, String)),
        "runner_sha256" => digest(RUNNER_PATH),
        "source_sha256" => source_manifest(),
        "cohort" => COHORT,
        "icn_bank_sha256" => digest(ICNScoring.BANK),
        "cpu_order" => CPU_ORDER,
        "environment" => SOLVER_ENVIRONMENT,
        "official_archive_sha256" => BKS["archive_sha256"],
        "instance_sha256" => Dict(row.id => row.source_sha256 for row in instances),
        "instances" => [row.id for row in instances],
        "targets" => Dict(row.id => Dict("vehicles"=>row.bks_vehicles,"distance"=>row.bks_distance) for row in instances),
        "methods" => methods,
        "requested_methods" => requested_methods,
        "skipped_methods" => skipped_methods,
        "strategy_variants" => Hybrid.SearchPolicies.CONFIG,
        "strategy_panel" => ResourceExperiment.StrategyPanel.CONFIG,
        "qubo_guides" => Hybrid.QUBOGuidance.input_manifest([row.id for row in instances]),
        "strategy_panel_configurations"=>Dict(m=>ResourceExperiment.StrategyPanel.metadata(m,opts.threads)
            for m in methods if haskey(ResourceExperiment.StrategyPanel.CATALOG,m)),
        "hexaly" => hexaly_identity,
        "ortools" => ortools_identity === nothing ? Dict{String,Any}() : ortools_identity,
        "ghost" => ghost_identity === nothing ? Dict{String,Any}() : ghost_identity,
        "seeds" => opts.seeds,
        "budget_seconds" => opts.budget,
        "threads" => opts.threads,
        "bks_distance_digits" => CAMPAIGN_CONFIG["bks_distance_digits"],
        "gc_threads" => Threads.ngcthreads(),
        "affinity" => Sys.islinux() ? allowed_cpus() : Int[],
        "affinity_mode" => PlatformResources.affinity_mode(),
        "host_platform" => string(Sys.MACHINE),
        "policy" => THREAD_CONFIG["policy"],
        "objective" => CAMPAIGN_CONFIG["objective"],
        "trajectory_policy" => CAMPAIGN_CONFIG["trajectory_policy"])
end

function trial_path(output, id, method, seed)
    joinpath(output, "trials", id * "__" * method * "__seed-" * string(seed) * ".toml")
end

function checked_objective(p, routes, vehicles, distance)
    check = validate_solution(p, routes)
    check.valid || error("stored route fails original Li-Lim validation")
    check.objective.vehicles == vehicles || error("stored vehicle count differs from original validation")
    isapprox(check.objective.distance, distance; atol=1e-8, rtol=1e-12) || error("stored distance differs from original validation")
    check.objective
end

function verify_trial(path, row, method, seed, budget, threads, problem, fingerprint)
    seal = path * ".sha256"
    isfile(seal) || error("unsealed result: $path")
    strip(read(seal, String)) == digest(path) || error("result checksum mismatch: $path")
    record = TOML.parsefile(path)
    (record["instance"], record["method"], record["seed"], record["budget_seconds"], record["threads_requested"]) ==
        (row.id, method, seed, budget, threads) || error("trial identity changed: $path")
    record["run_fingerprint"] == fingerprint || error("trial fingerprint differs from the campaign manifest")
    record["original_validation"] || error("trial lacks original-problem validation: $path")
    checked_objective(problem, record["routes"], record["vehicles"], record["distance"])
    for event in record["trajectory"]
        0 <= event["seconds"] <= budget || error("stored trajectory exceeds budget")
        checked_objective(problem, event["routes"], event["vehicles"], event["distance"])
    end
    record
end

function bks_hit(record)
    BenchmarkTargets.reaches_published_bks(record["vehicles"], record["distance"],
        record["bks_vehicles"], record["bks_distance"];
        distance_digits=CAMPAIGN_CONFIG["bks_distance_digits"])
end

function time_to_bks(record)
    for event in record["trajectory"]
        BenchmarkTargets.reaches_published_bks(event["vehicles"], event["distance"],
            record["bks_vehicles"], record["bks_distance"];
            distance_digits=CAMPAIGN_CONFIG["bks_distance_digits"]) &&
            return event["seconds"]
    end
    nothing
end

child_cpu_seconds(pid)=PlatformResources.child_cpu_seconds(pid)

"Run the official Python RoutingModel baseline under a one-core affinity mask."
function run_ortools_case(row, seconds, seed, policy, threads, ortools_identity, logpath)
    isfinite(seconds) && seconds > 0 || throw(ArgumentError("positive finite budget required"))
    GC.gc()
    controller_cpu_start = ResourceExperiment.cpu_seconds()
    origin_ns = time_ns()
    origin_epoch_ns = floor(Int, time() * 1e9)
    elapsed() = (time_ns() - origin_ns) / 1e9
    p = read_benchmark(row.path, :li_lim; id=row.id)
    initial = Pilot.insertion(p; starts=policy["insertion_starts"], seed=policy["insertion_seed"])
    initial === nothing && error("no valid common start for OR-Tools")
    initial_check = validate_solution(p, initial)
    initial_check.valid || error("common insertion start failed original validation")
    insertion_seconds = elapsed()
    insertion_seconds < seconds || error("common-start preparation exceeded OR-Tools wall budget")

    mktempdir() do exchange
        input_path = joinpath(exchange, "instance.txt")
        output_path = joinpath(exchange, "native.toml")
        open(input_path, "w") do io
            CompetitorAdapters.export_common_start(io, p, initial)
        end
        common_start_seconds = elapsed()
        common_start_seconds < seconds || error("OR-Tools exchange export exceeded wall budget")
        cpus = CPU_ORDER[1:1]
        command = CompetitorAdapters.ortools_command(ortools_identity["python"],
            joinpath(ROOT, "LiLim", "native", "ortools", "pdptw.py"), input_path, output_path;
            seconds, seed, trial_start_epoch_ns=origin_epoch_ns, cpus)
        python_path = get(ortools_identity,"python_path","")
        isempty(python_path) || (command=addenv(command,"PYTHONPATH"=>python_path,"PYTHONNOUSERSITE"=>"1"))
        mkpath(dirname(logpath))
        process_started_ns = time_ns()
        process_cpu = 0.0
        children_cpu_start=PlatformResources.children_cpu_seconds()
        open(logpath, "w") do log
            process = run(pipeline(command, stdout=log, stderr=log); wait=false)
            pid = getpid(process)
            while process_running(process)
                cpu = child_cpu_seconds(pid)
                cpu === nothing || (process_cpu = cpu)
                sleep(0.1)
            end
            cpu = child_cpu_seconds(pid)
            cpu === nothing || (process_cpu = cpu)
            wait(process)
            Sys.isapple() && (process_cpu=PlatformResources.children_cpu_seconds()-children_cpu_start)
            process.exitcode == 0 || error("OR-Tools exited with code $(process.exitcode); see $logpath")
        end
        process_wall_seconds = (time_ns() - process_started_ns) / 1e9
        measured_wall = elapsed()
        controller_cpu = ResourceExperiment.cpu_seconds() - controller_cpu_start
        total_cpu = controller_cpu + process_cpu
        isfile(output_path) || error("OR-Tools did not write its result; see $logpath")
        native = TOML.parsefile(output_path)
        native["ortools_version"] == ortools_identity["ortools_version"] ||
            error("OR-Tools runner version differs from the qualified Python environment")
        abs(native["seconds"] - measured_wall) <= max(2.0, 0.01 * seconds) ||
            error("OR-Tools wall clock differs from Julia monotonic clock")
        audit_started = time_ns()
        audited = CompetitorAdapters.audit_ortools_trial(p, initial, native;
            budget_seconds=seconds, common_start_seconds=common_start_seconds)
        audit_seconds = (time_ns() - audit_started) / 1e9
        audited["within_budget_feasible"] || error("OR-Tools produced no within-budget feasible solution")
        quality = validate_solution(p, audited["routes"]).objective
        Dict{String,Any}(
            "schema"=>"li-lim-resource-trial/1", "instance"=>row.id, "method"=>"ortools_native",
            "threads_requested"=>threads, "julia_threads_available"=>Threads.nthreads(),
            "threads_mode"=>"single-thread OR-Tools RoutingModel process pinned to one P-core",
            "seed"=>seed, "seed_applied_to_search"=>false, "budget_seconds"=>seconds,
            "wall_seconds"=>measured_wall, "outer_elapsed_seconds"=>measured_wall,
            "process_wall_seconds"=>process_wall_seconds, "process_cpu_seconds"=>total_cpu,
            "ortools_child_cpu_seconds"=>process_cpu, "controller_cpu_seconds"=>controller_cpu,
            "mean_active_cpus"=>total_cpu / max(measured_wall, eps()),
            "initial_seconds"=>common_start_seconds, "insertion_seconds"=>insertion_seconds,
            "initial_vehicles"=>initial_check.objective.vehicles,
            "initial_distance"=>initial_check.objective.distance,
            "vehicles"=>quality.vehicles, "distance"=>quality.distance,
            "routes"=>audited["routes"], "trajectory"=>audited["trajectory"],
            "original_validation"=>audited["original_validation"],
            "audited_incumbents"=>audited["audited_incumbents"],
            "late_incumbents_censored"=>audited["late_incumbents_censored"],
            "ortools_status"=>native["solver_status"],
            "ortools_search_seconds"=>native["solver_seconds"],
            "ortools_version"=>native["ortools_version"],
            "ortools_python_version"=>native["python_version"],
            "ortools_common_start_accepted"=>audited["common_start_accepted"],
            "ortools_internal_search_threads"=>native["internal_search_threads"],
            "ortools_guided_local_search"=>native["guided_local_search"],
            "ortools_binary_sha256"=>ortools_identity["native_module_sha256"],
            "ortools_runner_sha256"=>ortools_identity["runner_sha256"],
            "ortools_affinity"=>cpus,"ortools_audit_seconds"=>audit_seconds,
            "source_sha256"=>digest(row.path),"common_input_sha256"=>digest(input_path))
    end
end

"""Run one standalone Hexaly trial under the shared common-start wall clock."""
function run_hexaly_case(row, seconds, seed, policy, threads, executable, logpath)
    isfinite(seconds) && seconds > 0 || throw(ArgumentError("positive finite budget required"))
    isinteger(seconds) || throw(ArgumentError("Hexaly time limits are whole seconds"))
    threads in (1, 2, 4, 8, 16) || throw(ArgumentError("unsupported Hexaly thread width"))
    GC.gc()
    controller_cpu_start = ResourceExperiment.cpu_seconds()
    origin_ns = time_ns()
    origin_epoch_ms = floor(Int, time() * 1000)
    elapsed() = (time_ns() - origin_ns) / 1e9
    p = read_benchmark(row.path, :li_lim; id=row.id)
    initial = Pilot.insertion(p; starts=policy["insertion_starts"], seed=policy["insertion_seed"])
    initial === nothing && error("no valid common start for Hexaly")
    initial_check = validate_solution(p, initial)
    initial_check.valid || error("common insertion start failed original validation")
    insertion_seconds = elapsed()
    insertion_seconds < seconds || error("common-start preparation exceeded Hexaly wall budget")

    mktempdir() do exchange
        input_path = joinpath(exchange, "instance.txt")
        output_path = joinpath(exchange, "native.toml")
        trajectory_path = joinpath(exchange, "trajectory.toml")
        open(input_path, "w") do io
            CompetitorAdapters.export_common_start(io, p, initial)
        end
        common_start_seconds = elapsed()
        common_start_seconds < seconds || error("Hexaly exchange export exceeded wall budget")
        cpus = CPU_ORDER[1:threads]
        command = CompetitorAdapters.hexaly_command(executable, input_path, output_path;
            threads, seconds=Int(seconds), seed, cpus, trial_start_epoch_ms=origin_epoch_ms,
            trajectory=trajectory_path)
        mkpath(dirname(logpath))
        process_started_ns = time_ns()
        process_cpu = 0.0
        children_cpu_start=PlatformResources.children_cpu_seconds()
        open(logpath, "w") do log
            process = run(pipeline(command, stdout=log, stderr=log); wait=false)
            pid = getpid(process)
            while process_running(process)
                cpu = child_cpu_seconds(pid)
                cpu === nothing || (process_cpu = cpu)
                sleep(0.1)
            end
            cpu = child_cpu_seconds(pid)
            cpu === nothing || (process_cpu = cpu)
            wait(process)
            Sys.isapple() && (process_cpu=PlatformResources.children_cpu_seconds()-children_cpu_start)
            process.exitcode == 0 || error("Hexaly exited with code $(process.exitcode); see $logpath")
        end
        process_wall_seconds = (time_ns() - process_started_ns) / 1e9
        controller_cpu = ResourceExperiment.cpu_seconds() - controller_cpu_start
        total_cpu = controller_cpu + process_cpu
        isfile(output_path) || error("Hexaly did not write its final result; see $logpath")
        isfile(trajectory_path) || error("Hexaly did not write its trajectory; see $logpath")
        native = TOML.parsefile(output_path)
        trace = TOML.parsefile(trajectory_path)
        native_seconds = Float64(get(native, "seconds", Inf))
        measured_wall = elapsed()
        clock_skew = native_seconds - measured_wall
        abs(clock_skew) <= max(2.0, 0.01 * seconds) ||
            error("Hexaly wall clock differs from Julia monotonic clock by $(clock_skew) seconds")
        audit_started = time_ns()
        audited = CompetitorAdapters.audit_hexaly_trial(p, initial, native, trace;
            budget_seconds=seconds, common_start_seconds=common_start_seconds)
        audit_seconds = (time_ns() - audit_started) / 1e9
        audited["within_budget_feasible"] || error("Hexaly produced no within-budget feasible solution")
        quality = validate_solution(p, audited["routes"]).objective
        Dict{String,Any}(
            "schema"=>"li-lim-resource-trial/1", "instance"=>row.id, "method"=>"hexaly_native",
            "threads_requested"=>threads, "julia_threads_available"=>Threads.nthreads(),
            "threads_mode"=>"native Hexaly process under explicit CPU affinity",
            "seed"=>seed, "budget_seconds"=>seconds,
            "wall_seconds"=>measured_wall, "outer_elapsed_seconds"=>measured_wall,
            "process_wall_seconds"=>process_wall_seconds, "process_cpu_seconds"=>total_cpu,
            "hexaly_child_cpu_seconds"=>process_cpu, "controller_cpu_seconds"=>controller_cpu,
            "mean_active_cpus"=>total_cpu / max(measured_wall, eps()),
            "initial_seconds"=>common_start_seconds, "insertion_seconds"=>insertion_seconds,
            "initial_vehicles"=>initial_check.objective.vehicles,
            "initial_distance"=>initial_check.objective.distance,
            "vehicles"=>quality.vehicles, "distance"=>quality.distance,
            "routes"=>audited["routes"], "trajectory"=>audited["trajectory"],
            "hexaly_phase_budget"=>audited["phase_budget"],
            "original_validation"=>audited["original_validation"],
            "audited_incumbents"=>audited["audited_incumbents"],
            "late_incumbents_censored"=>audited["late_incumbents_censored"],
            "hexaly_status"=>native["status"], "hexaly_solver_seconds"=>native["solver_seconds"],
            "hexaly_common_clock_seconds"=>native_seconds, "hexaly_clock_skew_seconds"=>clock_skew,
            "hexaly_binary_sha256"=>digest(executable), "hexaly_version_target"=>HEXALY_CONFIG["target_version"],
            "hexaly_affinity"=>cpus, "hexaly_audit_seconds"=>audit_seconds,
            "source_sha256"=>digest(row.path), "common_input_sha256"=>digest(input_path),
            "hexaly_nominal_phase_split_seconds"=>Dict("fleet"=>max(1, fld(5 * Int(seconds), 6)),
                "distance"=>Int(seconds)-max(1, fld(5 * Int(seconds), 6))))
    end
end

function warmup(methods, row, policy, banks, plans, seconds, output, hexaly_executable, ortools_identity)
    results = Any[]
    for method in methods
        method in ResourceExperiment.METHODS || continue
        started = time_ns()
        record = ResourceExperiment.run_case(row.path, method, seconds, first(THREAD_CONFIG["seeds"]),
            policy, banks; threads=Threads.nthreads(), id=row.id, portfolio=get(plans, method, nothing))
        push!(results, Dict("instance"=>row.id,"method"=>method,"seconds"=>(time_ns()-started)/1e9,
            "valid"=>record["original_validation"],"budget_seconds"=>seconds))
    end
    if "ortools_native" in methods
        ortools_identity === nothing && error("OR-Tools warmup has no resolved Python environment")
        logpath = joinpath(output, "logs", "warmup__lc101__ortools_native.log")
        record = run_ortools_case(row, seconds, first(THREAD_CONFIG["seeds"]), policy,
            Threads.nthreads(), ortools_identity, logpath)
        push!(results, Dict("instance"=>row.id,"method"=>"ortools_native",
            "seconds"=>record["wall_seconds"],"valid"=>record["original_validation"],
            "budget_seconds"=>seconds,"mean_active_cpus"=>record["mean_active_cpus"]))
    end
    if "hexaly_native" in methods
        hexaly_executable === nothing && error("Hexaly warmup has no resolved executable")
        logpath = joinpath(output, "logs", "warmup__lc101__hexaly_native.log")
        record = run_hexaly_case(row, seconds, first(THREAD_CONFIG["seeds"]), policy,
            Threads.nthreads(), hexaly_executable, logpath)
        push!(results, Dict("instance"=>row.id,"method"=>"hexaly_native",
            "seconds"=>record["wall_seconds"],"valid"=>record["original_validation"],
            "budget_seconds"=>seconds,"mean_active_cpus"=>record["mean_active_cpus"]))
    end
    if "ghost_icn" in methods
        started = time_ns()
        Base.invokelatest(GHOSTNative.warmup,row.path,policy;threads=Threads.nthreads(),id=row.id)
        record = Base.invokelatest(GHOSTNative.run_case,row.path,seconds,first(THREAD_CONFIG["seeds"]),policy;
            threads=Threads.nthreads(),id=row.id)
        push!(results,Dict("instance"=>row.id,"method"=>"ghost_icn",
            "seconds"=>(time_ns()-started)/1e9,"trial_wall_seconds"=>record["wall_seconds"],
            "valid"=>record["original_validation"],"budget_seconds"=>seconds))
    end
    results
end

function campaign_main()
    opts = cli(ARGS)
    opts.threads > 0 || error("thread count must be positive")
    check_environment(opts.threads)
    all_rows = corpus()
    instances = select_instances(all_rows, opts.instances)
    requested_methods = select_methods(opts.threads, opts.methods)
    availability = NativeSolvers.resolve_requested(requested_methods; missing=opts.missing_solvers,
        ortools_resolver=()->NativeSolvers.resolve_ortools(opts.ortools; root=ROOT),
        hexaly_resolver=()->resolve_hexaly(opts),
        ghost_resolver=()->NativeSolvers.resolve_ghost(;root=ROOT))
    methods = availability.methods
    hexaly_executable = availability.hexaly
    ortools_identity = availability.ortools
    availability.ghost === nothing || Base.include(Main,joinpath(ROOT,"LiLim/src/GHOSTNative.jl"))
    allunique(opts.seeds) && all(>(0), opts.seeds) || error("seeds must be distinct positive integers")
    identity = campaign_identity(opts, instances, methods, hexaly_executable, ortools_identity;
        requested_methods, skipped_methods=availability.skipped,ghost_identity=availability.ghost)
    fingerprint = stable_sha(identity)
    output = opts.output
    manifest_path = joinpath(output, "manifest.toml")
    if opts.resume
        isfile(manifest_path) || error("no campaign manifest at $manifest_path")
        manifest = TOML.parsefile(manifest_path)
        manifest["run_fingerprint"] == fingerprint || error("resume inputs differ from the frozen campaign")
        get(manifest, "complete", false) && error("campaign is already complete")
    else
        ispath(output) && error("campaign output already exists; pass --resume only for an interrupted matching campaign")
        mkpath(output)
        manifest = Dict{String,Any}("identity"=>identity,"run_fingerprint"=>fingerprint,
            "started_utc"=>string(now(UTC)),"complete"=>false)
        atomic(manifest_path, io->TOML.print(io, manifest; sorted=true))
    end
    println(opts.resume ? "Resuming " : "Starting ", output, " (", length(instances), " instances × ",
        length(methods), " methods × ", length(opts.seeds), " seeds)")
    flush(stdout)

    for row in availability.skipped
        println("Skipped ",row["method"],": ",row["reason"])
    end
    if isempty(methods)
        manifest = TOML.parsefile(manifest_path)
        manifest["completed_trials"] = 0
        manifest["finished_utc"] = string(now(UTC))
        manifest["complete"] = true
        atomic(manifest_path,io->TOML.print(io,manifest;sorted=true))
        println("All requested methods were unavailable; no solve was launched.")
        return
    end

    banks = Dict(kind=>ICNScoring.load_backend(kind) for kind in (:naive,:icn,:direct))
    plans = Dict(method=>ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(method, opts.threads))
        for method in methods if method != "highs_native" && method in ResourceExperiment.METHODS)
    warmup_row = only(filter(row->row.id=="lc101", all_rows))
    warmed = Base.invokelatest(warmup,methods, warmup_row, THREAD_CONFIG["policy"], banks, plans,
        CAMPAIGN_CONFIG["warmup_seconds"], output, hexaly_executable, ortools_identity)
    manifest = TOML.parsefile(manifest_path)
    segments = get!(manifest, "warmup_segments", Any[])
    push!(segments, Dict("started_utc"=>string(now(UTC)), "threads"=>opts.threads, "runs"=>warmed))
    atomic(manifest_path, io->TOML.print(io, manifest; sorted=true))

    problems = Dict{String,Any}()
    total = length(instances) * length(methods) * length(opts.seeds)
    completed = 0
    for (instance_index, row) in enumerate(instances), (repeat_index, seed) in enumerate(opts.seeds),
        method in circshift(methods, repeat_index + instance_index - 2)
        Hybrid.QUBOGuidance.input_manifest([r.id for r in instances])==identity["qubo_guides"] ||
            error("QUBO guide inputs changed; preserve sealed trials and use a new cohort")
        path = trial_path(output, row.id, method, seed)
        problem = get!(problems, row.id) do
            read_benchmark(row.path, :li_lim; id=row.id)
        end
        if isfile(path)
            verify_trial(path, row, method, seed, opts.budget, opts.threads, problem, fingerprint)
            completed += 1
            continue
        end
        if isfile(joinpath(output,"STOP_AFTER_TRIAL"))
            manifest = TOML.parsefile(manifest_path)
            manifest["completed_trials"] = completed
            manifest["complete"] = false
            atomic(manifest_path,io->TOML.print(io,manifest;sorted=true))
            println("Stopped between trials; preserve seals and resume the same campaign after removing STOP_AFTER_TRIAL.")
            return
        end
        isfile(path * ".sha256") && error("orphan trial checksum: $path")
        started = time_ns()
        record = if method == "hexaly_native"
            logpath = joinpath(output, "logs", row.id * "__" * method * "__seed-" * string(seed) * ".log")
            run_hexaly_case(row, opts.budget, seed, THREAD_CONFIG["policy"], opts.threads,
                hexaly_executable, logpath)
        elseif method == "ortools_native"
            logpath = joinpath(output, "logs", row.id * "__" * method * "__seed-" * string(seed) * ".log")
            run_ortools_case(row, opts.budget, seed, THREAD_CONFIG["policy"], opts.threads,
                ortools_identity, logpath)
        elseif method == "ghost_icn"
            Base.invokelatest(() -> GHOSTNative.run_case(row.path,opts.budget,seed,THREAD_CONFIG["policy"];
                threads=opts.threads,id=row.id))
        else
            native_log = method == "highs_native" ? joinpath(output, "logs", row.id * "__" * method * "__seed-" * string(seed) * ".log") : nothing
            native_log === nothing || mkpath(dirname(native_log))
            ResourceExperiment.run_case(row.path, method, opts.budget, seed,
                THREAD_CONFIG["policy"], banks; threads=opts.threads, id=row.id,
                logpath=native_log, portfolio=get(plans, method, nothing))
        end
        record["original_validation"] || error("trial rejected by original validator")
        record["bks_vehicles"] = row.bks_vehicles
        record["bks_distance"] = row.bks_distance
        record["bks_reached"] = bks_hit(record)
        target_time = time_to_bks(record)
        record["time_to_bks_seconds"] = target_time === nothing ? "not_reached" : target_time
        record["outer_elapsed_seconds"] = (time_ns()-started)/1e9
        record["official_archive_sha256"] = BKS["archive_sha256"][basename(archive_path(string(row.size)))]
        record["run_fingerprint"] = fingerprint
        atomic(path, io->TOML.print(io, record; sorted=true))
        atomic(path * ".sha256", io->print(io, digest(path)))
        verify_trial(path, row, method, seed, opts.budget, opts.threads, problem, fingerprint)
        completed += 1
        println("[", completed, "/", total, "] ", row.id, " ", method, " seed ", seed,
            " -> ", record["vehicles"], " / ", round(record["distance"];digits=3),
            "; BKS ", record["bks_reached"], "; CPU ", round(record["mean_active_cpus"];digits=2))
        flush(stdout)
    end

    manifest = TOML.parsefile(manifest_path)
    manifest["completed_trials"] = completed
    manifest["finished_utc"] = string(now(UTC))
    manifest["complete"] = completed == total
    manifest["complete"] || error("campaign is missing trial records")
    atomic(manifest_path, io->TOML.print(io, manifest; sorted=true))
    println("Completed ", total, " qualified trials. Campaign fingerprint: ", fingerprint)
end

abspath(PROGRAM_FILE)==abspath(@__FILE__) && campaign_main()
