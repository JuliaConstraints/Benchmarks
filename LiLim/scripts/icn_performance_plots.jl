# Performance diagnostics stay separate from the original 369 quality trials.
using TOML, Statistics, CairoMakie, Random
length(ARGS)==2 && ARGS[2] in ("exact","xkcd") || error("usage: icn_performance_plots.jl output-directory exact|xkcd")
const ROOT=normpath(joinpath(@__DIR__,".."))
const OUT=abspath(ARGS[1]);mkpath(OUT)
const WIDTHS=[1,2,4,8,16]
hot(path)=filter(e->startswith(e["phase"],"hot"),TOML.parsefile(path)["events"])
const FINALS=[hot(joinpath(ROOT,"results","throughput-final-$(n)t-gc1-20261004.toml")) for n in WIDTHS]
append!(FINALS[3],hot(joinpath(ROOT,"results","throughput-final-repeat-4t-gc1-20261004.toml")))
const BEFORE=hot(joinpath(ROOT,"results","throughput-16t-gc1-20261004.toml"))
const FIRST=hot(joinpath(ROOT,"results","throughput-workspace-16t-gc1-20261004.toml"))
const STAGES=[BEFORE,FIRST,last(FINALS)]
const HOT_GC=hot(joinpath(ROOT,"results","throughput-hot-gc-16t-20261004.toml"))
const COLORS=[:firebrick3,:darkorange2,:seagreen3]
if ARGS[2]=="xkcd"
    @eval using XKCDMakie
    Random.seed!(41)
    set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans",fontsize=16,linewidth=2.5,
        Axis=(xgridvisible=false,ygridcolor=(:gray,0.15),titlesize=20)))
end
function render()
    fig=Figure(size=(1400,1020))
    Label(fig[0,1:2],"CBLS + ICN : allocations, GC et travail utile",fontsize=27)
    cpu=Axis(fig[1,1];title="Occupation des workers après correction",xscale=log2,
        xlabel="Threads",ylabel="Temps CPU / temps mural par worker (%)",xticks=WIDTHS,yticks=0:25:100)
    for (i,n) in enumerate(WIDTHS),event in FINALS[i]
        scatter!(cpu,fill(n,length(event["workers"])),100 .* [w["cpu_fraction"] for w in event["workers"]];
            color=(:seagreen3,0.3),markersize=7)
    end
    scatterlines!(cpu,WIDTHS,[100*median(mean(w["cpu_fraction"] for w in e["workers"]) for e in rows) for rows in FINALS];color=:seagreen3,markersize=12)
    hlines!(cpu,[100];color=:gray40,linestyle=:dash)
    xlims!(cpu,0.8,20);ylims!(cpu,0,108)
    work=Axis(fig[1,2];title="Débit après correction",xscale=log2,
        xlabel="Threads",ylabel="Millions de candidats / seconde",xticks=WIDTHS)
    for (i,n) in enumerate(WIDTHS)
        scatter!(work,fill(n,length(FINALS[i])),[e["candidates_per_second"]/1e6 for e in FINALS[i]];color=(:seagreen3,0.3),markersize=7)
    end
    scatterlines!(work,WIDTHS,[median(e["candidates_per_second"] for e in rows)/1e6 for rows in FINALS];color=:seagreen3,markersize=12)
    before=scatter!(work,[16],[median(e["candidates_per_second"] for e in BEFORE)/1e6];color=COLORS[1],marker=:diamond,markersize=15)
    first=scatter!(work,[16],[median(e["candidates_per_second"] for e in FIRST)/1e6];color=COLORS[2],marker=:rect,markersize=12)
    axislegend(work,[before,first],["Avant","Buffers seuls"];position=:lt,framevisible=false)
    xlims!(work,0.8,20);ylims!(work,0,nothing)
    gc=Axis(fig[2,1];title="16 threads : GC de l'appel complet",ylabel="Temps GC / durée totale (%)",
        xticks=(1:3,["Avant","Buffers ICN","+ noyau et routes"]),yticks=0:10:70)
    memory=Axis(fig[2,2];title="16 threads : allocations sur 5 secondes",ylabel="Go alloués par appel",
        xticks=(1:3,["Avant","Buffers ICN","+ noyau et routes"]))
    barplot!(gc,1:3,[100*median(e["gc_seconds"]/e["seconds"] for e in rows) for rows in STAGES];color=COLORS)
    barplot!(memory,1:3,[median(e["allocated_bytes"] for e in rows)/1e9 for rows in STAGES];color=COLORS)
    ylims!(gc,0,70);ylims!(memory,0,nothing)
    hotgc=round(median(e["search_gc_seconds"] for e in HOT_GC);digits=4)
    Label(fig[3,1:2],"LC101 · mêmes ICN et voisinages · 3 graines × 5 s, 2 lots à 4 threads · Julia -O1 · GC = 1 thread\nGC de l'appel complet : inclut la collecte forcée avant la recherche. Mesure séparée en recherche : $(hotgc) s.\n16 threads : 8 cœurs P + 4 cœurs E + 4 voies SMT. Débit ≠ amélioration de la solution.",fontsize=16)
    if ARGS[2]=="xkcd"
        Label(fig[4,1:2],"Illustration XKCD : tracés volontairement irréguliers. Coordonnées exactes dans la version sobre.",fontsize=14)
    end
    suffix=ARGS[2]=="xkcd" ? "-xkcd" : ""
    for extension in ("png","pdf")
        save(joinpath(OUT,"icn-performance"*suffix*"."*extension),fig;px_per_unit=1.5)
    end
end
Base.invokelatest(render)
