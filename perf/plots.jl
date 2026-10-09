using TOML,CairoMakie,Random

length(ARGS) in (3,4) || error("Usage: plots.jl QUALIFICATION.toml OUTPUT_DIRECTORY exact|xkcd [FIGURE_NAMES]")
proof=TOML.parsefile(abspath(ARGS[1]));out=abspath(ARGS[2]);style=ARGS[3]
requested=length(ARGS)==4 ? Set(split(ARGS[4],',')) : nothing
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
    requested===nothing || name in requested || return nothing
    for extension in ("png","pdf");save(joinpath(out,name*suffix*"."*extension),figure);end
end

if haskey(proof,"night_owned_objectives_v3")
    let
    rows=proof["night_owned_objectives_v3"]["measurement"]["measurements"]
    families=["tsp","qap","cvrp","cvrptw","top","mssc","car_sequencing","maintenance"]
    all(r->r["oracle"]=="passed",rows) || error("Unqualified objective figure")
    for adapter in ("callback","adapter")
        figure=Figure(size=(1650,750))
        for (column,input) in enumerate(("initial","minimum","maximum"))
            selected=[only(filter(r->r["family"]==family&&r["input"]==input,rows)) for family in families]
            before=[r["before_"*adapter]["bytes"] for r in selected]
            after=[r[adapter]["bytes"] for r in selected]
            axis=Axis(figure[1,column],title=uppercasefirst(input)*" domain input",
                xlabel="Allocated Julia bytes per warm call",ylabel=column==1 ? "Original problem family" : "",
                yticks=(1:length(families),replace.(uppercase.(families),"_"=>" ")),
                yticklabelsvisible=column==1)
            for i in eachindex(families)
                lines!(axis,[before[i],after[i]],[i,i];color=:gray65,linestyle=:dash,linewidth=1.5)
            end
            scatter!(axis,before,1:length(families);color=:gray35,marker=:rect,markersize=13,label="Previous source reference")
            scatter!(axis,after,1:length(families);color=:dodgerblue3,marker=:circle,markersize=13,label="Owned objective scratch")
            xlims!(axis,-120,3800)
            ylims!(axis,.4,length(families)+.6)
            column==2 && Legend(figure[2,1:3],axis;orientation=:horizontal,framevisible=false)
        end
        Label(figure[0,1:3],adapter=="callback" ? "Actual prepared CBLS objective callbacks" : "Actual CBLS objective wrappers";
            fontsize=23)
        Label(figure[3,1:3],"Three fixed inputs per family; five batches of 64 warmed calls; complete original-objective checksums, including infeasible inputs.\nPrevious-source reference marks remain visible. Preparation, cache misses and unsupported arithmetic excluded; no controlled speedup claim.",fontsize=13)
        export_figure(figure,"classical-owned-objective-"*adapter*"s")
    end
    end
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

if haskey(proof,"night_classical_zero_allocations")
    stage=proof["night_classical_zero_allocations"]
    before=Dict(r["family"]=>r for r in stage["before"]["records"] if r["backend"]=="direct")
    after=Dict(r["family"]=>r for r in stage["after"]["records"] if r["backend"]=="direct")
    families=["rcpsp","jssp","fjsp","maintenance","cvrp","cvrptw","bpp","salbp","aircraft_landing"]
    all(f->before[f]["correctness"]==after[f]["correctness"]=="passed",families) || error("Unqualified scoring case")
    n=length(families);figure=Figure(size=(1500,720))
    axis=Axis(figure[1,1],title="Prepared classical callbacks: further allocation reduction",
        xlabel="Remaining allocation (% of first workspace cohort)",ylabel="Original problem family",
        yticks=(1:n,replace.(uppercase.(families),"_"=>" ")))
    bytes=[100after[f]["native_total_bytes"]/before[f]["native_total_bytes"] for f in families]
    objects=[100after[f]["native_total_allocations"]/before[f]["native_total_allocations"] for f in families]
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed first-workspace reference")
    scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=12,label="Allocated Julia bytes")
    scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=12,label="Allocated Julia objects")
    for (i,f) in enumerate(families)
        text!(axis,12,i;text="$(before[f]["native_total_bytes"]) → $(after[f]["native_total_bytes"]) bytes",
            align=(:left,:center),fontsize=14)
    end
    xlims!(axis,-4,110)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"Native PerfChecker totals; 3 fixed inputs × 128 repetitions; direct backend shown; fused ICN also qualified.\nPrepared workspaces and bank excluded. Cold calls, cache misses and wider/custom arithmetic may allocate. No speed or solution-quality claim.",fontsize=13)
    export_figure(figure,"classical-scoring-warm-allocation-reduction")
end

for (key,basename,description,xminimum,caption) in (
        ("night_owned_repair_defaults","routing-private-defaults","private repair defaults and cached names",50,
         "Matching steps and observed search counters; private buffer initialization included."),
        ("night_owned_guidance","routing-owned-guidance","owned guidance and specialized call boundaries",25,
         "Matching full trace work checksums, routes and next RNG values; native LP/MIP lifecycle totals can vary."),
        ("night_owned_relocation","routing-owned-relocation","deferred private pair relocation",95,
         "Full trace, routes and next RNG values match; some small MetaStrategist lifecycle totals increase."))
    haskey(proof,key) || continue
    rows=proof[key]["records"]
    all(r->r["correctness"]=="passed" && r["observable_work_matches"],rows) ||
        error("Repair-default figure requires qualified matching observable work")
    for category in ("search","meta")
        local methods,n,figure,axis,bytes,objects
        selected=sort!([r for r in rows if r["category"]==category];by=r->r["method"])
        n=length(selected);figure=Figure(size=(1450,max(650,28n+180)))
        axis=Axis(figure[1,1],title="Routing $category profiles: $description",
            xlabel="Remaining allocation (% of same-cohort previous source)",ylabel="Configuration",
            yticks=(1:n,[replace(r["method"],"rp_"=>"","_"=>" ") for r in selected]))
        bytes=[100r["after_bytes"]/r["before_bytes"] for r in selected]
        objects=[100r["after_objects"]/r["before_objects"] for r in selected]
        vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
        scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=11,label="Allocated Julia bytes")
        scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=11,label="Allocated Julia objects")
        xlims!(axis,xminimum,103)
        Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
        Label(figure[3,1],"52 historical profiles; same frozen package cohort; 2 workers. $caption\nAll original-model oracles passed. Allocation evidence; no speed or quality claim.",fontsize=13)
        export_figure(figure,basename*"-"*category)
    end
end

if haskey(proof,"night_owned_relocation")
    let
    rows=proof["night_owned_relocation"]["larger_fixtures"]["records"]
    all(r->r["original_oracle"]=="passed"&&r["retained_routes_and_examined_match"],rows) ||
        error("Relocation figure requires matching original-model work")
    rows=sort(rows;by=r->(r["requests"],r["seed"]))
    figure=Figure(size=(1650,850));colgap!(figure.layout,60)
    labels=["$(r["requests"]) requests / seed $(r["seed"])" for r in rows]
    for (column,field,title,powers) in ((1,"bytes_per_call","Allocated Julia bytes",11:19),
            (2,"objects_per_call","Allocated Julia objects",5:13))
        prior=[r["before"][field] for r in rows];owned=[r["after"][field] for r in rows]
        axis=Axis(figure[1,column],title=title,xlabel="Per warm pair relocation (log₂ scale)",
            ylabel=column==1 ? "Original PDPTW fixture" : "",xscale=log2,
            yticks=(1:length(rows),labels),yticklabelsvisible=column==1,
            xticks=(2.0 .^ powers,string.(2 .^ powers)))
        for i in eachindex(rows)
            lines!(axis,[prior[i],owned[i]],[i,i];color=:gray65,linestyle=:dash,linewidth=1.5)
        end
        scatter!(axis,prior,1:length(rows);color=:gray35,marker=:rect,markersize=13,label="Previous source reference")
        scatter!(axis,owned,1:length(rows);color=:dodgerblue3,marker=:circle,markersize=13,label="Owned deferred incumbent")
        xlims!(axis,2.0^first(powers),2.0^last(powers));ylims!(axis,.4,length(rows)+.6)
        column==1 && Legend(figure[2,1:2],axis;orientation=:horizontal,framevisible=false)
    end
    colgap!(figure.layout,70)
    Label(figure[0,1:2],"Pair relocation: one independent incumbent after selection";fontsize=23)
    Label(figure[3,1:2],"Five batches of eight calls; exact historical routes, examined candidates and complete checksums match.\nAll original PDPTW validators pass. Warm workspace scope; concurrent timing is not a controlled speedup.",fontsize=13)
    export_figure(figure,"pair-relocation-owned-incumbent")
    end
end
