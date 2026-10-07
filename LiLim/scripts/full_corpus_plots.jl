using TOML, Statistics, CairoMakie, Random
include("../src/StrategyPanel.jl")
include("../src/PanelPlotStyles.jl")

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
    "mixed_ls_heavy"=>"MetaStrategist search-heavy", "ortools_native"=>"OR-Tools RoutingModel (GLS)",
    "hexaly_native"=>"Hexaly native", "ghost_icn"=>"GHOST ICN")
const STRATEGY_CONFIG = TOML.parsefile(joinpath(@__DIR__,"..","config","strategy-variants.toml"))
for variant in STRATEGY_CONFIG["variants"]
    prefix = get(variant,"hybrid",false) ? (get(variant,"bridged",false) ? "Hybrid XCSP3" : "Hybrid specialized") : "CBLS ICN"
    LABELS[variant["method"]] = prefix * " · " * replace(variant["policy"],'_'=>' ')
end
LABELS["cbls_strategy_diverse"] = "CBLS diverse strategy mix"
LABELS["mixed_strategy_diverse"] = "MetaStrategist diverse mix"
const COLORS = [:dodgerblue3, :darkorange2, :seagreen3, :purple3, :firebrick3,
    :gray35, :cyan3, :deeppink3, :sienna3, :steelblue3, :darkslateblue, :olivedrab3,
    :deepskyblue3]
const HTML_COLORS = ["#0072B2", "#D55E00", "#009E73", "#7B61A8", "#CC3311", "#555555",
    "#00A6D6", "#CC79A7", "#A65E2E", "#31708E", "#6B4C9A", "#8A9A00", "#0081A7"]
const MARKERS = [:circle, :rect, :utriangle, :diamond, :dtriangle, :cross,
    :star5, :hexagon, :pentagon, :xcross, :octagon, :star4, :star8]
const STYLE_ORDER = vcat(["cbls_naive","cbls_icn","cbls_icn_fused_scalar","cbls_icn_fused_all",
    "cbls_direct","hybrid_specialized_icn","hybrid_bridged_icn","highs_native",
    "highs_portfolio","cbls_mix_strategy","mixed_balanced","mixed_ls_heavy","ortools_native"],
    [v["method"] for v in STRATEGY_CONFIG["variants"][1:21]],
    ["cbls_strategy_diverse","mixed_strategy_diverse"],
    [v["method"] for v in STRATEGY_CONFIG["variants"][22:end]],
    sort!(setdiff(collect(keys(STRATEGY_CONFIG["portfolios"])),["cbls_strategy_diverse","mixed_strategy_diverse"])),["ghost_icn"],StrategyPanel.methods())
const PROFILE_STYLES = let
    profiles = filter(!=("hexaly_native"), METHODS)
    all(m->m in STYLE_ORDER,profiles) || error("unknown solver plot style")
    PanelPlotStyles.styles(profiles,STYLE_ORDER)
end
function profile_style(method)
    method == "hexaly_native" && return (color=:black, html_color="#111111", marker=:star8,linestyle=:dash)
    get(PROFILE_STYLES, method) do
        error("no explicit plot style configured for solver profile $method")
    end
end
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

json(value::Nothing) = "null"
json(value::Bool) = value ? "true" : "false"
json(value::Real) = isfinite(value) ? string(value) : "null"
json(value::AbstractString) = "\"" * replace(value, "\\"=>"\\\\", "\""=>"\\\"", "\n"=>"\\n", "\r"=>"\\r", "</script"=>"<\\/script") * "\""
json(value::AbstractVector) = "[" * join(json.(value), ",") * "]"
json(value::Tuple) = json(collect(value))
json(value::AbstractDict) = "{" * join((json(string(key)) * ":" * json(item) for (key, item) in value), ",") * "}"
json(value) = error("unsupported dashboard value: $(typeof(value))")

solver_family(method) = startswith(method,"xp_meta_") ? "MetaStrategist" :
    startswith(method,"xp_hybrid_") ? "Hybrid" : startswith(method,"xp_qubo_") ? "QUBO-guided CBLS" :
    startswith(method, "hybrid_") ? "Hybrid" :
    startswith(method, "highs_") ? "HiGHS" : startswith(method, "mixed_") ? "MetaStrategist" :
    method == "ortools_native" ? "OR-Tools" :
    method == "ghost_icn" ? "GHOST" :
    method == "hexaly_native" ? "Hexaly" : "CBLS"
line_style(method) = method in ("hexaly_native", "ortools_native") ? :dash : profile_style(method).linestyle

function write_dashboard()
    rows = SUMMARY["instance_results"]
    methods = String[]
    for row in SUMMARY["method_summary"]
        push!(methods, row["method"])
    end
    profiles = Any[]
    for method in methods
        style = profile_style(method)
        methodrow = only(filter(row->row["method"] == method, SUMMARY["method_summary"]))
        instancerows = sort(filter(row->row["method"] == method, rows); by=row->row["instance"])
        push!(profiles, Dict{String,Any}(
            "id"=>method, "label"=>label(method), "family"=>solver_family(method),
            "color"=>style.html_color,
            "marker"=>string(style.marker),
            "dash"=>(solver_family(method) == "Hybrid" ? "9 3" : solver_family(method) == "HiGHS" ? "2 3" : solver_family(method) == "MetaStrategist" ? "7 3 2 3" : solver_family(method) == "OR-Tools" ? "3 2 1 2" : ""),
            "hitRate"=>methodrow["bks_hit_rate"], "bestFleetGap"=>methodrow["mean_best_fleet_gap"],
            "meanFleetGap"=>methodrow["mean_run_fleet_gap"], "medianFleetGap"=>methodrow["mean_median_run_fleet_gap"],
            "distanceGap"=>methodrow["median_distance_gap_at_bks_fleet_percent"],
            "feasibleRuns"=>methodrow["feasible_runs"], "distanceCells"=>methodrow["cells_at_bks_fleet"],
            "cpu"=>(methodrow["mean_active_cpus"] < 0 ? nothing : methodrow["mean_active_cpus"]),
            "instances"=>[Dict{String,Any}(
                "id"=>row["instance"], "size"=>row["size"], "bksFleet"=>row["bks_vehicles"],
                "bksDistance"=>row["bks_distance"], "bestFleet"=>(row["feasible_runs"] == 0 ? nothing : row["best_vehicles"]),
                "meanFleet"=>(row["feasible_runs"] == 0 ? nothing : row["mean_vehicles"]),
                "medianFleet"=>(row["feasible_runs"] == 0 ? nothing : row["median_vehicles"]),
                "medianDistance"=>(row["median_vehicles"] == row["bks_vehicles"] && row["median_distance"] >= 0 ? row["median_distance"] : nothing),
                "success"=>row["bks_hit_rate"], "bksTimes"=>row["bks_times_seconds"],
                "planned"=>row["planned_runs"]
            ) for row in instancerows]
        ))
    end
    ranks = Dict(method["id"]=>((-method["hitRate"]),
        method["feasibleRuns"] == 0 ? Inf : method["medianFleetGap"],
        method["feasibleRuns"] == 0 ? Inf : method["meanFleetGap"],
        method["distanceCells"] == 0 ? Inf : method["distanceGap"]) for method in profiles)
    best_by_family = Dict{String,String}()
    for family in unique(profile["family"] for profile in profiles)
        candidates = filter(profile->profile["family"] == family, profiles)
        best_by_family[family] = first(sort(candidates; by=profile->ranks[profile["id"]]))["id"]
    end
    data = Dict{String,Any}(
        "budget"=>SUMMARY["budget_seconds"], "threads"=>SUMMARY["threads"],
        "instances"=>sort!(unique([row["instance"] for row in rows])),
        "sizes"=>sort!(unique([row["size"] for row in rows])),
        "profiles"=>profiles, "bestByFamily"=>best_by_family,
        "seedCount"=>SUMMARY["seed_count"], "runFingerprint"=>SUMMARY["run_fingerprint"])
    dashboard = raw"""<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SINTEF Li-Lim interactive comparison</title>
<style>
:root{font-family:system-ui,sans-serif;color:#17212b;background:#f5f7fa}body{max-width:1450px;margin:0 auto;padding:22px}h1{margin:0 0 4px}.sub{color:#536271;margin:0 0 18px}.layout{display:grid;grid-template-columns:320px 1fr;gap:18px}.panel,figure{background:white;border:1px solid #d7dfe7;border-radius:10px;padding:16px;box-shadow:0 2px 8px #1325380c}.panel h2{font-size:17px;margin:12px 0 7px}.buttons{display:flex;flex-wrap:wrap;gap:7px}.buttons button,select{border:1px solid #b8c4cf;background:#fff;border-radius:6px;padding:7px 10px;color:#17212b;cursor:pointer}.buttons button:hover{background:#edf3f8}.group,.profile{display:flex;align-items:center;gap:8px;padding:4px 2px;font-size:14px}.group{font-weight:650;border-top:1px solid #e5eaf0;padding-top:9px;margin-top:6px}.profile{padding-left:15px}.profile i{width:12px;height:12px;border-radius:50%;display:inline-block;border:1px solid #333}.profile label,.group label{cursor:pointer}.selectrow{display:flex;align-items:center;gap:9px;margin:10px 0}.selectrow select{flex:1}figure{margin:0;min-width:0}svg{display:block;width:100%;height:auto;min-height:430px}.refkey{display:inline-flex;gap:7px;align-items:center;margin-top:10px;font-size:13px}.refkey b{display:inline-block;width:26px;border-top:2px dashed #18232d}.note{font-size:12px;color:#536271;margin-top:8px}.tooltip{font-size:13px} @media(max-width:900px){.layout{grid-template-columns:1fr}body{padding:12px}}
</style>
<body><h1>SINTEF Li-Lim interactive comparison</h1><p class="sub">Starts with the highest-BKS-attainment profile in each family; ties favor lower median fleet gap, then mean fleet and distance gap. SINTEF references stay visible; toggle profiles or whole families to compare alternatives.</p>
<div class="layout"><aside class="panel"><h2>View</h2><div class="selectrow"><label for="metric">Measure</label><select id="metric"><option value="attainment">Time to SINTEF BKS</option><option value="success">BKS success by instance</option><option value="best">Best fleet gap by instance</option><option value="mean">Mean fleet gap by instance</option><option value="median">Median-run fleet gap by instance</option><option value="distance">Median distance gap at BKS fleet</option><option value="cpu">Mean active CPUs</option></select></div>
<div class="buttons"><button id="best">Best in each family</button><button id="all">Show all</button><button id="none">Clear solvers</button></div><h2>Solver families</h2><div id="groups"></div><h2>Solver profiles</h2><div id="profiles"></div><p class="note">The zero fleet/distance gap, 100% BKS attainment/success, and allocated CPU count are reference marks. They are not solver series and cannot be hidden.</p></aside>
<figure><div id="chart" role="img" aria-label="Interactive solver comparison chart"></div><div class="refkey"><b></b><span id="reference"></span></div><div class="note" id="caption"></div></figure></div>
<script>
const DATA = __BENCHMARK_DATA__;
const families=[...new Set(DATA.profiles.map(p=>p.family))];
const selected=new Set(Object.values(DATA.bestByFamily));
const colors=Object.fromEntries(DATA.profiles.map(p=>[p.id,p.color]));
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function drawControls(){
 const g=document.getElementById('groups'),p=document.getElementById('profiles');
 g.innerHTML=families.map(f=>{let id='group-'+f.replace(/[^a-z0-9]+/gi,'-');return `<div class="group"><input id="${id}" type="checkbox" data-family="${esc(f)}"><label for="${id}">${esc(f)}</label></div>`}).join('');
 p.innerHTML=DATA.profiles.map(x=>`<div class="profile"><input id="profile-${esc(x.id)}" type="checkbox" data-profile="${esc(x.id)}" ${selected.has(x.id)?'checked':''}><i style="background:${x.color}"></i><label for="profile-${esc(x.id)}">${esc(x.label)}</label></div>`).join('');
 g.querySelectorAll('[data-family]').forEach(c=>c.addEventListener('change',()=>{DATA.profiles.filter(x=>x.family===c.dataset.family).forEach(x=>c.checked?selected.add(x.id):selected.delete(x.id));sync()}));
 p.querySelectorAll('[data-profile]').forEach(c=>c.addEventListener('change',()=>{c.checked?selected.add(c.dataset.profile):selected.delete(c.dataset.profile);sync()}));
}
function sync(){
 document.querySelectorAll('[data-profile]').forEach(c=>c.checked=selected.has(c.dataset.profile));
 document.querySelectorAll('[data-family]').forEach(c=>{let xs=DATA.profiles.filter(x=>x.family===c.dataset.family);c.checked=xs.every(x=>selected.has(x.id));c.indeterminate=xs.some(x=>selected.has(x.id))&&!c.checked});
 draw();
}
function metricData(p,key){
 const xs=DATA.instances;
 if(key==='attainment'){
   const times=p.instances.flatMap(i=>i.bksTimes),total=p.instances.reduce((a,i)=>a+i.planned,0),steps=120;
   return Array.from({length:steps+1},(_,n)=>{let x=DATA.budget*n/steps;return [x,total?100*times.filter(t=>t<=x).length/total:0]});
 }
 if(key==='cpu')return [[p.label,p.cpu]];
 return p.instances.map(i=>{
   let v=key==='success'?100*i.success:key==='best'?(i.bestFleet===null?null:i.bestFleet-i.bksFleet):key==='mean'?(i.meanFleet===null?null:i.meanFleet-i.bksFleet):key==='median'?(i.medianFleet===null?null:i.medianFleet-i.bksFleet):key==='distance'?(i.medianDistance===null?null:100*(i.medianDistance/i.bksDistance-1)):null;
   return [i.id,v];
 });
}
function shape(p,x,y){let r=5,c=p.color,m=p.marker;
 const polygon={pentagon:5,hexagon:6,octagon:8},star=m.match(/^star([458])$/),n=star?2*Number(star[1]):polygon[m];
 if(n){let points=Array.from({length:n},(_,i)=>{let a=-Math.PI/2+2*Math.PI*i/n,rr=star&&i%2?2.5:6;return `${x+rr*Math.cos(a)},${y+rr*Math.sin(a)}`}).join(' ');return `<polygon points="${points}" fill="${c}" stroke="white" stroke-width="1"/>`}
 switch(m){case 'rect':return `<rect x="${x-4}" y="${y-4}" width="8" height="8" fill="${c}" stroke="white"/>`;case 'diamond':return `<path d="M ${x} ${y-6} L ${x+5} ${y} L ${x} ${y+6} L ${x-5} ${y} Z" fill="${c}" stroke="white"/>`;case 'utriangle':case 'dtriangle':return `<path d="M ${x} ${y+(m==='utriangle'? -6:6)} L ${x+5} ${y+(m==='utriangle'?4:-4)} L ${x-5} ${y+(m==='utriangle'?4:-4)} Z" fill="${c}" stroke="white"/>`;case 'cross':case 'xcross':return `<path d="${m==='cross'?`M${x-5} ${y}h10 M${x} ${y-5}v10`:`M${x-4} ${y-4}l8 8 M${x+4} ${y-4}l-8 8`}" stroke="${c}" stroke-width="2.5"/>`;default:return `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}" stroke="white" stroke-width="1.2"/>`}}
function draw(){
 const key=document.getElementById('metric').value,chosen=DATA.profiles.filter(p=>selected.has(p.id));
 const cpu=key==='cpu',att=key==='attainment',labels=att?[]:cpu?chosen.map(p=>p.label):DATA.instances;
 let points=chosen.flatMap(p=>metricData(p,key).map(([x,y])=>y).filter(Number.isFinite));
 let ref=key==='success'||att?100:key==='cpu'?DATA.threads:0;
 let ymin=key==='success'||att?0:Math.min(ref,...points,0),ymax=key==='success'||att?105:Math.max(ref,...points,1);
 if(key==='cpu'){ymin=0;ymax=Math.max(DATA.threads+1,...points,1)}
 if(ymax===ymin)ymax=ymin+1;if(!['success','attainment'].includes(key)){const pad=(ymax-ymin)*.06;ymin=Math.min(ymin,ref)-pad;ymax=Math.max(ymax,ref)+pad;if(cpu)ymin=0}
 const W=1100,H=570,L=86,R=30,T=32,B=90,pw=W-L-R,ph=H-T-B;
 const sx=x=>att?L+(x/DATA.budget)*pw:L+(labels.indexOf(x)+.5)*pw/Math.max(labels.length,1);
 const sy=y=>T+(ymax-y)/(ymax-ymin)*ph;
 const title={attainment:'Time to the SINTEF Best-Known Target',success:'BKS success by instance',best:'Best fleet gap vs SINTEF reference',mean:'Mean fleet gap vs SINTEF reference',median:'Median-run fleet gap vs SINTEF reference',distance:'Median distance gap at the BKS fleet',cpu:'Mean active CPUs'}[key];
 const ylabel=att||key==='success'?'Runs (%)':key==='cpu'?'Mean active CPUs':key==='distance'?'Distance gap (%)':'Vehicle gap';
 let svg=`<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="white"/><text x="${L}" y="23" font-size="19" font-weight="650">${title}</text>`;
 for(let n=0;n<=5;n++){let y=ymin+(ymax-ymin)*n/5,py=sy(y);svg+=`<line x1="${L}" y1="${py}" x2="${W-R}" y2="${py}" stroke="#dce3e9"/><text x="${L-10}" y="${py+4}" text-anchor="end" font-size="12" fill="#465562">${y.toFixed(1)}</text>`}
 const refy=sy(ref);svg+=`<line x1="${L}" y1="${refy}" x2="${W-R}" y2="${refy}" stroke="#1b2730" stroke-width="2" stroke-dasharray="5 5"/>`;
 if(att){for(let t=0;t<=5;t++){let x=DATA.budget*t/5,px=sx(x);svg+=`<line x1="${px}" y1="${T}" x2="${px}" y2="${H-B}" stroke="#eef1f4"/><text x="${px}" y="${H-B+22}" text-anchor="middle" font-size="12" fill="#465562">${x.toFixed(0)} s</text>`}}
 else labels.forEach((x,i)=>{let px=sx(x);svg+=`<line x1="${px}" y1="${T}" x2="${px}" y2="${H-B}" stroke="#eef1f4"/><text x="${px}" y="${H-B+22}" text-anchor="middle" font-size="12" fill="#465562">${esc(x)}</text>`});
 svg+=`<text x="18" y="${T+ph/2}" transform="rotate(-90 18 ${T+ph/2})" text-anchor="middle" font-size="13" fill="#263541">${ylabel}</text>`;
 for(const p of chosen){let ds=metricData(p,key),valid=ds.filter(d=>Number.isFinite(d[1]));if(!valid.length)continue;let xy=valid.map(d=>[sx(d[0]),sy(d[1])]);let dash=p.dash?` stroke-dasharray="${p.dash}"`:'';svg+=`<path d="${xy.map((q,i)=>(i?'L':'M')+q[0]+' '+q[1]).join(' ')}" fill="none" stroke="${p.color}" stroke-width="2.7"${dash}/><g fill="${p.color}">`;for(let i=0;i<valid.length;i++){let [x,y]=xy[i],d=valid[i],desc=att?`${d[0].toFixed(1)} sec: ${d[1].toFixed(1)}% of planned trials reached both SINTEF targets`:cpu?`${p.label}: ${d[1]?.toFixed(2)??'unavailable'} active CPUs`: `${d[0]}: ${d[1]?.toFixed(3)??'no feasible result'}`;svg+=`<g>${shape(p,x,y)}<title>${esc(p.label+' · '+desc)}</title></g>`}svg+='</g>'}
 svg+=`<line x1="${L}" y1="${T}" x2="${L}" y2="${H-B}" stroke="#263541"/><line x1="${L}" y1="${H-B}" x2="${W-R}" y2="${H-B}" stroke="#263541"/><text x="${L+pw/2}" y="${H-20}" text-anchor="middle" font-size="13" fill="#263541">${att?'Elapsed wall time (seconds)':cpu?'Solver profile':'Official instance'}</text>`;
 document.getElementById('chart').innerHTML=svg;
 document.getElementById('reference').textContent=att?'100% = all planned trials attained both SINTEF targets':key==='success'?'100% = every planned run attained both SINTEF targets':key==='cpu'?`Allocated worker reference: ${DATA.threads} CPUs`:(key==='distance'?'0% = SINTEF distance target at the BKS fleet':'0 vehicles = SINTEF fleet reference');
 document.getElementById('caption').textContent=`${DATA.profiles.length} profiles · ${DATA.instances.length} official instances · ${DATA.seedCount} seeds · ${DATA.budget}s per trial · Hover markers for details. References are fixed.`;
}
drawControls();sync();document.getElementById('metric').addEventListener('change',draw);
document.getElementById('best').onclick=()=>{selected.clear();Object.values(DATA.bestByFamily).forEach(x=>selected.add(x));sync()};
document.getElementById('all').onclick=()=>{DATA.profiles.forEach(x=>selected.add(x.id));sync()};
document.getElementById('none').onclick=()=>{selected.clear();sync()};
</script></body></html>"""
    dashboard = replace(dashboard, "__BENCHMARK_DATA__"=>json(data))
    mkpath(OUT)
    write(joinpath(OUT, "interactive.html"), dashboard)
end

function attainment_plot()
    budget = SUMMARY["budget_seconds"]
    grid = collect(range(0, budget; length=121))
    ncols = min(4, length(METHODS))
    nrows = cld(length(METHODS), ncols)
    fig = Figure(size=(2050, 330nrows + 230))
    Label(fig[0, 1:ncols], "Time to the SINTEF Best-Known Target", fontsize=27)
    Label(fig[1, 1:ncols], "One panel per solver profile · common time and success scales", fontsize=16)
    for (index, method) in enumerate(METHODS)
        row, col = divrem(index - 1, ncols) .+ (2, 1)
        style = profile_style(method)
        color = style.color
        ax = Axis(fig[row, col]; title=label(method),
            xlabel=row == nrows + 1 ? "Elapsed wall time (seconds)" : "",
            ylabel=col == 1 ? "Runs reaching SINTEF BKS (%)" : "",
            xtickformat=values -> string.(round.(values; digits=1)), yticks=0:25:100)
        rows = filter(row->row["method"] == method, SUMMARY["instance_results"])
        times = reduce(vcat, (row["bks_times_seconds"] for row in rows); init=Float64[])
        scheduled = sum(row["planned_runs"] for row in rows)
        y = [scheduled == 0 ? 0.0 : 100 * count(time->time <= t, times) / scheduled for t in grid]
        lines!(ax, grid, y; color, linewidth=2.6, linestyle=line_style(method))
        marker_positions = 1:10:length(grid)
        scatter!(ax, grid[marker_positions], y[marker_positions]; color,
            marker=style.marker, markersize=10)
        hlines!(ax, [100.0]; color=:black, linestyle=:dot, linewidth=1.7)
        xlims!(ax, 0, budget * 1.04)
        ylims!(ax, 0, 102)
    end
    Label(fig[nrows + 2, 1:ncols], "Dotted lines mark 100% target attainment. Budget: $(budget) s · $(SUMMARY["threads"]) workers · $(SUMMARY["seed_count"]) seeds · $(SUMMARY["instance_count"]) official instances · BKS distance rounded to $(SUMMARY["bks_distance_digits"]) decimals · misses censored at the budget", fontsize=14)
    savefig(fig, "lilim-bks-attainment")
end

function quality_by_size()
    sizes = sort!(unique([row["size"] for row in SUMMARY["size_summary"]]))
    instance_mode = length(sizes) == 1
    rows = instance_mode ? SUMMARY["instance_results"] : SUMMARY["size_summary"]
    categories = instance_mode ? sort!(unique([row["instance"] for row in rows])) : sizes
    xvalue(row) = findfirst(==(instance_mode ? row["instance"] : row["size"]), categories)
    titles = ("Best fleet gap", "Mean-run fleet gap",
        "Median-run fleet gap", "Median distance gap at BKS fleet")
    ylabel = ("Vehicle gap from SINTEF BKS", "Vehicle gap from SINTEF BKS",
        "Vehicle gap from SINTEF BKS", "Distance gap at BKS fleet (%)")
    filenames = ("lilim-quality-best-fleet-gap-by-profile",
        "lilim-quality-mean-fleet-gap-by-profile",
        "lilim-quality-median-fleet-gap-by-profile",
        "lilim-quality-distance-gap-by-profile")
    series = Dict{String,Any}()
    all_values = [Float64[] for _ in 1:4]
    for method in METHODS
        style = profile_style(method)
        selected = sort(filter(row->row["method"] == method, rows); by=row->instance_mode ? row["instance"] : row["size"])
        xs = [xvalue(row) for row in selected]
        best = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["best_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_best_fleet_gap"]) for row in selected]
        average = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["mean_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_run_fleet_gap"]) for row in selected]
        median_run = [instance_mode ? (row["feasible_runs"] == 0 ? NaN : row["median_vehicles"]-row["bks_vehicles"]) :
            (row["valid_cells"] == 0 ? NaN : row["mean_median_run_fleet_gap"]) for row in selected]
        if instance_mode
            distrows = filter(row->row["median_vehicles"] == row["bks_vehicles"] && row["median_distance"] >= 0, selected)
            distx = [xvalue(row) for row in distrows]
            dist = [100 * (row["median_distance"] / row["bks_distance"] - 1) for row in distrows]
        else
            distrows = filter(row->row["distance_cells"] > 0, selected)
            distx = [xvalue(row) for row in distrows]
            dist = [row["mean_distance_gap_at_bks_fleet_percent"] for row in distrows]
        end
        values = (best, average, median_run, dist)
        series[method] = ((xs, best), (xs, average), (xs, median_run), (distx, dist), style)
        for column in 1:4
            append!(all_values[column], filter(isfinite, values[column]))
        end
    end
    limits = map(all_values) do values
        finite = filter(isfinite, values)
        isempty(finite) && return (-1.0, 1.0)
        low, high = min(minimum(finite), 0.0), max(maximum(finite), 0.0)
        pad = max(0.05 * (high - low), 0.05)
        (low - pad, high + pad)
    end
    ncols = min(4, length(METHODS))
    nrows = cld(length(METHODS), ncols)
    for column in 1:4
        fig = Figure(size=(1900, 340nrows + 220))
        Label(fig[0, 1:ncols], titles[column] * " by Solver Profile", fontsize=27)
        for (index, method) in enumerate(METHODS)
            row, col = divrem(index - 1, ncols) .+ (1, 1)
            ax = Axis(fig[row, col]; title=label(method),
                xlabel=row == nrows ? (instance_mode ? "Official 100-request instance" : "Requests per instance") : "",
                ylabel=col == 1 ? ylabel[column] : "",
                xticks=(1:length(categories), string.(categories)))
            xlims!(ax, 0.5, length(categories) + 0.5)
            ylims!(ax, limits[column]...)
            hlines!(ax, [0.0]; color=:black, linestyle=:dot, linewidth=1.7)
            xs, ys = series[method][column]
            style = series[method][5]
            isempty(ys) || scatterlines!(ax, xs, ys; color=style.color, marker=style.marker,
                markersize=9, linewidth=2.0,
                linestyle=line_style(method))
        end
        Label(fig[nrows + 1, 1:ncols], "One panel per solver profile · common scale within this figure · negative fleet gaps beat the reference · dotted zero marks the SINTEF reference", fontsize=14)
        savefig(fig, filenames[column])
    end
end

function success_by_size()
    sizes = sort!(unique([row["size"] for row in SUMMARY["size_summary"]]))
    instance_mode = length(sizes) == 1
    rows = instance_mode ? SUMMARY["instance_results"] : SUMMARY["size_summary"]
    categories = instance_mode ? sort!(unique([row["instance"] for row in rows])) : sizes
    xvalue(row) = findfirst(==(instance_mode ? row["instance"] : row["size"]), categories)
    nmethods = length(METHODS)
    ncols = min(4, nmethods)
    nrows = cld(nmethods, ncols)
    fig = Figure(size=(2050, 300nrows + 230))
    Label(fig[0, 1:ncols], instance_mode ? "Best-Known Solution Success by Instance" : "Best-Known Solution Success by Problem Size", fontsize=27)
    Label(fig[1, 1:ncols], "One panel per solver profile · common success scale", fontsize=16)
    for (index, method) in enumerate(METHODS)
        row, col = divrem(index - 1, ncols) .+ (2, 1)
        style = profile_style(method)
        color, marker = style.color, style.marker
        selected = sort(filter(row->row["method"] == method, rows); by=row->instance_mode ? row["instance"] : row["size"])
        xs = [xvalue(row) for row in selected]
        ys = [100 * row["bks_hit_rate"] for row in selected]
        ax = Axis(fig[row, col]; title=label(method),
            xlabel=row == nrows + 1 ? (instance_mode ? "Official 100-request instance" : "Requests per instance") : "",
            ylabel=col == 1 ? "Runs reaching SINTEF BKS (%)" : "",
            xticks=(1:length(categories), string.(categories)), yticks=0:25:100)
        scatterlines!(ax, xs, ys; color, marker, markersize=9,
            linewidth=2.4, linestyle=line_style(method),
            )
        hlines!(ax, [100.0]; color=:black, linestyle=:dot, linewidth=1.7)
        xlims!(ax, 0.5, length(categories) + 0.5)
        ylims!(ax, 0, 102)
    end
    Label(fig[nrows + 2, 1:ncols], "Dotted lines mark 100% success. Rates use every scheduled seed; incomplete runs remain in the denominator.", fontsize=14)
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
    barplot!(ax, xs, values; color=[profile_style(row["method"]).color for row in methods])
    hlines!(ax, [SUMMARY["threads"]]; color=:black, linestyle=:dot, linewidth=2.0)
    finite_values = filter(isfinite, values)
    ylims!(ax, 0, max(SUMMARY["threads"] + 1, maximum(finite_values; init=0.0) + 1))
    Label(fig[2, 1], "Dotted line marks the allocated worker count ($(SUMMARY["threads"])). CPU time includes initialization, model setup, search and validation inside each trial's shared budget.", fontsize=14)
    savefig(fig, "lilim-cpu-use")
end

attainment_plot()
quality_by_size()
success_by_size()
cpu_plot()
STYLE == "exact" && write_dashboard()
println("Saved English benchmark plots to ", OUT, " (", STYLE, " style)")
