using TOML, Statistics, CairoMakie, Random
length(ARGS)==2 && ARGS[2] in ("exact","xkcd") || error("usage: competitors_plots.jl output-directory exact|xkcd")
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=abspath(ARGS[1]);mkpath(OUT)
include(joinpath(ROOT,"src","BenchmarkTargets.jl"))
const IDS=["lc101","lr101","lrc101"];const WIDTHS=[1,2,4,8,16]
const COLORS=[:seagreen3,:dodgerblue3,:darkorange2]
const LABELS=["CBLS + ICN","Timefold LA 400","Timefold LA 1,000"]
const TARGETS=TOML.parsefile(joinpath(ROOT,"config","diagnostic-targets.toml"))
const DATA=Dict{Tuple{String,Int,Int},Vector{Any}}()
for width in WIDTHS
    cbls=TOML.parsefile(joinpath(ROOT,"results","competitor-cbls-$(width)t-20261004.toml"))
    cbls["complete"] || error("unfinished CBLS control")
    for id in IDS;DATA[(id,width,1)]=filter(r->r["instance"]==id,cbls["trials"]) end
    for (kind,label) in ((2,"late"),(3,"late1000"))
        tf=TOML.parsefile(joinpath(ROOT,"results","timefold-$(label)-$(width)t-20261004.toml"))
        tf["complete"] || error("unfinished Timefold capture")
        for instance in tf["instances"]
            haskey(instance,"native_budget_seconds") || error("unmatched clock in comparison")
            DATA[(instance["id"],width,kind)]=instance["qualified_trials"]
        end
    end
end
key(r)=(r["vehicles"],r["distance"])
lexmedian(rows)=sort(rows;by=key)[2]
hit(event,id)=BenchmarkTargets.reaches_published_bks(event["vehicles"],event["distance"],
    TARGETS[id]["vehicles"],TARGETS[id]["distance"];distance_digits=TARGETS["bks_distance_digits"])
at(r,t)=begin
    events=filter(e->e["seconds"]<=t,r["trajectory"])
    isempty(events) ? nothing : last(events)
end
if ARGS[2]=="xkcd"
    @eval using XKCDMakie
    Random.seed!(41);set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans",fontsize=16,linewidth=2.5,
        Axis=(xgridvisible=false,ygridcolor=(:gray,0.15),titlesize=20)))
end
function exportfig(fig,name)
    suffix=ARGS[2]=="xkcd" ? "-xkcd" : ""
    for extension in ("png","pdf");save(joinpath(OUT,name*suffix*"."*extension),fig;px_per_unit=1.5) end
end
function render()
    legends=[LineElement(color=c,linewidth=2.5) for c in COLORS]
    reference=LineElement(color=:gray30,linestyle=:dot,linewidth=2)
    quality=Figure(size=(1500,1100))
    Label(quality[0,1:3],"CBLS / Timefold: quality and reference in 5 seconds",fontsize=27)
    anytime=Figure(size=(1500,1100))
    Label(anytime[0,1:3],"Search trajectories and success — 16 workers, 5 seconds",fontsize=27)
    grid=collect(0.:0.025:5.)
    for (column,id) in enumerate(IDS)
        fleet=Axis(quality[1,column];title=uppercase(id),ylabel=column==1 ? "Vehicles" : "",xlabel="Allocated workers",xticks=WIDTHS)
        distance=Axis(quality[2,column];ylabel=column==1 ? "Raw distance" : "",xlabel="Allocated workers",xticks=WIDTHS)
        rate=Axis(quality[3,column];ylabel=column==1 ? "Reference reached (%)" : "",xlabel="Allocated workers",xticks=WIDTHS,yticks=0:25:100)
        fleettime=Axis(anytime[1,column];title=uppercase(id),ylabel=column==1 ? "Vehicles" : "")
        disttime=Axis(anytime[2,column];ylabel=column==1 ? "Raw distance" : "")
        ratetime=Axis(anytime[3,column];ylabel=column==1 ? "Reference reached (%)" : "",xlabel="Elapsed time (s)",yticks=0:25:100)
        maxfleet=maximum(r["vehicles"] for w in WIDTHS for kind in 1:3 for r in DATA[(id,w,kind)])
        for axis in (fleet,fleettime)
            axis.yticks=collect(TARGETS[id]["vehicles"]:maxfleet)
            ylims!(axis,TARGETS[id]["vehicles"]-0.5,maxfleet+0.5)
            hlines!(axis,[TARGETS[id]["vehicles"]];color=:gray30,linestyle=:dot)
        end
        for axis in (distance,disttime);hlines!(axis,[TARGETS[id]["distance"]];color=:gray30,linestyle=:dot) end
        if id=="lc101"
            for axis in (distance,disttime);ylims!(axis,TARGETS[id]["distance"]-1,TARGETS[id]["distance"]+1) end
        end
        for axis in (fleet,distance,rate);xlims!(axis,0,17) end
        for axis in (fleettime,disttime,ratetime);xlims!(axis,0,5) end
        for axis in (rate,ratetime);ylims!(axis,-5,105) end
        for kind in 1:3
            style=kind==3 ? :dash : :solid
            summaries=[lexmedian(DATA[(id,w,kind)]) for w in WIDTHS]
            scatterlines!(fleet,WIDTHS,[r["vehicles"] for r in summaries];color=COLORS[kind],linestyle=style,markersize=10)
            scatterlines!(distance,WIDTHS,[r["distance"] for r in summaries];color=COLORS[kind],linestyle=style,markersize=10)
            scatterlines!(rate,WIDTHS,[100*mean(hit(r,id) for r in DATA[(id,w,kind)]) for w in WIDTHS];color=COLORS[kind],linestyle=style,markersize=10)
            rs=DATA[(id,16,kind)]
            points=[begin
                events=[at(r,t) for r in rs]
                any(isnothing,events) ? nothing : lexmedian(events)
            end for t in grid]
            stairs!(fleettime,grid,[p===nothing ? NaN : Float64(p["vehicles"]) for p in points];step=:post,color=COLORS[kind],linestyle=style)
            stairs!(disttime,grid,[p===nothing ? NaN : Float64(p["distance"]) for p in points];step=:post,color=COLORS[kind],linestyle=style)
            stairs!(ratetime,grid,[100*mean(any(e->e["seconds"]<=t && hit(e,id),r["trajectory"]) for r in rs) for t in grid];step=:post,color=COLORS[kind],linestyle=style)
        end
    end
    caption="Exposed diagnostic set · 3 seeds · same insertion start · fleet, then distance · dotted lines: SINTEF BKS\nCommunity runs independent serial solvers in one JVM. CBLS uses independent Julia workers. Different solver versions/profiles."
    for fig in (quality,anytime)
        Label(fig[4,1:3],caption,fontsize=14)
        Legend(fig[5,1:3],vcat(legends,[reference]),vcat(LABELS,["SINTEF BKS (rounded distance)"]);
            orientation=:horizontal,tellwidth=false,framevisible=false)
        if ARGS[2]=="xkcd"
            Label(fig[6,1:3],"XKCDMakie illustration; plain-style version has exact coordinates. Descriptive rates from 3 runs; no extrapolation.",fontsize=14)
        end
    end
    exportfig(quality,"competitors-quality");exportfig(anytime,"competitors-anytime")
end
Base.invokelatest(render)
