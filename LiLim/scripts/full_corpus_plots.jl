using TOML, Statistics, CairoMakie, Random

length(ARGS) in (2, 3) || error("usage: full_corpus_plots.jl SUMMARY.toml OUTPUT_DIR [exact|xkcd]")
const SUMMARY = TOML.parsefile(abspath(ARGS[1]))
const OUT = abspath(ARGS[2])
const STYLE = length(ARGS) == 3 ? ARGS[3] : "exact"
STYLE in ("exact", "xkcd") || error("style must be exact or xkcd")
const METHODS = SUMMARY["methods"]
const LABELS = Dict(
    "cbls_naive"=>"CBLS naive", "cbls_icn"=>"CBLS learned ICN",
    "cbls_icn_fused_scalar"=>"ICN fused scalar", "cbls_icn_fused_all"=>"ICN fused all",
    "cbls_direct"=>"CBLS direct error",
    "hybrid_specialized_icn"=>"Hybrid ICN specialized", "hybrid_bridged_icn"=>"Hybrid ICN + XCSP3",
    "highs_native"=>"HiGHS native", "highs_portfolio"=>"HiGHS portfolio",
    "cbls_mix_strategy"=>"CBLS strategy mix", "mixed_balanced"=>"MetaStrategist equal mix",
    "mixed_ls_heavy"=>"MetaStrategist search-heavy", "hexaly_native"=>"Hexaly native")
const COLORS = [:dodgerblue3, :darkorange2, :seagreen3, :purple3, :firebrick3,
    :gray35, :goldenrod2, :teal, :deeppink3, :sienna3]
const MARKERS = [:circle, :rect, :utriangle, :diamond, :dtriangle, :cross, :star5, :hexagon, :pentagon, :xcross]
label(method) = get(LABELS, method, replace(method, '_' => ' '))

if STYLE == "xkcd"
    @eval using XKCDMakie
    Random.seed!(41)
    set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans", fontsize=16, linewidth=2.5,
        Axis=(xgridvisible=false, ygridcolor=(:gray, .18), titlesize=20)))
end

function savefig(fig, name)
    mkpath(OUT)
    suffix = STYLE == "xkcd" ? "-xkcd" : ""
    for extension in ("png", "pdf")
        save(joinpath(OUT, name * suffix * "." * extension), fig; px_per_unit=1.5)
    end
end

function attainment_plot()
    budget = SUMMARY["budget_seconds"]
    grid = collect(range(0, budget; length=121))
    fig = Figure(size=(1450, 900))
    Label(fig[0, 1], "Time to the SINTEF Best-Known Target", fontsize=27)
    Label(fig[1, 1], "Cumulative share of scheduled runs that reached both the fleet and distance reference", fontsize=16)
    ax = Axis(fig[2, 1]; xlabel="Elapsed wall time (seconds)", ylabel="Runs reaching SINTEF BKS (%)",
        xtickformat=values -> string.(round.(values; digits=1)))
    for (index, method) in enumerate(METHODS)
        color = method == "hexaly_native" ? :black : COLORS[mod1(index, length(COLORS))]
        rows = filter(row->row["method"] == method, SUMMARY["instance_results"])
        times = reduce(vcat, (row["bks_times_seconds"] for row in rows); init=Float64[])
        scheduled = sum(row["planned_runs"] for row in rows)
        y = [scheduled == 0 ? 0.0 : 100 * count(time->time <= t, times) / scheduled for t in grid]
        lines!(ax, grid, y; color, linewidth=2.6,
            linestyle=method == "hexaly_native" ? :dash : :solid, label=label(method))
    end
    hlines!(ax, [100.0]; color=:black, linestyle=:dot, linewidth=2.0, label="100% target attainment")
    xlims!(ax, 0, budget)
    ylims!(ax, 0, 102)
    axislegend(ax; position=:rb, framevisible=false, labelsize=13, nbanks=2)
    Label(fig[3, 1], "Budget: $(budget) s · $(SUMMARY["threads"]) workers · $(SUMMARY["seed_count"]) seeds · $(SUMMARY["instance_count"]) official instances · BKS distance rounded to $(SUMMARY["bks_distance_digits"]) decimals · misses censored at the budget", fontsize=14)
    savefig(fig, "lilim-bks-attainment")
end

function quality_by_size()
    sizes = sort!(unique([row["size"] for row in SUMMARY["size_summary"]]))
    instance_mode = length(sizes) == 1
    rows = instance_mode ? SUMMARY["instance_results"] : SUMMARY["size_summary"]
    categories = instance_mode ? sort!(unique([row["instance"] for row in rows])) : sizes
    xvalue(row) = findfirst(==(instance_mode ? row["instance"] : row["size"]), categories)
    xoffset(index) = (index - (length(METHODS) + 1) / 2) * 0.03
    fig = Figure(size=(1950, 1750))
    Label(fig[0, 1:2], "Best, Mean and Median Search Quality Against SINTEF References", fontsize=27)
    titles = ("Best validated run across seeds", "Mean fleet across feasible seeds",
        "Fleet from one actual median-ranked run", "Median-ranked distance when fleet matches BKS")
    axes = [Axis(fig[row, 1]; xlabel=row == 4 ? (instance_mode ? "Official 100-request instance" : "Requests per instance") : "",
        ylabel=row < 4 ? "Vehicle gap from SINTEF BKS" : "Distance gap at the BKS fleet (%)",
        title=titles[row]) for row in 1:4]
    for (index, ax) in enumerate(axes)
        hlines!(ax, [0.0]; color=:black, linestyle=:dot, linewidth=2.0)
        ax.xticks = (1:length(categories), string.(categories))
        xlims!(ax, 0.5, length(categories) + 0.5)
    end
    for (index, method) in enumerate(METHODS)
        color = method == "hexaly_native" ? :black : COLORS[mod1(index, length(COLORS))]
        marker = method == "hexaly_native" ? :star5 : MARKERS[mod1(index, length(MARKERS))]
        linestyle = method == "hexaly_native" ? :dash : :solid
        selected = sort(filter(row->row["method"] == method, rows); by=row->instance_mode ? row["instance"] : row["size"])
        xs = [xvalue(row) + xoffset(index) for row in selected]
        best = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["best_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_best_fleet_gap"]) for row in selected]
        average = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["mean_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_run_fleet_gap"]) for row in selected]
        median_run = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["median_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_median_run_fleet_gap"]) for row in selected]
        if instance_mode
            distrows = filter(row->row["median_vehicles"] == row["bks_vehicles"] && row["median_distance"] >= 0, selected)
            distx = [xvalue(row) + xoffset(index) for row in distrows]
            dist = [100 * (row["median_distance"] / row["bks_distance"] - 1) for row in distrows]
        else
            distrows = filter(row->row["distance_cells"] > 0, selected)
            distx = [xvalue(row) + xoffset(index) for row in distrows]
            dist = [row["mean_distance_gap_at_bks_fleet_percent"] for row in distrows]
        end
        scatterlines!(axes[1], xs, best; color, marker, markersize=10,
            linewidth=2.2, linestyle, label=label(method))
        scatterlines!(axes[2], xs, average; color, marker, markersize=10,
            linewidth=2.2, linestyle, label=label(method))
        scatterlines!(axes[3], xs, median_run; color, marker, markersize=10,
            linewidth=2.2, linestyle, label=label(method))
        isempty(dist) || scatterlines!(axes[4], distx, dist; color, marker,
            markersize=10, linewidth=2.2, label=label(method))
    end
    Legend(fig[2:4, 2], axes[1]; framevisible=false, labelsize=15)
    Label(fig[5, 1:2], "Negative fleet gaps beat the reference. The median panel reports one real run selected by lexicographic result order. Distance gaps are shown only when that run matches the BKS fleet; dotted zero lines mark the SINTEF reference.", fontsize=14)
    savefig(fig, "lilim-best-mean-median-vs-bks")
end

function success_by_size()
    sizes = sort!(unique([row["size"] for row in SUMMARY["size_summary"]]))
    instance_mode = length(sizes) == 1
    rows = instance_mode ? SUMMARY["instance_results"] : SUMMARY["size_summary"]
    categories = instance_mode ? sort!(unique([row["instance"] for row in rows])) : sizes
    xvalue(row) = findfirst(==(instance_mode ? row["instance"] : row["size"]), categories)
    xoffset(index) = (index - (length(METHODS) + 1) / 2) * 0.03
    fig = Figure(size=(1950, 900))
    Label(fig[0, 1:2], instance_mode ? "Best-Known Solution Success by Instance" : "Best-Known Solution Success by Problem Size", fontsize=27)
    ax = Axis(fig[1, 1]; xlabel=instance_mode ? "Official 100-request instance" : "Requests per instance", ylabel="Runs reaching SINTEF BKS (%)")
    ax.xticks = (1:length(categories), string.(categories))
    xlims!(ax, 0.5, length(categories) + 0.5)
    for (index, method) in enumerate(METHODS)
        color = method == "hexaly_native" ? :black : COLORS[mod1(index, length(COLORS))]
        marker = method == "hexaly_native" ? :star5 : MARKERS[mod1(index, length(MARKERS))]
        selected = sort(filter(row->row["method"] == method, rows); by=row->instance_mode ? row["instance"] : row["size"])
        xs = [xvalue(row) + xoffset(index) for row in selected]
        ys = [100 * row["bks_hit_rate"] for row in selected]
        scatterlines!(ax, xs, ys; color, marker, markersize=10,
            linewidth=2.4, linestyle=method == "hexaly_native" ? :dash : :solid,
            label=label(method))
    end
    hlines!(ax, [100.0]; color=:black, linestyle=:dot, linewidth=2.0)
    ylims!(ax, 0, 102)
    Legend(fig[1, 2], ax; framevisible=false, labelsize=15)
    Label(fig[2, 1:2], "Rates use every scheduled seed; incomplete runs remain in the denominator.", fontsize=14)
    savefig(fig, "lilim-bks-success-by-size")
end

function cpu_plot()
    methods = SUMMARY["method_summary"]
    xs = collect(1:length(methods))
    labels = [label(row["method"]) for row in methods]
    values = [row["mean_active_cpus"] < 0 ? NaN : row["mean_active_cpus"] for row in methods]
    fig = Figure(size=(1550, 760))
    Label(fig[0, 1], "Effective CPU Use by Solver Profile", fontsize=27)
    ax = Axis(fig[1, 1]; xlabel="Solver profile", ylabel="Mean active CPUs", xticks=(xs, labels))
    ax.xticklabelrotation = π / 5
    barplot!(ax, xs, values; color=[row["method"] == "hexaly_native" ? :black : COLORS[mod1(i,length(COLORS))]
        for (i,row) in enumerate(methods)])
    hlines!(ax, [SUMMARY["threads"]]; color=:black, linestyle=:dot, linewidth=2.0,
        label="Allocated worker count: $(SUMMARY["threads"])" )
    axislegend(ax; position=:rt, framevisible=false)
    finite_values = filter(isfinite, values)
    ylims!(ax, 0, max(SUMMARY["threads"] + 1, maximum(finite_values; init=0.0) + 1))
    Label(fig[2, 1], "CPU time includes initialization, model setup, search and validation inside each trial's shared budget.", fontsize=14)
    savefig(fig, "lilim-cpu-use")
end

attainment_plot()
quality_by_size()
success_by_size()
cpu_plot()
println("Saved English benchmark plots to ", OUT, " (", STYLE, " style)")
