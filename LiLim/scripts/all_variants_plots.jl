using TOML, Statistics, CairoMakie, Random
length(ARGS)==3 && ARGS[3] in ("exact","xkcd") || error("usage: summary.toml output-directory exact|xkcd")
const DATA=TOML.parsefile(abspath(ARGS[1]));const OUT=abspath(ARGS[2]);mkpath(OUT)
const ROWS=DATA["records"];const METHODS=DATA["methods"];const LABELS=DATA["labels"]
const IDS=DATA["instances"];const WIDTHS=DATA["widths"];const TARGETS=DATA["targets"]
const COLORS=[:gray50,:dodgerblue3,:darkorange2,:navy,:seagreen3,:purple3,:firebrick3,:sienna3,
    :deeppink3,:black,:goldenrod2,:olive,:teal,:steelblue,:magenta3]
style(j)=j in (3,6,8,10,12,15) ? :dash : :solid
subset(id,method,width)=filter(r->r["instance"]==id&&r["method"]==method&&r["threads"]==width,ROWS)
key(r)=(r["vehicles"],r["distance"])
middle(rows)=sort(rows;by=key)[2]
hit(r,id)=r["vehicles"]<TARGETS[id]["vehicles"]||(r["vehicles"]==TARGETS[id]["vehicles"]&&r["distance"]<=TARGETS[id]["distance"]+1e-6)
improved(r)=(r["vehicles"],r["distance"])<(r["initial_vehicles"],r["initial_distance"]-1e-6)
at(r,t)=begin events=filter(e->e["seconds"]<=t,r["trajectory"]);isempty(events) ? nothing : last(events) end
if ARGS[3]=="xkcd"
    @eval using XKCDMakie
    Random.seed!(41);set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans",fontsize=15,linewidth=2.3,
        Axis=(xgridvisible=false,ygridcolor=(:gray,.15),titlesize=20)))
end
function exportfig(fig,name)
    suffix=ARGS[3]=="xkcd" ? "-xkcd" : ""
    for ext in ("png","pdf");save(joinpath(OUT,name*suffix*"."*ext),fig;px_per_unit=1.5) end
end
function footer!(fig,row;reference=true)
    elements=Any[LineElement(color=COLORS[j],linestyle=style(j),linewidth=2.3) for j in eachindex(METHODS)];labels=copy(LABELS)
    if reference;push!(elements,LineElement(color=:gray30,linestyle=:dot,linewidth=2));push!(labels,"BKS SINTEF") end
    Label(fig[row,1:3],"5 s, même insertion · 3 essais par cellule · BKS = flotte ET distance · LC101 : départ déjà à la référence",fontsize=14)
    Legend(fig[row+1,1:3],elements,labels;orientation=:horizontal,nbanks=4,tellwidth=false,framevisible=false,labelsize=14)
    Label(fig[row+2,1:3],"Diagnostic exposé, profils adaptés sans HPO complet · GHOST : répétitions sans seed contrôlée · Hexaly : exécutable absent"*(ARGS[3]=="xkcd" ? "\nIllustration XKCDMakie ; coordonnées exactes dans la version sobre." : ""),fontsize=13)
end
function widthaxis(ax)
    ax.xticks=(WIDTHS,string.(WIDTHS));xlims!(ax,.8,20);ax.xscale=log2
end
function refs(fleet,distance,id,maxfleet)
    fleet.yticks=collect(TARGETS[id]["vehicles"]:maxfleet);ylims!(fleet,TARGETS[id]["vehicles"]-.5,maxfleet+.5)
    hlines!(fleet,[TARGETS[id]["vehicles"]];color=:gray30,linestyle=:dot)
    hlines!(distance,[TARGETS[id]["distance"]];color=:gray30,linestyle=:dot)
    id=="lc101" && ylims!(distance,TARGETS[id]["distance"]-1,TARGETS[id]["distance"]+1)
end
function quality(;best=false)
    fig=Figure(size=(1650,1100));Label(fig[0,1:3],best ? "Meilleur de trois essais — 5 secondes par essai" : "Toutes les variantes : qualité médiane après 5 secondes",fontsize=27)
    for (col,id) in enumerate(IDS)
        fleet=Axis(fig[1,col];title=uppercase(id),ylabel=col==1 ? "Véhicules (priorité 1)" : "")
        distance=Axis(fig[2,col];xlabel="Workers alloués",ylabel=col==1 ? "Distance brute (priorité 2)" : "")
        widthaxis(fleet);widthaxis(distance);refs(fleet,distance,id,maximum(r["initial_vehicles"] for r in ROWS if r["instance"]==id))
        for (j,m) in enumerate(METHODS)
            xs=[w for w in WIDTHS if !isempty(subset(id,m,w))];rs=[best ? first(sort(subset(id,m,w);by=key)) : middle(subset(id,m,w)) for w in xs]
            scatterlines!(fleet,xs,[r["vehicles"] for r in rs];color=COLORS[j],linestyle=style(j),marker=j%3==0 ? :rect : :circle,markersize=8)
            scatterlines!(distance,xs,[r["distance"] for r in rs];color=COLORS[j],linestyle=style(j),marker=j%3==0 ? :rect : :circle,markersize=8)
        end
    end
    footer!(fig,3);exportfig(fig,best ? "all-variants-quality-best" : "all-variants-quality")
end
function success()
    fig=Figure(size=(1650,1150));Label(fig[0,1:3],"Réussite : référence atteinte et amélioration du départ",fontsize=27)
    for (col,id) in enumerate(IDS)
        bks=Axis(fig[1,col];title=uppercase(id)*" — BKS "*string(TARGETS[id]["vehicles"])*" / "*string(TARGETS[id]["distance"]),ylabel=col==1 ? "BKS atteinte (%)" : "",yticks=0:25:100)
        gain=Axis(fig[2,col];xlabel="Workers alloués",ylabel=col==1 ? "Départ amélioré (%)" : "",yticks=0:25:100)
        for ax in (bks,gain);widthaxis(ax);ylims!(ax,-5,105) end
        for (j,m) in enumerate(METHODS)
            xs=[w for w in WIDTHS if !isempty(subset(id,m,w))]
            scatterlines!(bks,xs,[100*mean(hit(r,id) for r in subset(id,m,w)) for w in xs];color=COLORS[j],linestyle=style(j),markersize=8)
            scatterlines!(gain,xs,[100*mean(improved(r) for r in subset(id,m,w)) for w in xs];color=COLORS[j],linestyle=style(j),markersize=8)
        end
    end
    footer!(fig,3;reference=false);exportfig(fig,"all-variants-success")
    # A numeric matrix keeps coincident curves readable: missing cells are dashes.
    table=Figure(size=(1750,1300));Label(table[0,1:3],"Taux de réussite par profil — BKS / départ amélioré",fontsize=27)
    for (col,id) in enumerate(IDS)
        ax=Axis(table[1,col];title=uppercase(id),xticks=(1:5,string.(WIDTHS)),yticks=(1:15,col==1 ? reverse(LABELS) : fill("",15)),xlabel="Workers alloués",xgridvisible=false,ygridvisible=false)
        values=fill(NaN,5,15)
        for (j,m) in enumerate(METHODS),(x,w) in enumerate(WIDTHS)
            rows=subset(id,m,w);isempty(rows) || (values[x,16-j]=100*mean(hit(r,id) for r in rows))
        end
        heatmap!(ax,.5:1:5.5,.5:1:15.5,values;colorrange=(0,100),colormap=[:white,:lightblue,:dodgerblue3],nan_color=:gray90)
        for (j,m) in enumerate(METHODS),(x,w) in enumerate(WIDTHS)
            rows=subset(id,m,w)
            text!(ax,x,16-j;text=isempty(rows) ? "—" : string(count(r->hit(r,id),rows),"/3 · ",count(improved,rows),"/3"),align=(:center,:center),fontsize=14,color=:black)
        end
        xlims!(ax,.5,5.5);ylims!(ax,.5,15.5)
    end
    Label(table[2,1:3],"Chaque cellule : BKS / 3 essais · départ amélioré / 3 essais. Couleur : taux BKS. Les deux critères ne sont pas interchangeables.",fontsize=15)
    exportfig(table,"all-variants-success-matrix")
end
function anytime(width)
    fig=Figure(size=(1650,1400));Label(fig[0,1:3],"Qualité et temps d'atteinte — $(width) workers",fontsize=27)
    grid=collect(0.:.025:5.)
    for (col,id) in enumerate(IDS)
        fleet=Axis(fig[1,col];title=uppercase(id),ylabel=col==1 ? "Véhicules" : "")
        distance=Axis(fig[2,col];ylabel=col==1 ? "Distance brute" : "")
        rate=Axis(fig[3,col];xlabel="Temps total (s)",ylabel=col==1 ? "BKS atteinte (%)" : "",yticks=0:25:100)
        refs(fleet,distance,id,maximum(r["initial_vehicles"] for r in ROWS if r["instance"]==id));ylims!(rate,-5,105)
        for ax in (fleet,distance,rate);xlims!(ax,0,5) end
        for (j,m) in enumerate(METHODS)
            rows=subset(id,m,width)
            points=[begin events=[at(r,t) for r in rows];any(isnothing,events) ? nothing : middle(events) end for t in grid]
            stairs!(fleet,grid,[p===nothing ? NaN : Float64(p["vehicles"]) for p in points];step=:post,color=COLORS[j],linestyle=style(j))
            stairs!(distance,grid,[p===nothing ? NaN : Float64(p["distance"]) for p in points];step=:post,color=COLORS[j],linestyle=style(j))
            stairs!(rate,grid,[100*mean(any(e->e["seconds"]<=t&&hit(e,id),r["trajectory"]) for r in rows) for t in grid];step=:post,color=COLORS[j],linestyle=style(j))
        end
    end
    footer!(fig,4);exportfig(fig,"all-variants-anytime-$(width)t")
end
function cpuplot()
    fig=Figure(size=(1650,850));Label(fig[0,1:3],"Utilisation effective des CPU — séparée de la qualité",fontsize=27)
    for (col,id) in enumerate(IDS)
        ax=Axis(fig[1,col];title=uppercase(id),xlabel="Workers alloués",ylabel=col==1 ? "CPU actifs moyens" : "");widthaxis(ax);ylims!(ax,0,17)
        lines!(ax,WIDTHS,WIDTHS;color=:gray30,linestyle=:dot)
        for (j,m) in enumerate(METHODS)
            xs=[w for w in WIDTHS if !isempty(subset(id,m,w))]
            scatterlines!(ax,xs,[median(r["mean_active_cpus"] for r in subset(id,m,w)) for w in xs];color=COLORS[j],linestyle=style(j),markersize=8)
        end
    end
    footer!(fig,2;reference=false);exportfig(fig,"all-variants-cpu")
end
function render()
    quality();quality(;best=true);success();anytime(8);anytime(16);cpuplot()
end
Base.invokelatest(render)
