"Deterministic English plotting styles, including opt-in strategy configurations."
module PanelPlotStyles
const COLORS=[:dodgerblue3,:darkorange2,:seagreen3,:purple3,:firebrick3,:gray35,:cyan3,
    :deeppink3,:sienna3,:steelblue3,:darkslateblue,:olivedrab3,:deepskyblue3]
const HTML_COLORS=["#0072B2","#D55E00","#009E73","#7B61A8","#CC3311","#555555","#00A6D6",
    "#CC79A7","#A65E2E","#31708E","#6B4C9A","#8A9A00","#0081A7"]
const MARKERS=[:circle,:rect,:utriangle,:diamond,:dtriangle,:cross,:star5,:hexagon,
    :pentagon,:xcross,:octagon,:star4,:star8]
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
