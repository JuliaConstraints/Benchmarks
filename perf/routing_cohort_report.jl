# Reduce sealed, order-reversed timing observations without discarding outliers.
using TOML, SHA, Statistics, Dates

function main()
length(ARGS) == 5 || error("Usage: routing_cohort_report.jl INPUT_DIRECTORY PREFIX BEFORE_ENVIRONMENT AFTER_ENVIRONMENT OUTPUT.toml")
input, prefix, before_environment, after_environment, output = abspath(ARGS[1]), ARGS[2], abspath(ARGS[3]), abspath(ARGS[4]), abspath(ARGS[5])
ispath(output) && error("Existing evidence is preserved; choose a new output")
isdir(dirname(output)) || error("Output parent must exist")
method_ids = ["rp_vnd_greedy", "rp_alns_route_regret2", "rp_aco_regret2", "rp_alns_random_regret2",
    "rp_meta_adaptive_late", "rp_meta_diversity_tabu", "rp_meta_pool_ipx_late", "rp_meta_pool_mip_tabu"]
widths, seeds, samples = [1,2,4,8], [41,42,43], 1:5
owned = Set(("CBLS", "LocalSearchSolvers", "MetaStrategist", "ConstraintModels", "CompositionalNetworks",
    "Constraints", "ConstraintCommons", "ConstraintDomains", "PatternFolds", "QUBOConstraints",
    "ConstraintProgrammingExtensions", "XCSP3Bridges", "GHOST"))
expected = Set((method, seed, sample) for method in method_ids for seed in seeds for sample in samples)
observations = Dict{Tuple{Int,String,Int},Dict{String,Any}}()
receipts = Dict{String,Any}[]
for round in 1:2, side in ("before","after"), width in widths
    file = joinpath(input, "$prefix-r$round-$side-w$width.toml")
    data = TOML.parsefile(file)
    data["complete"] === true || error("Incomplete observation: $file")
    data["protocol"] == "fixed-work Linux pipeline timing/3" || error("Different protocol: $file")
    data["workers"] == width || error("Different worker width: $file")
    data["gc_threads"] == data["blas_threads"] == 1 || error("Thread resource mismatch: $file")
    data["measured_application_sources_clean"] === true || error("Dirty application: $file")
    all(p -> p["source_clean"] === true, data["package_sources"]) || error("Dirty package: $file")
    rows = data["records"]
    length(rows) == length(expected) || error("Missing or duplicated measurement: $file")
    row_keys = [(r["method"],r["seed"],r["sample"]) for r in rows]
    Set(row_keys) == expected && allunique(row_keys) || error("Unexpected measurement keys: $file")
    all(r -> r["original_oracle"] == "passed", rows) || error("Original validation failed: $file")
    all(r -> length(r["worker_work"]) == width && length(r["thread_cpu_seconds"]) == width, rows) ||
        error("Incomplete lane evidence: $file")
    pins = data["thread_pins"]
    Set(p["cpu"] for p in pins) == Set(data["cpu_affinity"]) && length(pins) == width ||
        error("Invalid CPU pinning: $file")
    data["coordinator_cpu"] == first(data["cpu_affinity"]) || error("Unexpected coordinator CPU: $file")
    observations[(round,side,width)] = data
    push!(receipts, Dict("file"=>basename(file), "sha256"=>bytes2hex(sha256(read(file))),
        "round"=>round, "side"=>side, "workers"=>width, "records"=>length(rows),
        "application_commit"=>data["application_commit"], "source_sha256"=>data["source_sha256"],
        "project_sha256"=>data["project_sha256"], "manifest_sha256"=>data["manifest_sha256"],
        "initial_setup_wall_seconds"=>data["initial_setup_wall_seconds"],
        "cpu_affinity"=>data["cpu_affinity"], "recorded_utc"=>data["recorded_utc"],
        "completed_utc"=>data["completed_utc"]))
end
reference = observations[(1,"before",1)]
for ((round,side,width),data) in observations
    for field in ("protocol_sha256","instance_sha256","instance_name","timing_scope")
        data[field] == reference[field] || error("Incompatible $field")
    end
    first_side = observations[(1,side,1)]
    for field in ("application_commit","source_sha256","project_sha256","manifest_sha256","package_sources")
        data[field] == first_side[field] || error("Source/environment changed within $side observations: $field")
    end
    data["cpu_affinity"] == observations[(1,"before",width)]["cpu_affinity"] || error("CPU mask changed")
end

# Resolve identity of all non-controlled dependencies from the actual measured graphs.
graphs = Dict(side=>TOML.parsefile(joinpath(environment,"Manifest.toml"))
    for (side,environment) in (("before",before_environment),("after",after_environment)))
for (side, environment) in (("before",before_environment),("after",after_environment))
    data = observations[(1,side,1)]
    bytes2hex(sha256(read(joinpath(environment,"Project.toml")))) == data["project_sha256"] ||
        error("Project differs from the measured graph")
    bytes2hex(sha256(read(joinpath(environment,"Manifest.toml")))) == data["manifest_sha256"] ||
        error("Manifest differs from the measured graph")
end
for field in ("julia_version","manifest_format")
    graphs["before"][field] == graphs["after"][field] || error("Different $field")
end
external(side) = Dict(name=>entry for (name,entry) in graphs[side]["deps"] if name ∉ owned)
external("before") == external("after") || error("Non-controlled dependency graph changed")
native = [Dict("package"=>name, "entries"=>graphs["after"]["deps"][name])
    for name in ("HiGHS","HiGHS_jll","JuMP","MathOptInterface")]

function describe(values)
    v = Float64.(values)
    !isempty(v) && all(isfinite,v) || error("Non-finite or empty measurement")
    Dict("count"=>length(v),"best"=>minimum(v),"mean"=>mean(v),"median"=>median(v),
        "standard_deviation"=>length(v)>1 ? std(v) : 0.0,
        "minimum"=>minimum(v),"maximum"=>maximum(v),"q25"=>quantile(v,.25),"q75"=>quantile(v,.75))
end
lookup(data) = Dict((r["method"],r["seed"],r["sample"])=>r for r in data["records"])
indices = Dict(key=>lookup(data) for (key,data) in observations)
# Work hashes cover original routes, entire substantive traces, all lanes, next
# RNG values and non-timing coordinator results. Independently compare exported
# lane dictionaries and substantive coordination as a second guard.
substantive(r) = Dict(key=>value for (key,value) in r["coordinator"]
    if key ∉ ("master_seconds","master_build_seconds","budget_seconds"))
semantic_checks = 0
for width in widths, method in method_ids, seed in seeds
    first_row = indices[(1,"before",width)][(method,seed,1)]
    for round in 1:2, side in ("before","after"), sample in samples
        row = indices[(round,side,width)][(method,seed,sample)]
        row["work_sha256"] == first_row["work_sha256"] &&
            row["worker_work"] == first_row["worker_work"] &&
            substantive(row) == substantive(first_row) ||
            error("Unequal original work: $method / $width workers / seed $seed / round $round / $side / sample $sample")
        semantic_checks += 1
    end
end
metrics = ("seconds","bytes","objects","gc_seconds","process_cpu_seconds","mean_active_cpus")
groups = Dict{String,Any}[]
for width in widths, method in method_ids, seed in seeds
    group = Dict{String,Any}("method"=>method,"workers"=>width,"seed"=>seed,
        "original_work_sha256"=>indices[(1,"before",width)][(method,seed,1)]["work_sha256"],
        "observations_per_side"=>10, "original_work_matches"=>true)
    paired = Dict{String,Any}()
    for metric in metrics
        old = [indices[(round,"before",width)][(method,seed,sample)][metric] for round in 1:2 for sample in samples]
        new = [indices[(round,"after",width)][(method,seed,sample)][metric] for round in 1:2 for sample in samples]
        stats = Dict{String,Any}("before"=>describe(old),"after"=>describe(new))
        if all(>(0),old)
            stats["paired_remaining_percent"] = describe(100 .* new ./ old)
            stats["median_remaining_percent"] = 100median(new)/median(old)
        end
        paired[metric] = stats
    end
    group["metrics"] = paired
    group["rounds"] = [Dict("round"=>round, "first_side"=>round==1 ? "before" : "after",
        "seconds_before"=>describe([indices[(round,"before",width)][(method,seed,sample)]["seconds"] for sample in samples]),
        "seconds_after"=>describe([indices[(round,"after",width)][(method,seed,sample)]["seconds"] for sample in samples]))
        for round in 1:2]
    group["runtime"] = Dict(side=>Dict(
        "gc_percent"=>describe([100row["gc_seconds"]/row["seconds"] for round in 1:2 for sample in samples
            for row in (indices[(round,side,width)][(method,seed,sample)],)]),
        "master_percent"=>describe([100get(row["coordinator"],"master_seconds",0.)/row["seconds"] for round in 1:2 for sample in samples
            for row in (indices[(round,side,width)][(method,seed,sample)],)]),
        "master_build_seconds"=>describe([get(row["coordinator"],"master_build_seconds",0.) for round in 1:2 for sample in samples
            for row in (indices[(round,side,width)][(method,seed,sample)],)]),
        "mean_lane_cpu_seconds"=>describe([mean(row["thread_cpu_seconds"]) for round in 1:2 for sample in samples
            for row in (indices[(round,side,width)][(method,seed,sample)],)]))
        for side in ("before","after"))
    push!(groups,group)
end
summary = Dict{String,Any}[]
for width in widths, method in method_ids
    selected = filter(g->g["workers"]==width && g["method"]==method,groups)
    record = Dict{String,Any}("workers"=>width,"method"=>method,"seeds"=>seeds,"observations_per_side"=>30)
    record["remaining_percent"] = Dict(metric=>describe([g["metrics"][metric]["median_remaining_percent"] for g in selected])
        for metric in ("seconds","bytes","objects","process_cpu_seconds"))
    record["absolute"] = Dict(side=>Dict(metric=>describe([indices[(round,side,width)][(method,seed,sample)][metric]
        for round in 1:2 for seed in seeds for sample in samples]) for metric in metrics) for side in ("before","after"))
    push!(summary,record)
end
all_rows = [r for data in values(observations) for r in data["records"]]
compiled = [Dict("workers"=>width,"round"=>round,"side"=>side,"method"=>r["method"],
    "seed"=>r["seed"],"sample"=>r["sample"],"compile_seconds"=>r["compile_seconds"],
    "recompile_seconds"=>r["recompile_seconds"]) for ((round,side,width),data) in observations
    for r in data["records"] if r["compile_seconds"] != 0 || r["recompile_seconds"] != 0]
result = Dict("schema"=>"reserved-cohort-fixed-work-summary/1","complete"=>true,"recorded_utc"=>string(now(UTC)),
    "protocol"=>reference["protocol"],"protocol_sha256"=>reference["protocol_sha256"],
    "original_instance"=>reference["instance_name"],"instance_sha256"=>reference["instance_sha256"],
    "timing_scope"=>reference["timing_scope"],"original_semantic_checks"=>semantic_checks,
    "measurements"=>length(all_rows),"paired_measurements"=>length(all_rows)÷2,"groups"=>groups,"summary"=>summary,
    "input_receipts"=>receipts,"before_packages"=>observations[(1,"before",1)]["package_sources"],
    "after_packages"=>observations[(1,"after",1)]["package_sources"],"native_dependencies"=>native,
    "non_controlled_dependency_graph_matches"=>true,"compiled_attempts"=>compiled,
    "all_warm_compilation_zero"=>isempty(compiled),
    "comparison_limit"=>reference["comparison_limit"],
    "baseline_limit"=>"The before cohort is the first published overnight performance cohort, already optimized; it is not old main.",
    "statistics_scope"=>"Each seed has two order-reversed process rounds and five samples per round. Best means minimum measured cost, not best solution. No outliers or GC-bearing observations are removed.",
    "initial_setup_scope"=>reference["initial_setup_scope"],
    "heap_phase"=>reference["heap_phase"],
    "warmups"=>[Dict("round"=>round,"side"=>side,"workers"=>width,"records"=>data["warmups"])
        for ((round,side,width),data) in sort!(collect(observations);by=x->x.first)])
open(output,"w") do io; TOML.print(io,result;sorted=true); end
for r in summary
    println((workers=r["workers"],method=r["method"],
        time_remaining_percent=r["remaining_percent"]["seconds"]["median"],
        bytes_remaining_percent=r["remaining_percent"]["bytes"]["median"],
        objects_remaining_percent=r["remaining_percent"]["objects"]["median"]))
end
println("All $(length(all_rows)) original-valid measurements and $semantic_checks semantic comparisons preserved; $(length(compiled)) warm compilation exceptions.")
end

main()
