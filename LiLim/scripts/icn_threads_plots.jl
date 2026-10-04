# Export exact scientific figures first, then a separate XKCD illustration.
using TOML, Statistics, CairoMakie, Random
length(ARGS)==2 || error("usage: icn_threads_plots.jl summary.toml output-directory")
const REPORT=TOML.parsefile(abspath(ARGS[1]))
const OUT=abspath(ARGS[2]);mkpath(OUT)
const RECORDS=REPORT["records"]
const INSTANCES=REPORT["metadata"]["config"]["instances"]
const WIDTHS=REPORT["metadata"]["config"]["thread_counts"]
const METHODS=vcat(REPORT["metadata"]["config"]["methods"],REPORT["metadata"]["config"]["portfolio_methods"])
const LABELS=Dict("cbls_naive"=>"CBLS naïf", "cbls_icn"=>"CBLS ICN",
    "cbls_direct"=>"CBLS direct", "hybrid_specialized_icn"=>"Hybride spécialisé ICN",
    "hybrid_bridged_icn"=>"Hybride bridgé ICN", "highs_native"=>"HiGHS natif",
    "highs_portfolio"=>"HiGHS multi-départ", "mixed_balanced"=>"Mix équilibré",
    "mixed_ls_heavy"=>"Mix priorité CBLS")
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
        save(joinpath(OUT,name*"."*extension),fig;px_per_unit=1.5)
    end
end
set_theme!(Theme(font="DejaVu Sans",fontsize=15,linewidth=2.2,
    Axis=(xgridvisible=false,ygridcolor=(:gray,0.15),titlesize=19,)))
quality=Figure(size=(1500,1000))
Label(quality[0,1:3],"Li-Lim : qualité en 10 secondes",fontsize=28)
Label(quality[-1,1:3],"3 graines · corpus diagnostic déjà exposé · même budget mural",fontsize=16)
legend_lines=Any[];legend_labels=String[]
for (col,id) in enumerate(INSTANCES)
    fleet=Axis(quality[1,col];title=uppercase(id),xscale=log2,ylabel=col==1 ? "Véhicules" : "")
    dist=Axis(quality[2,col];xscale=log2,xlabel="Threads alloués",ylabel=col==1 ? "Distance" : "")
    configure_axis(fleet);configure_axis(dist)
    fleets=[r["vehicles"] for r in RECORDS if r["instance"]==id]
    fleet.yticks=collect(minimum(fleets):maximum(fleets))
    ylims!(fleet,minimum(fleets)-0.5,maximum(fleets)+0.5)
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
Label(quality[3,1:3],"Médiane lexicographique (flotte, puis distance). Distance à lire avec la flotte. Bandes : min–max de flotte sur 3 graines.",fontsize=14)
Legend(quality[4,1:3],legend_lines,legend_labels;orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
exportfigure(quality,"icn-threads-quality")

utilization=Figure(size=(1500,650))
Label(utilization[0,1:3],"Threads alloués et CPU réellement consommé",fontsize=26)
for (col,id) in enumerate(INSTANCES)
    ax=Axis(utilization[1,col];title=uppercase(id),xscale=log2,xlabel="Threads alloués",ylabel=col==1 ? "Nombre moyen de CPU actifs" : "")
    configure_axis(ax)
    lines!(ax,WIDTHS,WIDTHS;color=(:gray50,0.7),linestyle=:dot,linewidth=1.5)
    for (j,method) in enumerate(METHODS)
        xs=[width for width in WIDTHS if !isempty(subset(id,method,width))]
        ys=[median(r["mean_active_cpus"] for r in subset(id,method,width)) for width in xs]
        scatterlines!(ax,xs,ys;color=COLORS[j],markersize=8,linestyle=j>=8 ? :dash : :solid)
    end
    ylims!(ax,0,17)
end
Label(utilization[2,1:3],"Temps CPU total / temps mural, médiane de 3 graines. Pointillés gris : utilisation idéale. 16 = 8 P + 4 E + 4 SMT.",fontsize=14)
Legend(utilization[3,1:3],legend_lines,legend_labels;orientation=:horizontal,nbanks=3,tellwidth=false,framevisible=false)
exportfigure(utilization,"icn-threads-cpu")

throughput=Figure(size=(1500,650))
Label(throughput[0,1:3],"Débit de recherche : effet du nombre de threads",fontsize=26)
throughput_lines=Any[];throughput_labels=String[]
for (col,id) in enumerate(INSTANCES)
    ax=Axis(throughput[1,col];title=uppercase(id),xscale=log2,xlabel="Threads alloués",ylabel=col==1 ? "Débit relatif à 1 thread" : "")
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
Label(throughput[2,1:3],"Candidats de réinsertion examinés par seconde, médiane de 3 graines. Un débit supérieur n'est pas une preuve de meilleure qualité.",fontsize=14)
Legend(throughput[3,1:3],throughput_lines,throughput_labels;orientation=:horizontal,nbanks=2,tellwidth=false,framevisible=false)
exportfigure(throughput,"icn-threads-throughput")

# XKCDMakie changes Cairo rendering globally. Import after exact PNG/PDF export.
using XKCDMakie
Random.seed!(20261004)
set_theme!(XKCDMakie.theme_xkcd())
fun=Figure(size=(1100,760))
Label(fun[0,1],"J'ai demandé 16 threads...",fontsize=27)
ax=Axis(fun[1,1];title="CPU réellement occupé — LR101",xlabel="Threads alloués",ylabel="CPU actifs en moyenne",xscale=log2)
configure_axis(ax);ylims!(ax,0,17)
lines!(ax,WIDTHS,WIDTHS;color=:gray50,linestyle=:dash,label="Tous au travail")
for method in ("cbls_icn","hybrid_specialized_icn","highs_native","mixed_balanced")
    j=findfirst(==(method),METHODS)
    xs=[width for width in WIDTHS if !isempty(subset("lr101",method,width))]
    ys=[median(r["mean_active_cpus"] for r in subset("lr101",method,width)) for width in xs]
    scatterlines!(ax,xs,ys;color=COLORS[j],markersize=11,label=LABELS[method])
end
Legend(fun[2,1],ax;orientation=:horizontal,nbanks=2,tellwidth=false,framevisible=false)
Label(fun[3,1],"Illustration XKCD. Données réelles ; tracés volontairement irréguliers.\nLes figures scientifiques exactes sont fournies séparément.",fontsize=14)
exportfigure(fun,"icn-threads-xkcd")
println("Exported four PNG/PDF figures to ",OUT)
