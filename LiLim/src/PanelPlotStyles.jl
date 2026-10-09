"Deterministic English plotting styles, including opt-in strategy configurations."
module PanelPlotStyles
const COLORS=[:dodgerblue3,:darkorange2,:seagreen3,:purple3,:firebrick3,:gray35,:cyan3,
    :deeppink3,:sienna3,:steelblue3,:darkslateblue,:olivedrab3,:deepskyblue3]
const HTML_COLORS=["#0072B2","#D55E00","#009E73","#7B61A8","#CC3311","#555555","#00A6D6",
    "#CC79A7","#A65E2E","#31708E","#6B4C9A","#8A9A00","#0081A7"]
const MARKERS=[:circle,:rect,:utriangle,:diamond,:dtriangle,:cross,:star5,:hexagon,
    :pentagon,:xcross,:octagon,:star4,:star8]

"Keep historical references fixed and reserve distinct pairs for the Li-Lim panel."
function profile_order(config,structured_methods,extended_methods)
    variants=config["variants"]
    vcat(["cbls_naive","cbls_icn","cbls_icn_fused_scalar","cbls_icn_fused_all",
        "cbls_direct","hybrid_specialized_icn","hybrid_bridged_icn","highs_native",
        "highs_portfolio","cbls_mix_strategy","mixed_balanced","mixed_ls_heavy","ortools_native"],
        [v["method"] for v in variants[1:21]],
        ["cbls_strategy_diverse","mixed_strategy_diverse"],
        [v["method"] for v in variants[22:end]],
        sort!(setdiff(collect(keys(config["portfolios"])),["cbls_strategy_diverse","mixed_strategy_diverse"])),
        ["ghost_icn"],structured_methods,extended_methods)
end

"SVG dash pattern matching the static figure's actual line style."
function html_dash(linestyle)
    linestyle===:solid && return ""
    linestyle===:dash && return "9 3"
    linestyle===:dot && return "2 3"
    linestyle===:dashdot && return "7 3 2 3"
    throw(ArgumentError("unsupported dashboard line style: $linestyle"))
end

function style(index)
    1<=index<=4length(COLORS)*length(MARKERS) || throw(ArgumentError("plot style capacity exceeded; use separate cohorts"))
    cycle,base=divrem(index-1,length(COLORS)*length(MARKERS));i=base+1
    historical=mod(div(i-1,length(COLORS)),3)
    (;color=COLORS[mod1(i,length(COLORS))],html_color=HTML_COLORS[mod1(i,length(COLORS))],
        marker=MARKERS[mod1(i+div(i-1,length(COLORS)),length(MARKERS))],
        linestyle=(:solid,:dash,:dot,:dashdot)[mod1(historical+cycle+1,4)])
end
function styles(profiles,order)
    allunique(order) || throw(ArgumentError("duplicate style method"))
    Dict(method=>style(something(findfirst(==(method),order),0)) for method in profiles)
end
end
