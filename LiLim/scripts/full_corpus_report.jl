using ConstraintModels, TOML, SHA, Statistics, Printf
using ConstraintModels.Benchmarks

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
include(joinpath(ROOT, "LiLim", "src", "BenchmarkTargets.jl"))
length(ARGS) in (1, 2) || error("usage: full_corpus_report.jl CAMPAIGN_DIR [REPORT_DIR]")
const CAMPAIGN = abspath(ARGS[1])
const OUT = length(ARGS) == 2 ? abspath(ARGS[2]) : CAMPAIGN
const MANIFEST = TOML.parsefile(joinpath(CAMPAIGN, "manifest.toml"))
const IDENTITY = MANIFEST["identity"]
const BKS = TOML.parsefile(joinpath(ROOT, "LiLim", "config", "sintef-pdptw-bks-20261004.toml"))
const BUDGET = IDENTITY["budget_seconds"]
const THREADS = IDENTITY["threads"]
const METHODS = IDENTITY["methods"]
const SEEDS = IDENTITY["seeds"]
const INSTANCE_IDS = IDENTITY["instances"]
const CAMPAIGN_SCHEMA = IDENTITY["schema"]
const BKS_DISTANCE_DIGITS = IDENTITY["bks_distance_digits"]
family(id) = startswith(id, "lrc") ? "LRC" : startswith(id, "lc") ? "LC" : "LR"
digest(path) = bytes2hex(sha256(read(path)))

function instance_row(id)
    for size in keys(BKS["instances"])
        haskey(BKS["instances"][size], id) || continue
        target = BKS["instances"][size][id]
        path = joinpath(ROOT, "LiLim", "data", "raw", "pdp_" * size, id * ".txt")
        return (; id, size=parse(Int, size), path, bks_vehicles=target["vehicles"], bks_distance=target["distance"])
    end
    error("instance is absent from the frozen SINTEF BKS table: $id")
end

function validate_routes(problem, routes, vehicles, distance)
    result = validate_solution(problem, routes)
    result.valid || error("stored route fails original problem validation")
    result.objective.vehicles == vehicles || error("stored vehicle objective mismatch")
    isapprox(result.objective.distance, distance; atol=1e-8, rtol=1e-12) || error("stored distance objective mismatch")
    result.objective
end

function read_trial(row, method, seed, problems)
    path = joinpath(CAMPAIGN, "trials", row.id * "__" * method * "__seed-" * string(seed) * ".toml")
    isfile(path) || return nothing
    seal = path * ".sha256"
    isfile(seal) && strip(read(seal, String)) == digest(path) || error("missing or corrupt trial seal: $path")
    record = TOML.parsefile(path)
    (record["instance"], record["method"], record["seed"], record["budget_seconds"], record["threads_requested"]) ==
        (row.id, method, seed, BUDGET, THREADS) || error("trial identity mismatch: $path")
    record["run_fingerprint"] == MANIFEST["run_fingerprint"] || error("trial belongs to another campaign")
    record["original_validation"] || error("trial was not validated originally")
    expected_source = IDENTITY["instance_sha256"][row.id]
    record["source_sha256"] == expected_source || error("trial references a different instance source")
    record["bks_vehicles"] == row.bks_vehicles && record["bks_distance"] == row.bks_distance || error("trial reference target mismatch")
    expected_bks = BenchmarkTargets.reaches_published_bks(record["vehicles"], record["distance"],
        row.bks_vehicles, row.bks_distance; distance_digits=BKS_DISTANCE_DIGITS)
    record["bks_reached"] == expected_bks || error("stored BKS attainment disagrees with the published-precision rule")
    expected_bks_time = nothing
    for event in record["trajectory"]
        if BenchmarkTargets.reaches_published_bks(event["vehicles"], event["distance"],
                row.bks_vehicles, row.bks_distance; distance_digits=BKS_DISTANCE_DIGITS)
            expected_bks_time = event["seconds"]
            break
        end
    end
    actual_bks_time = record["time_to_bks_seconds"]
    if expected_bks_time === nothing
        actual_bks_time == "not_reached" || error("stored BKS time exists without a qualifying trajectory point")
    else
        actual_bks_time isa Real && isapprox(actual_bks_time, expected_bks_time; atol=1e-9, rtol=0) ||
            error("stored time-to-BKS disagrees with the published-precision rule")
    end
    problem = get!(problems, row.id) do
        digest(row.path) == expected_source || error("current source changed: $(row.id)")
        read_benchmark(row.path, :li_lim; id=row.id)
    end
    validate_routes(problem, record["routes"], record["vehicles"], record["distance"])
    for event in record["trajectory"]
        0 <= event["seconds"] <= BUDGET || error("trajectory contains a late observation")
        validate_routes(problem, event["routes"], event["vehicles"], event["distance"])
    end
    record
end

function median_run(rows)
    ordered = sort(rows; by=row->(row["vehicles"], row["distance"], row["seed"]))
    ordered[cld(length(ordered), 2)]
end

function cell_summary(row, method, runs, planned)
    feasible = filter(record->record["original_validation"], runs)
    best = isempty(feasible) ? nothing : first(sort(feasible; by=r->(r["vehicles"], r["distance"])))
    middle = isempty(feasible) ? nothing : median_run(feasible)
    reached = [Float64(r["time_to_bks_seconds"]) for r in feasible if r["time_to_bks_seconds"] isa Real]
    distances = [Float64(r["distance"]) for r in feasible]
    vehicles = [Float64(r["vehicles"]) for r in feasible]
    Dict{String,Any}(
        "size"=>row.size, "family"=>family(row.id), "instance"=>row.id, "method"=>method,
        "bks_vehicles"=>row.bks_vehicles, "bks_distance"=>row.bks_distance,
        "planned_runs"=>planned, "completed_runs"=>length(runs), "feasible_runs"=>length(feasible),
        "completion_rate"=>length(runs)/planned, "feasibility_rate"=>(isempty(runs) ? 0.0 : length(feasible)/length(runs)),
        "bks_hits"=>count(get(r, "bks_reached", false) for r in feasible),
        "bks_hit_rate"=>(isempty(runs) ? 0.0 : count(get(r, "bks_reached", false) for r in feasible)/planned),
        "best_seed"=>(best === nothing ? -1 : best["seed"]),
        "best_vehicles"=>(best === nothing ? -1 : best["vehicles"]),
        "best_distance"=>(best === nothing ? -1.0 : best["distance"]),
        "median_seed"=>(middle === nothing ? -1 : middle["seed"]),
        "median_vehicles"=>(middle === nothing ? -1 : middle["vehicles"]),
        "median_distance"=>(middle === nothing ? -1.0 : middle["distance"]),
        "mean_vehicles"=>(isempty(vehicles) ? -1.0 : mean(vehicles)),
        "std_vehicles"=>(length(vehicles) < 2 ? 0.0 : std(vehicles)),
        "min_vehicles"=>(isempty(vehicles) ? -1 : minimum(vehicles)),
        "max_vehicles"=>(isempty(vehicles) ? -1 : maximum(vehicles)),
        "mean_distance"=>(isempty(distances) ? -1.0 : mean(distances)),
        "std_distance"=>(length(distances) < 2 ? 0.0 : std(distances)),
        "min_distance"=>(isempty(distances) ? -1.0 : minimum(distances)),
        "max_distance"=>(isempty(distances) ? -1.0 : maximum(distances)),
        "bks_times_seconds"=>reached,
        "mean_bks_time_seconds"=>(isempty(reached) ? -1.0 : mean(reached)),
        "median_bks_time_seconds"=>(isempty(reached) ? -1.0 : median(reached)))
end

function method_summaries(cells, method)
    selected = filter(row->row["method"] == method, cells)
    completed = sum(row["completed_runs"] for row in selected)
    planned = sum(row["planned_runs"] for row in selected)
    feasible = sum(row["feasible_runs"] for row in selected)
    hits = sum(row["bks_hits"] for row in selected)
    avg_best_gap = [row["best_vehicles"] - row["bks_vehicles"] for row in selected if row["best_vehicles"] >= 0]
    avg_mean_gap = [row["mean_vehicles"] - row["bks_vehicles"] for row in selected if row["mean_vehicles"] >= 0]
    avg_median_gap = [row["median_vehicles"] - row["bks_vehicles"] for row in selected if row["median_vehicles"] >= 0]
    distance_gaps = Float64[]
    for row in selected
        row["median_vehicles"] == row["bks_vehicles"] && row["median_distance"] >= 0 || continue
        push!(distance_gaps, 100 * (row["median_distance"] / row["bks_distance"] - 1))
    end
    bks_times = reduce(vcat, (row["bks_times_seconds"] for row in selected); init=Float64[])
    active_cpu = Float64[]
    gc_seconds = Float64[]
    whole_trial_gc_seconds = Float64[]
    infeasible_fraction = Float64[]
    tabu_entries = Int[]
    reset_counts = Int[]
    for id in INSTANCE_IDS, seed in SEEDS
        path = joinpath(CAMPAIGN, "trials", id * "__" * method * "__seed-" * string(seed) * ".toml")
        isfile(path) || continue
        record=TOML.parsefile(path)
        push!(active_cpu, record["mean_active_cpus"])
        haskey(record,"search_gc_seconds") && push!(gc_seconds,record["search_gc_seconds"])
        haskey(record,"gc_scope") && startswith(record["gc_scope"],"whole trial:") &&
            push!(whole_trial_gc_seconds,record["gc_seconds"])
        for worker in get(record,"workers",Any[])
            trace=worker["trace"]
            get(trace,"steps",0)>0 && haskey(trace,"infeasible_steps") &&
                push!(infeasible_fraction,trace["infeasible_steps"]/trace["steps"])
            haskey(trace,"max_tabu_entries") && push!(tabu_entries,trace["max_tabu_entries"])
            get(trace,"sequence_or_exhaustion_resets",-1)>=0 &&
                push!(reset_counts,trace["sequence_or_exhaustion_resets"])
        end
    end
    Dict{String,Any}(
        "method"=>method, "planned_runs"=>planned, "completed_runs"=>completed, "feasible_runs"=>feasible,
        "completion_rate"=>(planned == 0 ? 0.0 : completed/planned),
        "feasibility_rate"=>(completed == 0 ? 0.0 : feasible/completed),
        "bks_hits"=>hits, "bks_hit_rate"=>(planned == 0 ? 0.0 : hits/planned),
        "mean_best_fleet_gap"=>(isempty(avg_best_gap) ? -1.0 : mean(avg_best_gap)),
        "mean_run_fleet_gap"=>(isempty(avg_mean_gap) ? -1.0 : mean(avg_mean_gap)),
        "mean_median_run_fleet_gap"=>(isempty(avg_median_gap) ? -1.0 : mean(avg_median_gap)),
        "median_distance_gap_at_bks_fleet_percent"=>(isempty(distance_gaps) ? -1.0 : median(distance_gaps)),
        "cells_at_bks_fleet"=>length(distance_gaps),
        "mean_time_to_bks_seconds"=>(isempty(bks_times) ? -1.0 : mean(bks_times)),
        "median_time_to_bks_seconds"=>(isempty(bks_times) ? -1.0 : median(bks_times)),
        "bks_time_observations"=>length(bks_times),
        "mean_active_cpus"=>(isempty(active_cpu) ? -1.0 : mean(active_cpu)),
        "mean_search_gc_seconds"=>(isempty(gc_seconds) ? -1.0 : mean(gc_seconds)),
        "mean_whole_trial_gc_seconds"=>(isempty(whole_trial_gc_seconds) ? -1.0 : mean(whole_trial_gc_seconds)),
        "mean_infeasible_step_fraction"=>(isempty(infeasible_fraction) ? -1.0 : mean(infeasible_fraction)),
        "max_observed_tabu_entries"=>maximum(tabu_entries;init=-1),
        "mean_sequence_or_exhaustion_resets"=>(isempty(reset_counts) ? -1.0 : mean(reset_counts)))
end

function size_summaries(cells, methods)
    sizes = sort!(unique([row["size"] for row in cells]))
    rows = Any[]
    for size in sizes, method in methods
        selected = filter(row->row["size"] == size && row["method"] == method, cells)
        isempty(selected) && continue
        completed = sum(row["completed_runs"] for row in selected)
        planned = sum(row["planned_runs"] for row in selected)
        valid_cells = filter(row->row["best_vehicles"] >= 0, selected)
        best_gaps = [row["best_vehicles"]-row["bks_vehicles"] for row in valid_cells]
        mean_gaps = [row["mean_vehicles"]-row["bks_vehicles"] for row in valid_cells]
        median_gaps = [row["median_vehicles"]-row["bks_vehicles"] for row in valid_cells]
        distance_gaps = [100*(row["median_distance"]/row["bks_distance"]-1) for row in valid_cells
            if row["median_vehicles"] == row["bks_vehicles"]]
        push!(rows, Dict{String,Any}(
            "size"=>size, "method"=>method, "instances"=>length(selected),
            "valid_cells"=>length(valid_cells),
            "completed_runs"=>completed, "planned_runs"=>planned,
            "bks_hits"=>sum(row["bks_hits"] for row in selected),
            "bks_hit_rate"=>(planned == 0 ? 0.0 : sum(row["bks_hits"] for row in selected)/planned),
            "mean_best_fleet_gap"=>(isempty(best_gaps) ? -1.0 : mean(best_gaps)),
            "mean_run_fleet_gap"=>(isempty(mean_gaps) ? -1.0 : mean(mean_gaps)),
            "mean_median_run_fleet_gap"=>(isempty(median_gaps) ? -1.0 : mean(median_gaps)),
            "mean_distance_gap_at_bks_fleet_percent"=>(isempty(distance_gaps) ? -1.0 : mean(distance_gaps)),
            "distance_cells"=>length(distance_gaps)))
    end
    rows
end

function write_report(path, summary)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# SINTEF Li-Lim Benchmark Report\n")
        skipped=get(IDENTITY,"skipped_methods",[])
        if !isempty(skipped)
            println(io,"## Unavailable optional solvers\n\nThese profiles were skipped before any solve. They are excluded from success, infeasibility and timing denominators.\n\n| Profile | Status | Reason |\n|---|---|---|")
            for row in skipped
                println(io,"| `",row["method"],"` | skipped | `",row["reason"],"` |")
            end
            println(io)
        end
        println(io, "Campaign fingerprint: `", summary["run_fingerprint"], "`. The frozen scope contains ",
            summary["instance_count"], " instances, ", summary["method_count"], " solver profiles, ",
            summary["seed_count"], " repeat labels, ", summary["threads"], " workers and a ",
            summary["budget_seconds"], " second wall budget per trial.\n")
        println(io,"Resource policy: `",get(IDENTITY,"affinity_mode","hard_cpu_affinity"),"`. Linux pins CPU IDs. macOS and Windows cap solver threads without claiming a hard CPU mask or P-core placement. Windows child CPU is sampled; macOS uses reaped-child CPU accounting. Cross-host results must identify this difference.\n")
        println(io, "The official SINTEF archive checksums and all ", summary["instance_count"],
            " extracted instance checksums were verified. Every stored incumbent and every trajectory point in the report was revalidated against the original Li-Lim instance. The fleet objective has priority; raw double-precision Euclidean distance is compared only after fleet count.\n")
        if "ortools_native" in summary["methods"]
            println(io, "The OR-Tools profile is the pinned 9.14.6206 RoutingModel with Guided Local Search, run as one search thread (pinned to one selected CPU on Linux). Wider campaign settings do not increase OR-Tools' thread count; the OR-Tools CPU-use row reports measured process and Julia-controller CPU. Repetition seed values identify trials but are not applied, so the default GLS search parameters stay unchanged. These are repeated timings of the same configuration, not independent random-seed experiments. The model uses a dominating fixed vehicle cost to encode the Li-Lim fleet-then-distance ranking and a shared insertion start; this is a local comparison profile, not an exact reproduction of Hexaly's published OR-Tools model. Costs use integer-scaled distances, time windows are conservatively integer-scaled, capacities remain exact integers, and the original Julia validator remains authoritative.\n")
        end
        println(io, "SINTEF publishes its distance targets to ", summary["bks_distance_digits"],
            " decimal places. BKS attainment rounds the candidate to that displayed precision; raw double-precision distances remain in the results and determine solver rankings.\n")
        println(io, "## Interactive comparison and English figures\n\n[Open the interactive comparison](figures-exact/interactive.html) to select individual profiles or whole solver families. It opens with the best profile in each family selected; fixed SINTEF target marks remain visible when profiles are hidden. Crowded static solver comparisons use one small panel per profile, with shared scales, so overlapping curves remain separately inspectable. Every static plot has a precise version and an XKCDMakie version. Dotted zero lines mark the SINTEF reference where applicable; the dotted line in the CPU plot marks the allocated worker count.\n")
        println(io, "### Interactive view\n\nThe dashboard is self-contained and works offline. Its controls select CBLS, hybrid, HiGHS, OR-Tools, GHOST, MetaStrategist or Hexaly profiles individually or by family, and its measure selector switches between BKS attainment, fleet/distance gaps and CPU use. Hover over a marker for the corresponding value.\n")
        figures = (
            ("lilim-bks-attainment", "Time to the SINTEF best-known target"),
            ("lilim-quality-best-fleet-gap-by-profile", "Best fleet gap by solver profile"),
            ("lilim-quality-mean-fleet-gap-by-profile", "Mean-run fleet gap by solver profile"),
            ("lilim-quality-median-fleet-gap-by-profile", "Median-run fleet gap by solver profile"),
            ("lilim-quality-distance-gap-by-profile", "Median distance gap by solver profile"),
            ("lilim-bks-success-by-size", "Best-known solution success by instance or size"),
            ("lilim-cpu-use", "Effective CPU use by solver profile"),
        )
        for (name, caption) in figures
            exact_png = relpath(joinpath(CAMPAIGN, "figures-exact", name * ".png"), dirname(path))
            exact_pdf = relpath(joinpath(CAMPAIGN, "figures-exact", name * ".pdf"), dirname(path))
            xkcd_png = relpath(joinpath(CAMPAIGN, "figures-xkcd", name * "-xkcd.png"), dirname(path))
            xkcd_pdf = relpath(joinpath(CAMPAIGN, "figures-xkcd", name * "-xkcd.pdf"), dirname(path))
            println(io, "### ", caption, "\n")
            println(io, "![", caption, "](", exact_png, ")\n")
            println(io, "[Exact PNG](", exact_png, ") · [Exact PDF](", exact_pdf,
                ") · [XKCD PNG](", xkcd_png, ") · [XKCD PDF](", xkcd_pdf, ")\n")
        end
        println(io, "## Results by solver profile\n\n| Profile | Completed / planned | Feasible / completed | BKS hits / planned | Best fleet gap per instance | Mean-run fleet gap per instance | Median-run fleet gap per instance | Median distance gap at BKS fleet | Mean time to BKS (s) | Mean active CPUs |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in summary["method_summary"]
            distance = row["cells_at_bks_fleet"] == 0 ? "—" : @sprintf("%.3f%% (%d cells)", row["median_distance_gap_at_bks_fleet_percent"], row["cells_at_bks_fleet"])
            bks_time = row["mean_time_to_bks_seconds"] < 0 ? "—" : @sprintf("%.2f (%d hits)", row["mean_time_to_bks_seconds"], row["bks_time_observations"])
            println(io, @sprintf("| %s | %d / %d | %d / %d (%.1f%%) | %d / %d (%.1f%%) | %.3f | %.3f | %.3f | %s | %s | %.2f |",
                row["method"], row["completed_runs"], row["planned_runs"], row["feasible_runs"], row["completed_runs"],
                100 * row["feasibility_rate"], row["bks_hits"], row["planned_runs"], 100 * row["bks_hit_rate"],
                row["mean_best_fleet_gap"], row["mean_run_fleet_gap"], row["mean_median_run_fleet_gap"], distance, bks_time, row["mean_active_cpus"]))
        end
        descriptions = Dict(
            "cbls_naive"=>"Handwritten constraint residuals reduced to one Boolean infeasibility indicator per candidate.",
            "cbls_icn"=>"Recovered learned ICN decoders are called for each scalar constraint and for each pickup-delivery route-equality and precedence constraint.",
            "cbls_icn_fused_scalar"=>"Compatible scalar residuals are grouped through one learned sum-condition ICN; learned route-equality and precedence decoders still run separately for every pair.",
            "cbls_icn_fused_all"=>"Scalar residuals and direct pickup-delivery violation indicators are grouped through one learned sum-condition ICN; pair-specific equality and precedence ICN decoders are bypassed.",
            "cbls_direct"=>"Handwritten scalar residuals and direct pickup-delivery violation indicators; no ICN decoder is called.",
            "hybrid_specialized_icn"=>"Learned-ICN CBLS with HiGHS repair subproblems using the specialized Li-Lim formulation.",
            "hybrid_bridged_icn"=>"Learned-ICN CBLS with HiGHS repair subproblems using the qualified XCSP3Bridges fragment.",
            "highs_native"=>"HiGHS solves the full native mixed-integer model with its requested thread pool.",
            "highs_portfolio"=>"Independent serial HiGHS searches run as a parallel portfolio and merge their best validated incumbents.",
            "cbls_mix_strategy"=>"A fixed portfolio of CBLS policies uses the learned-ICN scorer and merges independent validated incumbents.",
            "mixed_balanced"=>"MetaStrategist executes a fixed balanced allocation of CBLS, specialized hybrid, bridged hybrid and serial HiGHS workers.",
            "mixed_ls_heavy"=>"MetaStrategist executes a fixed search-heavy allocation of CBLS, specialized hybrid, bridged hybrid and serial HiGHS workers.",
            "ortools_native"=>"Pinned Google OR-Tools 9.14.6206 RoutingModel with Guided Local Search, one internal search thread and one-core affinity; fleet priority is encoded by a dominating fixed vehicle cost. Every stored incumbent is checked against the original Li-Lim validator.",
            "ghost_icn"=>"Native development GHOST through GHOST.jl/MOI, permutation neighborhood and the same qualified PDPTW ICN scorer. Each Julia lane owns one native worker, model and private buffers. Native RNG seed and tabu/reset counters are not exposed; repetition labels are not applied as seeds. Original-validator-approved incumbents are censored at the common wall deadline.",
            "hexaly_native"=>"Hexaly native Modeler profile at the configured target version, launched with the same validated insertion start, full trial wall-clock cap and explicit CPU affinity; every stored incumbent is checked against the original Li-Lim validator.")
        println(io, "\n## Score and solver provenance\n\nThe ICN variants below use the frozen learned-weight bank recorded in `manifest.toml`. `Fused all` is an aggregate-ICN ablation: its pairwise violation indicators are formed directly before learned aggregation, so it does not execute the individual pair decoders used by `CBLS learned ICN`. The differential tests establish score identity on their qualified synthetic domain; benchmark performance is reported separately.\n\n| Profile | Executed score or solver path |\n|---|---|")
        for method in METHODS
            config=get(IDENTITY,"strategy_variants",Dict())
            variant=findfirst(row->row["method"]==method,get(config,"variants",Any[]))
            description=get(descriptions, method, "Profile description unavailable; inspect the frozen source manifest.")
            if variant!==nothing
                row=config["variants"][variant]
                description="Recovered learned ICN scorer with existing policy `$(row["policy"])`; " *
                    (get(row,"hybrid",false) ? (get(row,"bridged",false) ? "qualified XCSP3Bridges RO repair." : "specialized HiGHS RO repair.") : "native CBLS and paired reinsertion.")
            elseif haskey(get(config,"portfolios",Dict()),method)
                description="MetaStrategist executes fixed independently seeded lanes: " * join(config["portfolios"][method],", ") * ". No adaptive allocation or live exchange."
            end
            println(io, "| `", method, "` | ", description, " |")
        end
        if haskey(IDENTITY,"strategy_variants")
            println(io,"\n## Executed strategy diagnostics\n\nHistorical CBLS lanes retain their greedy acceptance, no tabu and zero-fraction best-state resets. Added policies can temporarily become infeasible; feasible-route reinsertion and RO snapshots are skipped until the native scorer has restored feasibility. Exported best solutions and trajectory points remain independently validated. Reset probabilities are per native step; the native stagnation trigger also applies except for exhaustion policies. Partial resets change raw successor variables, and can be ineffective on route structure; their quality is measured rather than assumed.\n")
            println(io,"| Profile | Mean search GC (s) | Mean whole-trial GC (s) | Mean infeasible-step share | Maximum tabu entries | Mean observable native resets per lane |\n|---|---:|---:|---:|---:|---:|")
            for row in summary["method_summary"]
                showvalue(key;percent=false)=row[key]<0 ? "—" : @sprintf("%.3f%s",row[key]*(percent ? 100 : 1),percent ? "%" : "")
                println(io,"| `",row["method"],"` | ",showvalue("mean_search_gc_seconds")," | ",showvalue("mean_whole_trial_gc_seconds")," | ",showvalue("mean_infeasible_step_fraction";percent=true)," | ",row["max_observed_tabu_entries"]<0 ? "—" : row["max_observed_tabu_entries"]," | ",showvalue("mean_sequence_or_exhaustion_resets")," |")
            end
            println(io,"\nNative universal-sequence and exhaustion reset counts are observable. Random/tabu-triggered counts are unavailable and shown as a dash; they are never inferred. GC counters cover all Julia lanes in the process: search-phase and whole-trial measurements are reported separately. GHOST's whole-trial measurement includes parsing, common insertion, model construction, search and original validation; it is not a search-only measurement. Infeasible-step share is a lane average. Exact policy settings, allocations and source hashes are frozen in the manifest and lane traces.\n")
        end
        println(io, "\nA fleet gap of zero means the fleet matches the SINTEF reference; a negative gap is better. Best, mean-run and median-run fleet gaps are averaged per instance so large instances do not dominate. Per-instance output includes the best run, one actual median-ranked run, mean, standard deviation and full min/max spread across feasible seeds. The distance gap is shown only for instance cells whose median-ranked run uses the BKS fleet; distance remains a secondary objective. BKS time is conditional on hits, and misses are censored at the campaign budget in the attainment plot.\n")
        println(io, "## Results by problem size\n\n| Requests | Profile | BKS hits / planned | Mean best fleet gap | Mean run fleet gap | Mean median-run fleet gap | Median-run distance gap at BKS fleet |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|")
        for row in summary["size_summary"]
            distance = row["distance_cells"] == 0 ? "—" : @sprintf("%.3f%% (%d cells)", row["mean_distance_gap_at_bks_fleet_percent"], row["distance_cells"])
            println(io, @sprintf("| %d | %s | %d / %d (%.1f%%) | %.3f | %.3f | %.3f | %s |", row["size"], row["method"],
                row["bks_hits"], row["planned_runs"], 100 * row["bks_hit_rate"], row["mean_best_fleet_gap"], row["mean_run_fleet_gap"], row["mean_median_run_fleet_gap"], distance))
        end
        println(io, "\n## Reproducibility\n\n- Julia: `", IDENTITY["julia"], "`.\n- Threads: ", THREADS, "; GC threads: ", IDENTITY["gc_threads"], "; affinity: `", join(IDENTITY["affinity"], ","), "`.\n- Seeds: `", join(SEEDS, ", "), "`; budget: ", BUDGET, " seconds.\n- Source manifest, solver environment, cohort, official archives, per-instance checksums and BKS values are in `manifest.toml`.\n- Detailed per-instance best, mean, median-ranked run, standard deviation, min/max spread, BKS success and time-to-target metrics are in `summary.toml` and `per-instance.csv`.")
        if !isempty(get(IDENTITY, "hexaly", Dict{String,Any}()))
            hexaly = IDENTITY["hexaly"]
            println(io, "- Hexaly: target version `", hexaly["target_version"], "`; executable SHA-256 `", hexaly["binary_sha256"], "`; common clock skew and observed child-process CPU are recorded per trial.\n")
        end
        if !summary["complete"]
            println(io, "## Incomplete campaign\n\n", summary["missing_runs"], " scheduled trials are missing. Completion and feasibility statistics use separate denominators; an absent run is not reported as a solver infeasibility.\n")
        end
    end
end

function write_csv(path, cells)
    open(path, "w") do io
        println(io, "size,family,instance,method,planned_runs,completed_runs,feasible_runs,feasibility_rate,bks_hits,bks_hit_rate,bks_vehicles,bks_distance,best_seed,best_vehicles,best_distance,median_seed,median_vehicles,median_distance,mean_vehicles,std_vehicles,min_vehicles,max_vehicles,mean_distance,std_distance,min_distance,max_distance,mean_bks_time_seconds,median_bks_time_seconds")
        for row in cells
            println(io, join((row[key] for key in ("size","family","instance","method","planned_runs","completed_runs","feasible_runs","feasibility_rate","bks_hits","bks_hit_rate","bks_vehicles","bks_distance","best_seed","best_vehicles","best_distance","median_seed","median_vehicles","median_distance","mean_vehicles","std_vehicles","min_vehicles","max_vehicles","mean_distance","std_distance","min_distance","max_distance","mean_bks_time_seconds","median_bks_time_seconds")), ','))
        end
    end
end

problems = Dict{String,Any}()
instances = [instance_row(id) for id in INSTANCE_IDS]
cells = Any[]
for row in instances, method in METHODS
    runs = Any[]
    for seed in SEEDS
        result = read_trial(row, method, seed, problems)
        result === nothing || push!(runs, result)
    end
    push!(cells, cell_summary(row, method, runs, length(SEEDS)))
end
expected = length(instances)*length(METHODS)*length(SEEDS)
completed = sum((row["completed_runs"] for row in cells);init=0)
summary = Dict{String,Any}(
    "schema"=>"li-lim-full-corpus-summary/1", "run_fingerprint"=>MANIFEST["run_fingerprint"],
    "complete"=>(completed == expected && get(MANIFEST,"complete",false)),
    "missing_runs"=>expected-completed, "budget_seconds"=>BUDGET, "threads"=>THREADS,
    "bks_distance_digits"=>BKS_DISTANCE_DIGITS,
    "seed_count"=>length(SEEDS), "seeds"=>SEEDS, "instance_count"=>length(instances),
    "method_count"=>length(METHODS), "instances"=>INSTANCE_IDS, "methods"=>METHODS,
    "requested_methods"=>get(IDENTITY,"requested_methods",METHODS),
    "skipped_methods"=>get(IDENTITY,"skipped_methods",[]),
    "instance_results"=>cells,
    "method_summary"=>[method_summaries(cells,method) for method in METHODS],
    "size_summary"=>size_summaries(cells,METHODS))
mkpath(OUT)
open(joinpath(OUT,"summary.toml"),"w") do io
    TOML.print(io,summary;sorted=true)
end
write_csv(joinpath(OUT,"per-instance.csv"),cells)
write_report(joinpath(OUT,"report.md"),summary)
println("Validated ",completed," / ",expected," trials; summary: ",joinpath(OUT,"report.md"))
