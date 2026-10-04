using ConstraintModels, JuMP, TOML, SHA, Dates, LinearAlgebra
using ConstraintModels.Benchmarks

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RUNNER_PATH = abspath(@__FILE__)
for source in ("Pilot", "MetaRepair", "ICNScoring", "Hybrid", "ResourceExperiment")
    include(joinpath(ROOT, "LiLim", "src", source * ".jl"))
end

const THREAD_CONFIG = TOML.parsefile(joinpath(ROOT, "LiLim", "config", "icn-threads.toml"))
const CAMPAIGN_CONFIG_PATH = joinpath(ROOT, "LiLim", "config", "full-corpus-campaign.toml")
const CAMPAIGN_CONFIG = TOML.parsefile(CAMPAIGN_CONFIG_PATH)
const BASELINE_PATH = joinpath(ROOT, "LiLim", "config", "current-pilot.toml")
const BASELINE = TOML.parsefile(BASELINE_PATH)
const COHORT_PATH = joinpath(ROOT, "LiLim", "config", "workspace-cohort.toml")
const COHORT = TOML.parsefile(COHORT_PATH)["cohort"]
const BKS_PATH = joinpath(ROOT, "LiLim", "config", "sintef-pdptw-bks-20261004.toml")
const BKS = TOML.parsefile(BKS_PATH)
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
        name in ("budget", "output", "threads", "instances", "methods", "seeds") || error("unknown option --$name")
        haskey(values, name) && error("duplicate option --$name")
        values[name] = value
    end
    all(key -> haskey(values, key), ("budget", "output", "threads")) ||
        error("usage: full_corpus_campaign.jl --budget=SECONDS --output=DIR --threads=N [--instances=all|ID,...] [--methods=all|NAME,...] [--seeds=41,42,43] [--resume]")
    budget = parse(Float64, values["budget"])
    isfinite(budget) && budget > 0 || error("budget must be positive and finite")
    (; budget, output=abspath(values["output"]), threads=parse(Int, values["threads"]),
       instances=get(values, "instances", "all"), methods=get(values, "methods", "all"),
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

function available_methods(threads)
    methods = unique(vcat(THREAD_CONFIG["methods"], CAMPAIGN_CONFIG["extra_methods"], ["cbls_mix_strategy"],
        threads >= 4 ? THREAD_CONFIG["portfolio_methods"] : String[]))
    methods
end

function select_methods(threads, selector)
    allowed = available_methods(threads)
    selector == "all" && return allowed
    wanted = strip.(split(selector, ','))
    isempty(wanted) && error("empty method selection")
    unknown = setdiff(Set(wanted), Set(allowed))
    isempty(unknown) || error("methods unavailable at $(threads) threads: " * join(sort!(collect(unknown)), ", "))
    unique(wanted)
end

function allowed_cpus()
    row = only(filter(line -> startswith(line, "Cpus_allowed_list:"), readlines("/proc/self/status")))
    text = strip(split(row, ':')[2])
    cpus = Int[]
    for part in split(text, ',')
        bounds = parse.(Int, split(part, '-'))
        append!(cpus, length(bounds) == 1 ? bounds : first(bounds):last(bounds))
    end
    sort(cpus)
end

function check_environment(threads)
    string(VERSION) == THREAD_CONFIG["julia"] || error("Julia version differs from the qualified campaign")
    Threads.nthreads() == threads || error("launched Julia thread count differs from --threads")
    threads in CAMPAIGN_CONFIG["thread_counts"] || error("thread width is not in the frozen protocol")
    BLAS.get_num_threads() == 1 || error("BLAS must be single-threaded")
    sort(allowed_cpus()) == sort(CAMPAIGN_CONFIG["cpu_order"][1:threads]) || error("CPU affinity differs from the frozen topology order")
    env = dirname(Base.active_project())
    for (file, key) in (("Project.toml", "project_sha256"), ("Manifest.toml", "manifest_sha256"))
        digest(joinpath(env, file)) == BASELINE["environment"][key] || error("solver environment changed: $file")
    end
    for (name, expected) in COHORT
        repo = joinpath(homedir(), ".julia", "dev", name)
        strip(read(`git -C $repo rev-parse HEAD`, String)) == expected || error("development cohort changed: $name")
        isempty(strip(read(`git -C $repo status --porcelain --untracked-files=no`, String))) || error("dirty dependency: $name")
    end
    bank = joinpath(homedir(), ".julia", "dev", "ConstraintLearningBenchmarks",
        "scripts", "xcsp3_core", "learnable_catalog", "weights.toml")
    digest(bank) == THREAD_CONFIG["icn_bank_sha256"] || error("learned ICN bank changed")
    measured = vcat(filter(path -> endswith(path, ".jl"), readdir(joinpath(ROOT, "LiLim", "src"); join=true)),
        [CAMPAIGN_CONFIG_PATH, BKS_PATH, BASELINE_PATH, COHORT_PATH,
         joinpath(ROOT, "LiLim", "config", "icn-threads.toml"),
         joinpath(ROOT, "LiLim", "test", "icn_resources.jl"),
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
        [RUNNER_PATH, CAMPAIGN_CONFIG_PATH, BKS_PATH, BASELINE_PATH, COHORT_PATH,
         joinpath(ROOT, "LiLim", "config", "icn-threads.toml"),
         joinpath(ROOT, "LiLim", "test", "icn_resources.jl"),
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_report.jl"),
         joinpath(ROOT, "LiLim", "scripts", "full_corpus_plots.jl")])
    Dict(relpath(abspath(path), ROOT) => digest(path) for path in files)
end

function campaign_identity(opts, instances, methods)
    Dict{String,Any}(
        "schema" => CAMPAIGN_CONFIG["schema"],
        "julia" => string(VERSION),
        "benchmarks_commit" => strip(read(`git -C $ROOT rev-parse HEAD`, String)),
        "runner_sha256" => digest(RUNNER_PATH),
        "source_sha256" => source_manifest(),
        "cohort" => COHORT,
        "environment" => BASELINE["environment"],
        "official_archive_sha256" => BKS["archive_sha256"],
        "instance_sha256" => Dict(row.id => row.source_sha256 for row in instances),
        "instances" => [row.id for row in instances],
        "targets" => Dict(row.id => Dict("vehicles"=>row.bks_vehicles,"distance"=>row.bks_distance) for row in instances),
        "methods" => methods,
        "seeds" => opts.seeds,
        "budget_seconds" => opts.budget,
        "threads" => opts.threads,
        "gc_threads" => Threads.ngcthreads(),
        "affinity" => allowed_cpus(),
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
    record["vehicles"] < record["bks_vehicles"] ||
        (record["vehicles"] == record["bks_vehicles"] && record["distance"] <= record["bks_distance"] + 1e-6)
end

function time_to_bks(record)
    for event in record["trajectory"]
        (event["vehicles"] < record["bks_vehicles"] ||
            (event["vehicles"] == record["bks_vehicles"] && event["distance"] <= record["bks_distance"] + 1e-6)) &&
            return event["seconds"]
    end
    nothing
end

function warmup(methods, row, policy, banks, plans, seconds)
    results = Any[]
    for method in methods
        started = time_ns()
        record = ResourceExperiment.run_case(row.path, method, seconds, first(THREAD_CONFIG["seeds"]),
            policy, banks; threads=Threads.nthreads(), id=row.id, portfolio=get(plans, method, nothing))
        push!(results, Dict("instance"=>row.id,"method"=>method,"seconds"=>(time_ns()-started)/1e9,
            "valid"=>record["original_validation"],"budget_seconds"=>seconds))
    end
    results
end

function run()
    opts = cli(ARGS)
    opts.threads > 0 || error("thread count must be positive")
    check_environment(opts.threads)
    all_rows = corpus()
    instances = select_instances(all_rows, opts.instances)
    methods = select_methods(opts.threads, opts.methods)
    allunique(opts.seeds) && all(>(0), opts.seeds) || error("seeds must be distinct positive integers")
    identity = campaign_identity(opts, instances, methods)
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

    banks = Dict(kind=>ICNScoring.load_backend(kind) for kind in (:naive,:icn,:direct))
    plans = Dict(method=>ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(method, opts.threads))
        for method in methods if method != "highs_native")
    warmup_row = only(filter(row->row.id=="lc101", all_rows))
    warmed = warmup(methods, warmup_row, THREAD_CONFIG["policy"], banks, plans, CAMPAIGN_CONFIG["warmup_seconds"])
    manifest = TOML.parsefile(manifest_path)
    segments = get!(manifest, "warmup_segments", Any[])
    push!(segments, Dict("started_utc"=>string(now(UTC)), "threads"=>opts.threads, "runs"=>warmed))
    atomic(manifest_path, io->TOML.print(io, manifest; sorted=true))

    problems = Dict{String,Any}()
    total = length(instances) * length(methods) * length(opts.seeds)
    completed = 0
    for (instance_index, row) in enumerate(instances), (repeat_index, seed) in enumerate(opts.seeds),
        method in circshift(methods, repeat_index + instance_index - 2)
        path = trial_path(output, row.id, method, seed)
        problem = get!(problems, row.id) do
            read_benchmark(row.path, :li_lim; id=row.id)
        end
        if isfile(path)
            verify_trial(path, row, method, seed, opts.budget, opts.threads, problem, fingerprint)
            completed += 1
            continue
        end
        isfile(path * ".sha256") && error("orphan trial checksum: $path")
        native_log = method == "highs_native" ? joinpath(output, "logs", row.id * "__" * method * "__seed-" * string(seed) * ".log") : nothing
        native_log === nothing || mkpath(dirname(native_log))
        started = time_ns()
        record = ResourceExperiment.run_case(row.path, method, opts.budget, seed,
            THREAD_CONFIG["policy"], banks; threads=opts.threads, id=row.id,
            logpath=native_log, portfolio=get(plans, method, nothing))
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

run()
