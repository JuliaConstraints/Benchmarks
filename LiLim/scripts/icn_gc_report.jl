using TOML, SHA, Statistics, Printf, CairoMakie, XKCDMakie, Random

length(ARGS) == 4 || error("usage: icn_gc_report.jl CAMPAIGN_8T CAMPAIGN_16T PERFCHECK_DIR OUTPUT_DIR")
const CAMPAIGNS = Dict(8=>abspath(ARGS[1]), 16=>abspath(ARGS[2]))
const PERF_DIR = abspath(ARGS[3])
const OUT = abspath(ARGS[4])
const METHODS = ["cbls_icn", "hybrid_specialized_icn", "hybrid_bridged_icn", "mixed_balanced", "mixed_ls_heavy"]
const LABELS = Dict(
    "cbls_icn"=>"CBLS learned ICN",
    "hybrid_specialized_icn"=>"Hybrid specialized",
    "hybrid_bridged_icn"=>"Hybrid XCSP3",
    "mixed_balanced"=>"Meta balanced",
    "mixed_ls_heavy"=>"Meta search-heavy")
const COLORS = [:dodgerblue3, :darkorange2, :seagreen3, :purple3, :firebrick3]
digest(path) = bytes2hex(sha256(read(path)))

function read_runs(threads, method)
    dir = CAMPAIGNS[threads]
    manifest = TOML.parsefile(joinpath(dir, "manifest.toml"))
    identity = manifest["identity"]
    identity["threads"] == threads || error("campaign thread count mismatch: $dir")
    identity["budget_seconds"] == 60 || error("expected the paired 60-second campaign: $dir")
    runs = Any[]
    for instance in identity["instances"], seed in identity["seeds"]
        path = joinpath(dir, "trials", "$(instance)__$(method)__seed-$(seed).toml")
        isfile(path) || error("missing paired campaign trial: $path")
        seal = path * ".sha256"
        isfile(seal) && strip(read(seal, String)) == digest(path) || error("missing or corrupt trial seal: $path")
        record = TOML.parsefile(path)
        record["run_fingerprint"] == manifest["run_fingerprint"] || error("trial fingerprint mismatch: $path")
        record["original_validation"] || error("unvalidated trial in campaign: $path")
        record["method"] == method && record["threads_requested"] == threads || error("trial identity mismatch: $path")
        record["wall_seconds"] > 0 && record["search_gc_seconds"] >= 0 || error("invalid GC measurement: $path")
        push!(runs, record)
    end
    runs
end

const CAMPAIGN_RUNS = Dict((threads, method)=>read_runs(threads, method)
    for threads in (8, 16) for method in METHODS)

function perf_summary(threads, method)
    name = method == "cbls_icn" ? "cbls-icn-$(threads)t-planned" :
        method == "mixed_balanced" ? "meta-balanced-$(threads)t" :
        method == "mixed_ls_heavy" ? "meta-heavy-$(threads)t" : nothing
    name === nothing && return Dict("status"=>"not_captured")
    path = joinpath(PERF_DIR, "perfchecker-$(name)-20261005.toml")
    isfile(path) || error("missing PerfChecker profile: $path")
    result = TOML.parsefile(path)
    result["complete"] || error("incomplete PerfChecker result: $path")
    result["worker_threads"] == threads || error("PerfChecker width mismatch: $path")
    collectors = Dict{String,Any}()
    for collector in result["collectors"]
        rows = get(collector, "rows", Any[])
        sites = Dict{String,Int}()
        for row in rows
            site = replace(string(get(row, "filename", "?"), ":", get(row, "line", 0)), homedir()=>"~")
            sites[site] = get(sites, site, 0) + get(row, "samples", 0)
        end
        top_sites = sort!(collect(sites); by=last, rev=true)
        collectors[collector["backend"]] = Dict(
            "sampled_sites"=>length(rows),
            "samples"=>sum(get(row, "samples", 0) for row in rows),
            "top_sites"=>[Dict("site"=>first(item), "samples"=>last(item)) for item in Iterators.take(top_sites, 8)])
    end
    Dict("status"=>"complete", "file"=>basename(path), "method"=>method,
        "threads"=>threads, "gc_threads_environment"=>result["gc_threads_environment"],
        "perfchecker_revision"=>result["perfchecker_revision"], "collectors"=>collectors)
end

const METHODS_SUMMARY = Any[]
for method in METHODS, threads in (8, 16)
    runs = CAMPAIGN_RUNS[(threads, method)]
    gc_seconds = [Float64(run["search_gc_seconds"]) for run in runs]
    gc_share = [100 * run["search_gc_seconds"] / run["wall_seconds"] for run in runs]
    active_cpu = [Float64(run["mean_active_cpus"]) for run in runs]
    push!(METHODS_SUMMARY, Dict(
        "method"=>method, "threads"=>threads, "runs"=>length(runs),
        "mean_gc_seconds"=>mean(gc_seconds), "median_gc_seconds"=>median(gc_seconds),
        "mean_gc_wall_percent"=>mean(gc_share), "median_gc_wall_percent"=>median(gc_share),
        "mean_active_cpus"=>mean(active_cpu)))
end

const PROFILE_SUMMARY = Dict(string(threads)=>Dict(method=>perf_summary(threads, method)
    for method in ("cbls_icn", "mixed_balanced", "mixed_ls_heavy")) for threads in (8, 16))

function make_plot(style)
    if style == "xkcd"
        Random.seed!(41)
        set_theme!(XKCDMakie.theme_xkcd())
    else
        set_theme!(Theme(font="DejaVu Sans", fontsize=16, linewidth=2.5,
            Axis=(xgridvisible=false, ygridcolor=(:gray, .18), titlesize=20)))
    end
    fig = Figure(size=(1600, 900))
    Label(fig[0, 1:2], "Garbage-Collector Share of Search Wall Time", fontsize=27)
    ax = Axis(fig[1, 1]; xlabel="Solver profile", ylabel="Mean collector time / search wall time (%)",
        xticks=(1:length(METHODS), [LABELS[method] for method in METHODS]))
    ax.xticklabelrotation = π / 10
    for (index, method) in enumerate(METHODS)
        rows8 = filter(row->row["method"] == method && row["threads"] == 8, METHODS_SUMMARY)
        rows16 = filter(row->row["method"] == method && row["threads"] == 16, METHODS_SUMMARY)
        barplot!(ax, [index - 0.19], [only(rows8)["mean_gc_wall_percent"]]; width=0.34,
            color=COLORS[index], label=index == 1 ? "8 worker threads" : nothing)
        barplot!(ax, [index + 0.19], [only(rows16)["mean_gc_wall_percent"]]; width=0.34,
            color=COLORS[index], alpha=0.48, label=index == 1 ? "16 worker threads" : nothing)
    end
    Legend(fig[1, 2], ax; framevisible=false)
    ylims!(ax, 0, maximum(row["mean_gc_wall_percent"] for row in METHODS_SUMMARY) * 1.15)
    Label(fig[2, 1:2], "Mean across nine validated trials per bar. Per-trial process-global GC time / search wall time.", fontsize=15)
    suffix = style == "xkcd" ? "-xkcd" : ""
    for extension in ("png", "pdf")
        save(joinpath(OUT, "lilim-gc-share-8-vs-16" * suffix * "." * extension), fig; px_per_unit=1.5)
    end
end

mkpath(OUT)
summary = Dict("schema"=>"li-lim-resource-profile-summary/1",
    "campaigns"=>Dict(string(threads)=>TOML.parsefile(joinpath(CAMPAIGNS[threads], "manifest.toml"))["run_fingerprint"] for threads in (8, 16)),
    "methods"=>METHODS_SUMMARY, "perfchecker"=>PROFILE_SUMMARY)
open(joinpath(OUT, "summary.toml"), "w") do io
    TOML.print(io, summary; sorted=true)
end

make_plot("exact")
make_plot("xkcd")

open(joinpath(OUT, "report.md"), "w") do io
    println(io, "# Li-Lim resource profile: GC and PerfChecker\n")
    println(io, "This post-run analysis compares the fully validated 60-second, 8-thread and 16-thread SINTEF pilot cohorts for lc101, lr101 and lrc101 (three seeds per instance). The width comparison uses eight P-cores versus all 12 physical cores plus four SMT siblings. Each GC observation comes from a sealed trial file; the original campaign reports revalidated every route and trajectory point against Li-Lim.\n")
    println(io, "![Garbage-collector share of search wall time](lilim-gc-share-8-vs-16.png)\n")
    println(io, "[Exact PNG](lilim-gc-share-8-vs-16.png) · [Exact PDF](lilim-gc-share-8-vs-16.pdf) · [XKCD PNG](lilim-gc-share-8-vs-16-xkcd.png) · [XKCD PDF](lilim-gc-share-8-vs-16-xkcd.pdf)\n")
    println(io, "## GC summary\n\n| Profile | Threads | Runs | Mean GC seconds | Median GC seconds | Mean GC share of wall time | Mean active CPUs |\n|---|---:|---:|---:|---:|---:|---:|")
    for row in METHODS_SUMMARY
        println(io, @sprintf("| %s | %d | %d | %.3f | %.3f | %.2f%% | %.2f |",
            LABELS[row["method"]], row["threads"], row["runs"], row["mean_gc_seconds"],
            row["median_gc_seconds"], row["mean_gc_wall_percent"], row["mean_active_cpus"]))
    end
    println(io, "\nThe metric is per-trial process-global `Base.gc_num().total_time` inside the shared search interval divided by that trial's wall time. Forced precollection and final validation are excluded; collection across Julia worker threads is included. These captures show collector time, not allocation volume, and the three-seed cohort is too small to establish statistical superiority.\n")
    println(io, "## PerfChecker stack samples\n\nPerfChecker `1.0.0-rc1` used the frozen `LiLim/perfcheck` environment and prepared MetaStrategist plans before the measured calls. Its profile rows are sampling snapshots, not CPU utilization. Counts can grow with thread width and must not be read as absolute work. The following profiles cover learned-ICN CBLS, balanced MetaStrategist and search-heavy MetaStrategist.\n")
    for threads in (8, 16), method in ("cbls_icn", "mixed_balanced", "mixed_ls_heavy")
        profile = PROFILE_SUMMARY[string(threads)][method]
        println(io, "### ", LABELS[method], " — ", threads, " threads\n")
        for backend in sort(collect(keys(profile["collectors"])))
            entry = profile["collectors"][backend]
            println(io, "- `", backend, "`: ", entry["samples"], " samples across ", entry["sampled_sites"], " sampled source rows.")
            isempty(entry["top_sites"]) || println(io, "  Leading sampled sites: ", join((string(site["site"], " (", site["samples"], ")") for site in entry["top_sites"]), "; "), ".")
        end
    end
    println(io, "\nPerfChecker emitted non-fatal DWARF address-range warnings but completed and saved both collectors in all six selected runs. Allocation-site profiling is omitted because PerfChecker did not find target source sites in the earlier attempt; no allocation-byte conclusion is made here. The standalone first 8-thread ICN capture without an explicitly prepared MetaStrategist plan is retained only as an uncommitted diagnostic and is excluded from this comparison.\n")
    println(io, "## Files\n\nThe source TOML files are the paired campaign trials in the two campaign directories and the six `perfchecker-*-20261005.toml` captures in `LiLim/results/`. `summary.toml` records campaign fingerprints, thread widths, aggregate GC measurements and PerfChecker source-site summaries.")
end

println("Wrote resource-profile report and English plots to ", OUT)
