using TOML,CairoMakie,Random

length(ARGS)==3 || error("Usage: plots.jl QUALIFICATION.toml OUTPUT_DIRECTORY exact|xkcd")
proof=TOML.parsefile(abspath(ARGS[1]));out=abspath(ARGS[2]);style=ARGS[3]
style in ("exact","xkcd") || error("Unknown figure style")
if style=="xkcd"
    @eval using XKCDMakie
    Random.seed!(41);set_theme!(XKCDMakie.theme_xkcd())
else
    set_theme!(Theme(font="DejaVu Sans",fontsize=16))
end
mkpath(out)
suffix=style=="xkcd" ? "-xkcd" : ""
function export_figure(figure,name)
    for extension in ("png","pdf");save(joinpath(out,name*suffix*"."*extension),figure);end
end
function qualified_rows(rows)
    all(r->r["correctness"]=="passed",rows) || error("Figure includes an unqualified observation")
    Dict(r["method"]=>r for r in rows)
end

integrated=proof["night_integrated_owned_oracles"]
before=qualified_rows(proof["night_exchange_prefilter"]["native_fixture_oracles"])
after=qualified_rows(integrated["native_fixed_work"]["strategies"])
Set(keys(before))==Set(keys(after)) || error("Fixed-work cohorts differ")
for category in ("search","meta")
    methods=sort!([id for(id,row)in after if row["category"]==category])
    n=length(methods)
    figure=Figure(size=(1450,max(650,28n+180)))
    axis=Axis(figure[1,1],title="Fixed-work $category configurations: additional allocation reduction",
        xlabel="Remaining allocation (% of previous prefilter cohort)",ylabel="Configuration",
        yticks=(1:n,replace.(methods,"rp_"=>"","_"=>" ")))
    bytes=[100after[id]["bytes"]/before[id]["bytes"] for id in methods]
    objects=[100after[id]["objects"]/before[id]["objects"] for id in methods]
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-cohort reference")
    scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=11,label="Allocated Julia bytes")
    scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=11,label="Allocated Julia objects")
    xlims!(axis,0,max(110,maximum(vcat(bytes,objects))+5))
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"Same tiny original-model work: 40 steps per lane or 8 × 8 cooperative episodes; 2 workers. Setup and verification excluded.\nEvery oracle passed. This figure measures allocation, not solution quality or speed.",fontsize=13)
    export_figure(figure,"routing-fixed-work-"*category)
end

old=qualified_rows(proof["night_exchange_prefilter"]["original_instance_diagnostics"]["strategies"])
new=qualified_rows(integrated["original_instance_diagnostics"]["strategies"])
methods=["rp_vnd_greedy","rp_vnd_late","rp_vnd_tabu","rp_meta_fleet_distance_late","rp_meta_adaptive_late"]
methods=filter(id->haskey(old,id)&&haskey(new,id),methods)
labels=replace.(methods,"rp_"=>"","_"=>" ")
figure=Figure(size=(1450,650))
for(column,key,scale,ylabel)in ((1,"bytes",2.0^20,"Cumulative allocated Julia bytes (MiB)"),
                              (2,"search_gc_seconds",.001,"Search GC time (ms)"))
    axis=Axis(figure[1,column],title=column==1 ? "LC101: 30-second diagnostic allocations" : "LC101: 30-second diagnostic GC",
        xlabel="Configuration",ylabel=ylabel,xticks=(1:length(methods),labels),xticklabelrotation=pi/5)
    scatterlines!(axis,1:length(methods),[old[id][key]/scale for id in methods];
        color=:gray35,marker=:rect,linestyle=:dash,markersize=12,label="Previous prefilter cohort")
    scatterlines!(axis,1:length(methods),[new[id][key]/scale for id in methods];
        color=:dodgerblue3,marker=:circle,markersize=12,label="Integrated owned workspaces")
    axislegend(axis;position=:rt)
end
Label(figure[2,1:2],"Original solutions and trajectories passed validation. Two workers on CPUs 8 and 10; other chats used disjoint cores.\nTime-capped runs execute different step counts: cumulative reductions are not matched-work speedups. No accepted LC101 meta-moves in these runs.",fontsize=13)
export_figure(figure,"routing-lc101-allocation-gc")

if haskey(proof,"night_classical_resource_workspace")
    stage=proof["night_classical_resource_workspace"]
    before=Dict(r["family"]=>r for r in stage["before"]["records"] if r["backend"]=="direct")
    after=Dict(r["family"]=>r for r in stage["after"]["records"] if r["backend"]=="direct")
    families=["rcpsp","jssp","fjsp","maintenance","cvrp","cvrptw","bpp","salbp","aircraft_landing"]
    all(f->before[f]["correctness"]==after[f]["correctness"]=="passed",families) || error("Unqualified scoring case")
    figure=Figure(size=(1400,700))
    axis=Axis(figure[1,1],title="Classical scoring callbacks: fixed-work allocations",
        xlabel="Original problem family",ylabel="Allocated Julia bytes per 384 callbacks (log2)",yscale=log2,
        xticks=(1:length(families),replace.(uppercase.(families),"_"=>" ")),xticklabelrotation=pi/6)
    scatterlines!(axis,(1:length(families)).-.08,[before[f]["native_total_bytes"] for f in families];
        color=:gray35,marker=:rect,linestyle=:dash,markersize=13,label="Previous scoring source")
    scatterlines!(axis,(1:length(families)).+.08,[after[f]["native_total_bytes"] for f in families];
        color=:dodgerblue3,marker=:circle,markersize=13,label="Owned resource workspaces")
    axislegend(axis;position=:rt)
    Label(figure[2,1],"Native PerfChecker totals; 3 fixed inputs × 128 repetitions; direct backend shown; markers offset within each family for visibility.\nFused ICN checks also passed. Preparation, bank compilation and original verification excluded; no controlled speedup claim.",fontsize=13)
    export_figure(figure,"classical-scoring-allocations")
end
