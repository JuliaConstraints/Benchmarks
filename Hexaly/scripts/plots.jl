using TOML,CairoMakie,Random
include("../../LiLim/src/StrategyPanel.jl")
include("../../LiLim/src/PanelPlotStyles.jl")
length(ARGS)==3 || error("Usage: plots.jl SUMMARY.toml OUTPUT_DIRECTORY exact|xkcd")
summary=TOML.parsefile(abspath(ARGS[1]));out=abspath(ARGS[2]);style=ARGS[3]
style in ("exact","xkcd") || error("Unknown figure style")
if style=="xkcd"
    @eval using XKCDMakie
    Random.seed!(41);set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans",fontsize=16))
end
config=TOML.parsefile(joinpath(@__DIR__,"../../LiLim/config/strategy-variants.toml"))
methods=vcat(["cbls_naive","cbls_direct","cbls_icn","cbls_icn_fused","strategies","hybrid_highs","metastrategist","metastrategist_mixed","highs","ortools","ghost","ghost_icn","hexaly"],
    ["strategy:"*p for p in sort!(collect(keys(config["profiles"])))],StrategyPanel.methods())
colors=[:dodgerblue3,:darkorange2,:seagreen3,:purple3,:firebrick3,:gray35,:cyan3,:deeppink3,:sienna3,:steelblue3,:darkslateblue,:olivedrab3,:deepskyblue3]
markers=[:circle,:rect,:utriangle,:diamond,:dtriangle,:cross,:star5,:hexagon,:pentagon,:xcross,:octagon,:star4,:star8]
styles=PanelPlotStyles.styles(methods,methods)
allunique([(s.color,s.marker,s.linestyle) for s in values(styles)]) || error("Duplicate plot style")
mkpath(out)
for id in unique([r["instance"] for r in summary["groups"]])
    groups=filter(r->r["instance"]==id,summary["groups"]);good=filter(r->r["feasible"]>0,groups)
    isempty(good) && continue
    sort!(good;by=r->findfirst(==(r["method"]),methods));n=length(first(good)["best"])
    for component in 1:n
        fig=Figure(size=(max(1100,50length(good)),700))
        ax=Axis(fig[1,1],title="$id: objective component $component (minimized)",
            xlabel="Solver / strategy",ylabel="Objective value",xticks=(1:length(good),[replace(r["method"],'_'=>' ') for r in good]),xticklabelrotation=pi/3)
        for(i,row)in enumerate(good)
            profile=styles[row["method"]];color,marker=profile.color,profile.marker
            scatter!(ax,[i],[row["best"][component]];color,marker,markersize=14)
            scatter!(ax,[i+.16],[row["mean"][component]];color,marker,markersize=8)
            rangebars!(ax,[i+.16],[row["component_min"][component]],[row["component_max"][component]];color,whiskerwidth=8)
        end
        reference=get(first(good),"reference",Float64[])
        if length(reference)>=component
            hlines!(ax,[reference[component]];color=:black,linestyle=:dash,linewidth=3,label="Fixed BKS reference")
            axislegend(ax;position=:rt)
        end
        Label(fig[2,1],"Large marker: best; small marker: feasible-run mean; whisker: component range. Components retain fleet-first / lexicographic semantics.",fontsize=12)
        suffix=style=="xkcd" ? "-xkcd" : ""
        for extension in ("png","pdf");save(joinpath(out,"$id-component-$component$suffix.$extension"),fig);end
        success=Figure(size=(1100,600));a=Axis(success[1,1],title="$id: original-validator success",xlabel="Solver / strategy",ylabel="Feasible attempts (%)",xticks=(1:length(groups),[replace(r["method"],'_'=>' ') for r in groups]),xticklabelrotation=pi/3)
        for(i,row)in enumerate(groups);profile=styles[row["method"]];scatter!(a,[i],[100row["success_rate"]];color=profile.color,marker=profile.marker,markersize=13);end
        ylims!(a,0,105)
        # The success figure is independent of the objective component.
        component==1 && save(joinpath(out,"$id-success$suffix.png"),success)
    end
end
