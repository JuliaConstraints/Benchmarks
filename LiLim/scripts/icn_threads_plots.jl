# Export exact scientific figures first, then a separate XKCD illustration.
using TOML, Statistics, CairoMakie, Random
length(ARGS) in (2,3) || error("usage: icn_threads_plots.jl summary.toml output-directory [success-only|success-xkcd]")
const REPORT=TOML.parsefile(abspath(ARGS[1]))
const OUT=abspath(ARGS[2]);mkpath(OUT)
const RECORDS=REPORT["records"]
const INSTANCES=REPORT["metadata"]["config"]["instances"]
const WIDTHS=REPORT["metadata"]["config"]["thread_counts"]
const TARGETS=TOML.parsefile(joinpath(@__DIR__,"..","config","diagnostic-targets.toml"))
const SUFFIX=length(ARGS)==3 && ARGS[3]=="success-xkcd" ? "-xkcd" : ""
const METHODS=vcat(REPORT["metadata"]["config"]["methods"],REPORT["metadata"]["config"]["portfolio_methods"])
const LABELS=Dict("cbls_naive"=>"CBLS naive", "cbls_icn"=>"CBLS ICN",
    "cbls_direct"=>"CBLS direct", "hybrid_specialized_icn"=>"Specialized ICN hybrid",
    "hybrid_bridged_icn"=>"Bridged ICN hybrid", "highs_native"=>"Native HiGHS",
    "highs_portfolio"=>"HiGHS multistart", "mixed_balanced"=>"Balanced mix",
    "mixed_ls_heavy"=>"CBLS-heavy mix")
const COLORS=[:gray45,:dodgerblue3,:darkorange2,:seagreen3,:purple3,
    :firebrick3,:sienna3,:deeppink3,:black]
subset(id,method,width)=filter(r->r["instance"]==id && r["method"]==method && r["threads_requested"]==width,RECORDS)
lexmiddle(rs)=sort(rs;by=r->(r["vehicles"],r["distance"]))[cld(length(rs),2)]
work(r)=sum(get(w["trace"],"pair_candidates",0) for w in r["workers"])/r["budget_seconds"]
function configure_axis(ax)
    xlims!(ax,0.9,17.5)
    ax.xticks=(Float64.(WIDTHS),string.(WIDTHS))
    ax.xgridvisible=false
end
function exportfigure(fig,name)
    for extension in ("png","pdf")
        save(joinpath(OUT,name*SUFFIX*"."*extension),fig;px_per_unit=1.5)
    end
end
set_theme!(Theme(font="DejaVu Sans",fontsize=15,linewidth=2.2,
    Axis=(xgridvisible=false,ygridcolor=(:gray,0.15),titlesize=19,)))
function successplots()
    targets=TARGETS
    tol=targets["tie_tolerance"]
    hit(r,id)=r["vehicles"]<targets[id]["vehicles"] ||
        (r["vehicles"]==targets[id]["vehicles"] && r["distance"]<=targets[id]["distance"]+tol)
    improved(r)=r["vehicles"]<r["initial_vehicles"] ||
        (r["vehicles"]==r["initial_vehicles"] && r["distance"]<r["initial_distance"]-tol)
    legends=Any[];labels=String[]
    rates=Figure(size=(1500,1000))
    Label(rates[0,1:3],"10-second success: reference reached and starting solution improved",fontsize=26)
    for (col,id) in enumerate(INSTANCES)
        reference=targets[id]
        ax=Axis(rates[1,col];title=uppercase(id)*" — "*string(reference["vehicles"])*" / "*string(reference["distance"]),
            xscale=log2,ylabel=col==1 ? "SINTEF reference reached (%)" : "",yticks=0:25:100)
        gain=Axis(rates[2,col];xscale=log2,xlabel="Allocated threads",ylabel=col==1 ? "Starting solution improved (%)" : "",yticks=0:25:100)
        configure_axis(ax);configure_axis(gain);ylims!(ax,-5,105);ylims!(gain,-5,105)
        for (j,method) in enumerate(METHODS)
            xs=[w for w in WIDTHS if !isempty(subset(id,method,w))]
            success=[100*mean(hit(r,id) for r in subset(id,method,w)) for w in xs]
            progress=[100*mean(improved(r) for r in subset(id,method,w)) for w in xs]
            line=scatterlines!(ax,xs,success;color=COLORS[j],markersize=9,linestyle=j>=8 ? :dash : :solid)
            scatterlines!(gain,xs,progress;color=COLORS[j],markersize=9,linestyle=j>=8 ? :dash : :solid)
            if col==1;push!(legends,line);push!(labels,LABELS[method]);end
        end
    end
    Label(rates[3,1:3],"3 seeds: 33% = 1/3. LC101 starts at its reference. No LRC101 run reaches 14 vehicles. Diagnostic targets after the campaign.",fontsize=14)
    Legend(rates[4,1:3],legends,labels;orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
    exportfigure(rates,"icn-threads-success")

    width=8;grid=collect(0.:0.05:10.)
    available(r,t)=begin
        events=filter(e->e["seconds"]<=t,r["trajectory"])
        isempty(events) ? nothing : last(events)
    end
    anytime=Figure(size=(1500,1000))
    Label(anytime[0,1:3],"Solution progress during search — 8 threads",fontsize=26)
    cdf=Figure(size=(1500,650))
    Label(cdf[0,1:3],"Time to reach the SINTEF reference — 8 threads",fontsize=26)
    for (col,id) in enumerate(INSTANCES)
        fleet=Axis(anytime[1,col];title=uppercase(id),ylabel=col==1 ? "Vehicles" : "")
        distance=Axis(anytime[2,col];xlabel="Elapsed time (s)",ylabel=col==1 ? "Distance" : "")
        target=Axis(cdf[1,col];title=uppercase(id),xlabel="Elapsed time (s)",ylabel=col==1 ? "Reference reached (%)" : "",yticks=0:25:100)
        xlims!(fleet,0,10);xlims!(distance,0,10);xlims!(target,0,10);ylims!(target,-5,105)
        fleets=[r["vehicles"] for r in RECORDS if r["instance"]==id && r["threads_requested"]==width]
        initial=[r["initial_vehicles"] for r in RECORDS if r["instance"]==id && r["threads_requested"]==width]
        lower=min(minimum(fleets),targets[id]["vehicles"])
        fleet.yticks=collect(lower:maximum(initial));ylims!(fleet,lower-0.5,maximum(initial)+0.5)
        hlines!(fleet,[targets[id]["vehicles"]];color=:gray30,linestyle=:dot,linewidth=2)
        hlines!(distance,[targets[id]["distance"]];color=:gray30,linestyle=:dot,linewidth=2)
        for (j,method) in enumerate(METHODS)
            rs=subset(id,method,width)
            points=[begin
                events=[available(r,t) for r in rs]
                any(isnothing,events) ? nothing : sort(events;by=e->(e["vehicles"],e["distance"]))[2]
            end for t in grid]
            ys=[p===nothing ? NaN : Float64(p["vehicles"]) for p in points]
            ds=[p===nothing ? NaN : Float64(p["distance"]) for p in points]
            style=j>=8 ? :dash : :solid
            stairs!(fleet,grid,ys;step=:post,color=COLORS[j],linestyle=style)
            stairs!(distance,grid,ds;step=:post,color=COLORS[j],linestyle=style)
            fractions=[100*mean(any(e->e["seconds"]<=t && hit(e,id),r["trajectory"]) for r in rs) for t in grid]
            stairs!(target,grid,fractions;step=:post,color=COLORS[j],linestyle=style)
        end
    end
    Label(anytime[3,1:3],"Lexicographic median over 3 seeds. Gray dotted lines: SINTEF reference. Frontier reconstructed from private discoveries; final merge across workers.",fontsize=14)
    reference=LineElement(color=:gray30,linestyle=:dot,linewidth=2)
    Legend(anytime[4,1:3],vcat(legends,[reference]),vcat(labels,["SINTEF reference"]);orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
    Label(cdf[2,1:3],"Published rounded reference, fleet then distance. Failures remain at 0%. Descriptive curves over 3 seeds; no statistical extrapolation.",fontsize=14)
    Legend(cdf[3,1:3],legends,labels;orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
    exportfigure(anytime,"icn-threads-anytime")
    exportfigure(cdf,"icn-threads-time-to-target")
end
if length(ARGS)==3
    ARGS[3] in ("success-only","success-xkcd") || error("unknown plot mode")
    if ARGS[3]=="success-xkcd"
        @eval using XKCDMakie
        Random.seed!(20261004)
        set_theme!(XKCDMakie.theme_xkcd())
    end
    Base.invokelatest(successplots)
    println("Exported success, anytime and target-time PNG/PDF figures to ",OUT)
    exit()
end
quality=Figure(size=(1500,1000))
Label(quality[0,1:3],"Li-Lim: solution quality after 10 seconds",fontsize=28)
Label(quality[-1,1:3],"3 seeds · exposed diagnostic set · same wall-clock budget",fontsize=16)
legend_lines=Any[];legend_labels=String[]
for (col,id) in enumerate(INSTANCES)
    fleet=Axis(quality[1,col];title=uppercase(id),xscale=log2,ylabel=col==1 ? "Vehicles" : "")
    dist=Axis(quality[2,col];xscale=log2,xlabel="Allocated threads",ylabel=col==1 ? "Distance" : "")
    configure_axis(fleet);configure_axis(dist)
    fleets=[r["vehicles"] for r in RECORDS if r["instance"]==id]
    fleet.yticks=collect(minimum(fleets):maximum(fleets))
    reference=TARGETS[id]
    fleet.yticks=collect(min(minimum(fleets),reference["vehicles"]):maximum(fleets))
    ylims!(fleet,min(minimum(fleets),reference["vehicles"])-0.5,maximum(fleets)+0.5)
    refline=hlines!(fleet,[reference["vehicles"]];color=:gray30,linestyle=:dot,linewidth=2)
    hlines!(dist,[reference["distance"]];color=:gray30,linestyle=:dot,linewidth=2)
    for (j,method) in enumerate(METHODS)
        xs=[width for width in WIDTHS if !isempty(subset(id,method,width))]
        points=[lexmiddle(subset(id,method,width)) for width in xs]
        vehicles=Float64[r["vehicles"] for r in points];distances=Float64[r["distance"] for r in points]
        lows=[minimum(r["vehicles"] for r in subset(id,method,width)) for width in xs]
        highs=[maximum(r["vehicles"] for r in subset(id,method,width)) for width in xs]
        band!(fleet,xs,lows,highs;color=(COLORS[j],0.07))
        line=scatterlines!(fleet,xs,vehicles;color=COLORS[j],markersize=8,linestyle=j>=8 ? :dash : :solid)
        scatterlines!(dist,xs,distances;color=COLORS[j],markersize=8,linestyle=j>=8 ? :dash : :solid)
        if col==1
            push!(legend_lines,line);push!(legend_labels,LABELS[method])
        end
    end
end
Label(quality[3,1:3],"Lexicographic median (fleet, then distance). Gray dotted lines: SINTEF reference. Read distance together with fleet size. Bands show min–max over 3 seeds.",fontsize=14)
Legend(quality[4,1:3],vcat(legend_lines,[LineElement(color=:gray30,linestyle=:dot,linewidth=2)]),
    vcat(legend_labels,["SINTEF reference"]);orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
exportfigure(quality,"icn-threads-quality")

utilization=Figure(size=(1500,650))
Label(utilization[0,1:3],"Allocated threads and actual CPU use",fontsize=26)
for (col,id) in enumerate(INSTANCES)
    ax=Axis(utilization[1,col];title=uppercase(id),xscale=log2,xlabel="Allocated threads",ylabel=col==1 ? "Mean active CPUs" : "")
    configure_axis(ax)
    lines!(ax,WIDTHS,WIDTHS;color=(:gray50,0.7),linestyle=:dot,linewidth=1.5)
    for (j,method) in enumerate(METHODS)
        xs=[width for width in WIDTHS if !isempty(subset(id,method,width))]
        ys=[median(r["mean_active_cpus"] for r in subset(id,method,width)) for width in xs]
        scatterlines!(ax,xs,ys;color=COLORS[j],markersize=8,linestyle=j>=8 ? :dash : :solid)
    end
    ylims!(ax,0,17)
end
Label(utilization[2,1:3],"Total CPU time / wall time, median over 3 seeds. Gray dotted line: ideal utilization. 16 = 8 P-cores + 4 E-cores + 4 SMT lanes.",fontsize=14)
Legend(utilization[3,1:3],legend_lines,legend_labels;orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
exportfigure(utilization,"icn-threads-cpu")

throughput=Figure(size=(1500,650))
Label(throughput[0,1:3],"Search throughput by thread count",fontsize=26)
throughput_lines=Any[];throughput_labels=String[]
for (col,id) in enumerate(INSTANCES)
    ax=Axis(throughput[1,col];title=uppercase(id),xscale=log2,xlabel="Allocated threads",ylabel=col==1 ? "Throughput relative to 1 thread" : "")
    configure_axis(ax)
    lines!(ax,WIDTHS,WIDTHS;color=(:gray50,0.7),linestyle=:dot,linewidth=1.5)
    for (j,method) in enumerate(METHODS[1:5])
        baseline=median(work(r) for r in subset(id,method,1))
        baseline>0 || error("zero throughput baseline")
        ys=[median(work(r) for r in subset(id,method,width))/baseline for width in WIDTHS]
        line=scatterlines!(ax,WIDTHS,ys;color=COLORS[j],markersize=8)
        if col==1;push!(throughput_lines,line);push!(throughput_labels,LABELS[method]);end
    end
end
Label(throughput[2,1:3],"Reinsertion candidates examined per second, median over 3 seeds. Higher throughput does not prove better solution quality.",fontsize=14)
Legend(throughput[3,1:3],throughput_lines,throughput_labels;orientation=:horizontal,nbanks=2,tellwidth=false,framevisible=false)
exportfigure(throughput,"icn-threads-throughput")
successplots()

# XKCDMakie changes Cairo rendering globally. Import after exact PNG/PDF export.
using XKCDMakie
Random.seed!(20261004)
set_theme!(XKCDMakie.theme_xkcd())
fun=Figure(size=(1100,760))
Label(fun[0,1],"I asked for 16 threads...",fontsize=27)
ax=Axis(fun[1,1];title="Actual CPU utilization — LR101",xlabel="Allocated threads",ylabel="Mean active CPUs",xscale=log2)
configure_axis(ax);ylims!(ax,0,17)
lines!(ax,WIDTHS,WIDTHS;color=:gray50,linestyle=:dash,label="Tous au travail")
for method in ("cbls_icn","hybrid_specialized_icn","highs_native","mixed_balanced")
    j=findfirst(==(method),METHODS)
    xs=[width for width in WIDTHS if !isempty(subset("lr101",method,width))]
    ys=[median(r["mean_active_cpus"] for r in subset("lr101",method,width)) for width in xs]
    scatterlines!(ax,xs,ys;color=COLORS[j],markersize=11,label=LABELS[method])
end
Legend(fun[2,1],ax;orientation=:horizontal,nbanks=2,tellwidth=false,framevisible=false)
Label(fun[3,1],"XKCD illustration. Real data; lines are intentionally irregular.\nExact scientific figures are provided separately.",fontsize=14)
exportfigure(fun,"icn-threads-xkcd")
println("Exported seven PNG/PDF figures to ",OUT)
