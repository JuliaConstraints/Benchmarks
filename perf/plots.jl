using TOML,CairoMakie,Random,Statistics

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

# Avoid constructing the historical figures when only the reserved-cohort
# figures were explicitly selected; every historical export remains available.
if requested===nothing || any(name->!startswith(name,"routing-cohort-reserved-"),requested)
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
         "Full trace, routes and next RNG values match; some small MetaStrategist lifecycle totals increase."),
        ("night_surviving_relocation","routing-surviving-relocation","copy only surviving primitive routes",90,
         "Full trace, routes and next RNG values match; fresh LP/MIP lifecycle variation is retained."),
        ("night_owned_trace","routing-owned-trace","private numeric trace storage",90,
         "Full trace, routes and next RNG values match; short complete MetaStrategist lifecycles can allocate more."),
        ("night_owned_snapshots","routing-owned-snapshots","independent primitive route snapshots",70,
         "Full trace, routes and next RNG values match; all observed profile allocations are unchanged or lower."),
        ("night_owned_range_cache","routing-owned-range-cache","bounded private cache capacity",98,
         "Full trace/routes/RNG match; all small-profile variations remain shown. Original LR101 allocations are unchanged."),
        ("night_owned_membership","routing-owned-membership","private pool membership positions",65,
         "Full trace/routes/RNG match; initial HIPO lifecycle variation is retained. Exact-warmed paired paths are shown separately."),
        ("night_owned_pool_columns","routing-owned-pool-columns","borrow ordered native pool columns",98,
         "Full trace/routes/RNG match; 50 profiles allocate fewer bytes and two are unchanged. Generic callback effects retain eager snapshots."),
        ("night_native_empty_insertion","routing-native-empty-insertion","ordered native empty-sequence insertion",55,
         "Full trace/routes/RNG match; every initial lifecycle variation remains shown. Generic callback order and exceptional floating values retain the original cache path."),
        ("night_owned_best_quality","routing-owned-best-quality","owned coordinator quality snapshots",98,
         "Full trace/routes/RNG match; initial model lifecycle variations remain shown. Complete lane qualities retain their original floating bits."))
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
        xlims!(axis,xminimum,max(103,maximum(vcat(bytes,objects))+5))
        Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
        Label(figure[3,1],"52 historical profiles; same frozen package cohort; 2 workers. $caption\nAll original-model oracles passed. Allocation evidence; no speed or quality claim.",fontsize=13)
        export_figure(figure,basename*"-"*category)
    end
end

if haskey(proof,"night_owned_best_quality")
    let
    stage=proof["night_owned_best_quality"]
    rows=stage["native_best_quality_pairs"]["records"]
    all(r->r["original_oracle"]=="passed" && r["checksum_matches"],rows) ||
        error("Unqualified coordinator quality pairs")
    n=length(rows);figure=Figure(size=(1600,820))
    axis=Axis(figure[1,1],title="Actual prepared lanes: owned coordinator quality snapshots",
        xlabel="Remaining allocation (% of same-cohort previous source)",ylabel="Prepared lane states / seed",
        yticks=(1:n,["$(r["width"]) lane states / seed $(r["seed"])" for r in rows]))
    bytes=[100r["after"]["bytes"]/r["before"]["bytes"] for r in rows]
    objects=[100r["after"]["objects"]/r["before"]["objects"] for r in rows]
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
    scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=12,label="Allocated Julia bytes")
    scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=12,label="Allocated Julia objects")
    xlims!(axis,-2,103);ylims!(axis,.5,n+.5)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"One warmed batch of 1,000 complete quality refreshes plus ordered consumption; constant 448-byte/9-object scaffold retained.\nPrepared widths 1/2/4/8/16 are lane states; only 2 threads run. Qualities, checksum, lane ownership and original PDPTW solutions match.\nThe isolated refresh allocates zero bytes. Concurrent timing; no controlled speed or solution-quality claim.",fontsize=13)
    export_figure(figure,"routing-owned-best-quality-native")

    rows=stage["exact_warm_meta"]["records"]
    all(r->r["all_lane_and_coordination_work_matches"],rows) || error("Unqualified cooperative quality snapshots")
    methods=sort!(unique(r["method"] for r in rows));n=length(methods)
    figure=Figure(size=(1600,820))
    axis=Axis(figure[1,1],title="Actual MetaStrategist cooperation: owned coordinator quality snapshots",
        xlabel="Remaining allocation (% of same-cohort previous source)",ylabel="Configuration",
        yticks=(1:n,[replace(id,"rp_"=>"","_"=>" ") for id in methods]))
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
    maxima=Float64[]
    for (metric,color,marker,offset,label) in (("bytes",:dodgerblue3,:circle,-.12,"Allocated Julia bytes"),
            ("objects",:purple3,:utriangle,.12,"Allocated Julia objects"))
        values=[[100r["after"][metric]/r["before"][metric] for r in rows if r["method"]==id] for id in methods]
        append!(maxima,maximum.(values))
        for (i,v) in enumerate(values)
            lines!(axis,[minimum(v),maximum(v)],fill(i+offset,2);color,linewidth=2)
        end
        scatter!(axis,[sum(v)/length(v) for v in values],(1:n).+offset;color,marker,markersize=12,label)
    end
    xlims!(axis,98,max(101,maximum(maxima)+1));ylims!(axis,.5,n+.5)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"48 paired paths: 16 configurations × 3 seeds; 8 actual cooperative episodes × 2 workers, including simplex/IPX/HIPO masters.\nMarkers: mean paired ratio; bars: full seed range. Two byte and two object increases are retained. Complete substantive work and zero compilation/recompilation.\nOriginal validator and all warm attempts retained. Concurrent timing; no controlled speed or solution-quality claim.",fontsize=13)
    export_figure(figure,"routing-owned-best-quality-exact-warm-meta")
    end
end

for (stagekey,prefix,nativekey,description,native_minimum,fixed_minimum,meta_minimum) in (
        ("night_owned_membership","routing-owned-membership","native_membership_pairs","private pool membership",-2,68,94),
        ("night_owned_pool_columns","routing-owned-pool-columns","native_pool_column_pairs","borrowed native pool columns",78,98.5,99),
        ("night_native_empty_insertion","routing-native-empty-insertion","native_empty_insertion_pairs","ordered native empty insertion",-2,35,94))
    haskey(proof,stagekey) || continue
    let
    stage=proof[stagekey]
    for (key,basename,title,caption) in (
            (nativekey,prefix*"-native","Actual prepared routing: $description",
             nativekey=="native_membership_pairs" ? "1,000 native route checks per row; independently valid full PDPTW inputs. A constant 432-byte/8-object measurement scaffold remains." :
             nativekey=="native_empty_insertion_pairs" ? "One warmed batch of 1,000 calls per request; original two-node summaries and full PDPTW inputs. Constant 656-byte/11-object measurement scaffold retained; generic matrix-view controls unchanged." :
                "100 nonduplicate complete admissions per row; independently prepared pools. Every ordered column, retained solution and membership workspace state matches."),
            ("fixed_original_lr101",prefix*"-fixed-lr101","Actual original LR101: $description",
             "4,096 steps per lane × 2 workers; three seeds per configuration. Every exact path is independently warmed; compilation/recompilation are zero."))
        local rows,labels,n,figure,axis,bytes,objects
        rows=stage[key]["records"]
        all(r->r["original_oracle"]=="passed",rows) || error("Unqualified membership pairs")
        labels=key==nativekey ? ["$(r["requests"]) requests"*(haskey(r,"pool_cap") ? " / pool $(r["pool_cap"])" : "")*(haskey(r,"kind") ? " / "*replace(r["kind"],"_"=>" ") : "")*" / seed $(r["seed"])" for r in rows] :
            [replace(r["method"],"rp_"=>"","_"=>" ")*" / seed $(r["seed"])" for r in rows]
        n=length(rows);figure=Figure(size=(1600,max(650,38n+180)))
        axis=Axis(figure[1,1],title=title,xlabel="Remaining allocation (% of same-cohort previous source)",
            ylabel="Paired fixed workload",yticks=(1:n,labels))
        bytes=[100r["after"]["bytes"]/r["before"]["bytes"] for r in rows]
        objects=[100r["after"]["objects"]/r["before"]["objects"] for r in rows]
        vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
        scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=12,label="Allocated Julia bytes")
        scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=12,label="Allocated Julia objects")
        xlims!(axis,key==nativekey ? native_minimum : fixed_minimum,stagekey=="night_owned_pool_columns" ? 100.2 : 103);ylims!(axis,.5,n+.5)
        Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
        Label(figure[3,1],caption*"\nAll original oracles passed; complete LR101 trace/routes/RNG work matches. Concurrent timing; no controlled speed or quality claim.",fontsize=13)
        export_figure(figure,basename)
    end
    rows=stage["exact_warm_meta"]["records"]
    all(r->r["all_lane_and_coordination_work_matches"],rows) || error("Unqualified exact-warm cooperation")
    methods=sort!(unique(r["method"] for r in rows));n=length(methods)
    figure=Figure(size=(1600,max(750,36n+200)))
    axis=Axis(figure[1,1],title="Actual MetaStrategist cooperation: exact-warm $description",
        xlabel="Remaining allocation (% of same-cohort previous source)",ylabel="Configuration",
        yticks=(1:n,[replace(id,"rp_"=>"","_"=>" ") for id in methods]))
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
    for (metric,color,marker,offset,label) in (("bytes",:dodgerblue3,:circle,-.12,"Allocated Julia bytes"),
            ("objects",:purple3,:utriangle,.12,"Allocated Julia objects"))
        values=[[100r["after"][metric]/r["before"][metric] for r in rows if r["method"]==id] for id in methods]
        means=[sum(v)/length(v) for v in values]
        for (i,v) in enumerate(values)
            lines!(axis,[minimum(v),maximum(v)],fill(i+offset,2);color,linewidth=2)
        end
        scatter!(axis,means,(1:n).+offset;color,marker,markersize=12,label)
    end
    xlims!(axis,meta_minimum,stagekey=="night_owned_pool_columns" ? 100.1 : 101);ylims!(axis,.5,n+.5)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"48 paired paths: 16 configurations × 3 seeds; 8 actual cooperative episodes × 2 workers, including simplex/IPX/HIPO masters.\nMarkers: mean paired ratio; bars: full seed range. Complete lane work and substantive coordination match; zero compilation/recompilation. All warm attempts retained.\nOriginal validator retained. Concurrent timing; no controlled speed or solution-quality claim.",fontsize=13)
    export_figure(figure,prefix*"-exact-warm-meta")
    end
end

for (stagekey,recordkey,basename,title,caption,xminimum) in (
        ("night_combined_routing_source_lr101","qualification","routing-combined-source-fixed-lr101",
         "Original LR101: combined overnight routing-source changes",
         "12 paired paths: 4 configurations × 3 seeds; 4,096 steps per lane × 2 workers. Historical routing source from the start of the night; all other current application and package sources shared.",0),
        ("night_owned_best_quality","fixed_original_lr101_meta","routing-owned-best-quality-original-lr101-meta",
         "Original LR101 cooperation: owned coordinator quality snapshots",
         "12 paired paths: 4 configurations × 3 seeds; 8 actual cooperative episodes × 32 steps × 2 workers. Four small byte increases retained; all object counts decrease.",99.8))
    haskey(proof,stagekey) && haskey(proof[stagekey],recordkey) || continue
    let
    rows=proof[stagekey][recordkey]["records"]
    all(r->r["original_oracle"]=="passed" && all(r[side]["compilation_seconds"]==r[side]["recompilation_seconds"]==0 for side in ("before","after")),rows) ||
        error("Unqualified original-instance allocation comparison")
    methods=sort!(unique(r["method"] for r in rows));n=length(methods)
    figure=Figure(size=(1700,650))
    axis=Axis(figure[1,1];title,xlabel="Remaining allocation (% of same-cohort historical source)",ylabel="Configuration",
        yticks=(1:n,[replace(id,"rp_"=>"","_"=>" ") for id in methods]))
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed historical-source reference")
    limits=Float64[]
    for (metric,color,marker,offset,label) in (("bytes",:dodgerblue3,:circle,-.12,"Allocated Julia bytes"),
            ("objects",:purple3,:utriangle,.12,"Allocated Julia objects"))
        values=[[100r["after"][metric]/r["before"][metric] for r in rows if r["method"]==id] for id in methods]
        append!(limits,Iterators.flatten(values))
        for (i,v) in enumerate(values)
            lines!(axis,[minimum(v),maximum(v)],fill(i+offset,2);color,linewidth=2)
        end
        scatter!(axis,[sum(v)/length(v) for v in values],(1:n).+offset;color,marker,markersize=14,label)
    end
    xlims!(axis,min(xminimum,minimum(limits)-.02),max(xminimum==0 ? 103 : 100.1,maximum(limits)+.02));ylims!(axis,.5,n+.5)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],caption*"\nMarkers: mean paired ratio; bars: full seed range. Complete substantive trace/routes/RNG work and original validators match; zero compilation/recompilation.\nFrozen V7 integration remains provisional for a separate generic QUBO constructor regression. Concurrent timing; no controlled speed or quality claim.",fontsize=13)
    export_figure(figure,basename)
    end
end

if haskey(proof,"night_owned_range_cache")
    let
    rows=proof["night_owned_range_cache"]["native_cache_sequences"]["records"]
    all(r->r["oracle"]=="passed",rows) || error("Unqualified range cache figure")
    labels=[r["case"]=="native_growth" ? "Growth from 2 to 80 nodes / 40 updates" :
        r["case"]=="fallback_reuse" ? "Long-route scan fallback / 3,000 updates" :
        "Growth then stable reuse / 1,000 updates" for r in rows]
    n=length(rows);figure=Figure(size=(1600,650))
    axis=Axis(figure[1,1],title="Actual range-cache sequences: bounded private storage",
        xlabel="Remaining allocation (% of previous source)",ylabel="Ordered segment workload",yticks=(1:n,labels))
    bytes=[100r["after"]["bytes"]/r["before"]["bytes"] for r in rows]
    objects=[100r["after"]["objects"]/r["before"]["objects"] for r in rows]
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
    scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=13,label="Allocated Julia bytes")
    scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=13,label="Allocated Julia objects")
    xlims!(axis,-2,106);ylims!(axis,.5,n+.5)
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"180,138 exact original segment comparisons; cache creation and growing private storage included. Stable reuse is unchanged.\nNo original LR101 cache allocation gain: all nine full paired paths preserve bytes/objects exactly. No controlled speed or quality claim.",fontsize=13)
    export_figure(figure,"routing-owned-range-cache-sequences")
    end
end

if haskey(proof,"night_owned_snapshots")
    let
    stage=proof["night_owned_snapshots"]
    for (key,name,title,xminimum) in (
            ("native_snapshots","routing-owned-snapshots-kernels","Actual route snapshots: independently owned retained outputs",0),
            ("fixed_original_lr101","routing-owned-snapshots-fixed-lr101","Original LR101: primitive snapshots at identical search work",40))
        rows=stage[key]["records"]
        all(r->r["original_oracle"]=="passed",rows) || error("Unqualified route snapshot figure")
        native=key=="native_snapshots"
        native || all(r->r["full_trace_routes_rng_match"],rows) || error("Original LR101 work differs")
        rows=sort(rows;by=r->native ? (string(r["requests"]),r["seed"]) : (r["method"],r["seed"]))
        labels=[native ? "$(r["requests"]) requests / seed $(r["seed"])" :
            "$(replace(r["method"],"rp_"=>"","_"=>" ")) / seed $(r["seed"])" for r in rows]
        bytes=[native ? 100r["after_bytes"]/r["before_bytes"] : 100r["after"]["bytes"]/r["before"]["bytes"] for r in rows]
        objects=[native ? 100r["after_objects"]/r["before_objects"] : 100r["after"]["objects"]/r["before"]["objects"] for r in rows]
        n=length(rows);figure=Figure(size=(1650,780))
        axis=Axis(figure[1,1];title,xlabel="Remaining allocation (% of previous source)",
            ylabel=native ? "Original PDPTW fixture" : "Configuration / seed",yticks=(1:n,labels))
        vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
        scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=12,label="Allocated Julia bytes")
        scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=12,label="Allocated Julia objects")
        xlims!(axis,xminimum,105);ylims!(axis,.4,n+.6)
        Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
        caption=native ? "Nine original-valid fixtures; five batches of 1,000 warmed snapshots. Independent output rows and original input remain intact." :
            "Nine paired original LR101 paths; 4,096 steps per lane, 2 private lanes. Complete trace/routes/next RNG match; exact paths fully warmed."
        Label(figure[3,1],caption*"\nNo observed compilation/recompilation. Preparation and final validation excluded; no controlled speed or quality claim.",fontsize=13)
        export_figure(figure,name)
    end
    end
end

if haskey(proof,"night_owned_trace")
    let
    stage=proof["night_owned_trace"]
    rows=stage["native_update_kernels"]["records"]
    all(r->r["oracle"]=="passed",rows) || error("Unqualified trace update figure")
    figure=Figure(size=(1650,720))
    labels=[replace(r["mode"],"_"=>" ") for r in rows]
    for (column,key,title) in ((1,"bytes","Allocated Julia bytes"),(2,"objects","Allocated Julia objects"))
        prior=[r["before"][key] for r in rows];owned=[r["after"][key] for r in rows]
        axis=Axis(figure[1,column];title,xlabel="Per 100,000 warm operations",ylabel=column==1 ? "Actual bookkeeping workload" : "",
            yticks=(1:length(rows),labels),yticklabelsvisible=column==1)
        for i in eachindex(rows)
            lines!(axis,[prior[i],owned[i]],[i,i];color=:gray65,linestyle=:dash,linewidth=1.5)
        end
        scatter!(axis,prior,(1:length(rows)).-.10;color=:gray35,marker=:rect,markersize=13,label="Ordinary dictionary reference")
        scatter!(axis,owned,(1:length(rows)).+.10;color=:dodgerblue3,marker=:circle,markersize=13,label="Private numeric trace")
        xlims!(axis,-.03maximum(vcat(prior,[1])),1.05maximum(vcat(prior,[1])))
        ylims!(axis,.5,length(rows)+.5)
        column==1 && Legend(figure[2,1:2],axis;orientation=:horizontal,framevisible=false)
    end
    Label(figure[0,1:2],"Actual counter updates: complete ordinary-dictionary arithmetic";fontsize=23)
    Label(figure[3,1:2],"Independent native observations; every complete value matches, including ordered floating additions. Preparation and snapshots excluded.\nMarkers are offset to preserve coincident zero references. Wider/custom values retain the original path; this is not a whole-solver zero-allocation claim.",fontsize=13)
    colgap!(figure.layout,70)
    export_figure(figure,"routing-owned-trace-update-kernels")

    rows=stage["fixed_original_lr101"]["records"]
    all(r->r["original_oracle"]=="passed"&&r["full_trace_routes_rng_match"],rows) || error("Unqualified fixed LR101 figure")
    rows=sort(rows;by=r->(r["method"],r["steps_per_lane"],r["seed"]))
    n=length(rows);figure=Figure(size=(1650,max(780,28n+200)))
    labels=["$(replace(r["method"],"rp_"=>"","_"=>" ")) / $(r["steps_per_lane"]) / seed $(r["seed"])" for r in rows]
    axis=Axis(figure[1,1],title="Original LR101: numeric traces at identical search work",
        xlabel="Remaining allocation (% of previous ordinary dictionary source)",ylabel="Configuration / steps per lane / seed",
        yticks=(1:n,labels))
    bytes=[100r["after"]["bytes"]/r["before"]["bytes"] for r in rows]
    objects=[100r["after"]["objects"]/r["before"]["objects"] for r in rows]
    vlines!(axis,[100];color=:black,linestyle=:dash,linewidth=2,label="Fixed previous-source reference")
    scatter!(axis,bytes,(1:n).-.12;color=:dodgerblue3,marker=:circle,markersize=11,label="Allocated Julia bytes")
    scatter!(axis,objects,(1:n).+.12;color=:purple3,marker=:utriangle,markersize=11,label="Allocated Julia objects")
    xlims!(axis,0,max(105,maximum(vcat(bytes,objects))+5))
    Legend(figure[2,1],axis;orientation=:horizontal,framevisible=false)
    Label(figure[3,1],"27 paired original-instance observations; 2 private lanes; identical starts, seeds and steps. Complete trace, route and next RNG values match.\nEach exact path is fully warmed; no observed compilation/recompilation. Preparation and final observations excluded; no controlled speed or quality claim.",fontsize=13)
    export_figure(figure,"routing-owned-trace-fixed-lr101")
    end
end

for (key,basename,title,legend,byte_powers,object_powers) in (
        ("night_owned_relocation","pair-relocation-owned-incumbent",
         "Pair relocation: one independent incumbent after selection","Owned deferred incumbent",11:19,5:13),
        ("night_surviving_relocation","pair-relocation-surviving-incumbent",
         "Pair relocation: copy only independently owned surviving routes","Surviving route snapshot",9:16,4:10))
    haskey(proof,key) || continue
    let
    rows=proof[key]["larger_fixtures"]["records"]
    all(r->r["original_oracle"]=="passed"&&r["retained_routes_and_examined_match"],rows) ||
        error("Relocation figure requires matching original-model work")
    rows=sort(rows;by=r->(r["requests"],r["seed"]))
    figure=Figure(size=(1650,850));colgap!(figure.layout,60)
    labels=["$(r["requests"]) requests / seed $(r["seed"])" for r in rows]
    for (column,field,axis_title,powers) in ((1,"bytes_per_call","Allocated Julia bytes",byte_powers),
            (2,"objects_per_call","Allocated Julia objects",object_powers))
        prior=[r["before"][field] for r in rows];owned=[r["after"][field] for r in rows]
        axis=Axis(figure[1,column],title=axis_title,xlabel="Per warm pair relocation (log₂ scale)",
            ylabel=column==1 ? "Original PDPTW fixture" : "",xscale=log2,
            yticks=(1:length(rows),labels),yticklabelsvisible=column==1,
            xticks=(2.0 .^ powers,string.(2 .^ powers)))
        for i in eachindex(rows)
            lines!(axis,[prior[i],owned[i]],[i,i];color=:gray65,linestyle=:dash,linewidth=1.5)
        end
        scatter!(axis,prior,1:length(rows);color=:gray35,marker=:rect,markersize=13,label="Previous source reference")
        scatter!(axis,owned,1:length(rows);color=:dodgerblue3,marker=:circle,markersize=13,label=legend)
        xlims!(axis,2.0^first(powers),2.0^last(powers));ylims!(axis,.4,length(rows)+.6)
        column==1 && Legend(figure[2,1:2],axis;orientation=:horizontal,framevisible=false)
    end
    colgap!(figure.layout,70)
    Label(figure[0,1:2],title;fontsize=23)
    Label(figure[3,1:2],"Five batches of eight calls; exact historical routes, examined candidates and complete checksums match.\nAll original PDPTW validators pass. Warm workspace scope; concurrent timing is not a controlled speedup.",fontsize=13)
    export_figure(figure,basename)
    end
end

end

if haskey(proof,"night_reserved_cohort_timing")
    let
    stage=proof["night_reserved_cohort_timing"]
    stage["complete"] && stage["non_controlled_dependency_graph_matches"] ||
        error("Unqualified reserved timing cohort")
    rows=stage["groups"]
    all(r->r["original_work_matches"],rows) || error("Original work differs")
    methods=["rp_vnd_greedy","rp_alns_route_regret2","rp_aco_regret2","rp_alns_random_regret2",
        "rp_meta_adaptive_late","rp_meta_diversity_tabu","rp_meta_pool_ipx_late","rp_meta_pool_mip_tabu"]
    labels=["VND / greedy","Route ALNS / regret-2","ACO / regret-2","Random ALNS / regret-2",
        "Meta / adaptive / late","Meta / diversity / tabu","Meta / pooled IPX / late","Meta / pooled MIP / tabu"]
    for (metric,title,basename) in (("seconds","Steady elapsed time","routing-cohort-reserved-time"),
            ("bytes","Allocated Julia bytes","routing-cohort-reserved-bytes"),
            ("objects","Allocated Julia objects","routing-cohort-reserved-objects"))
        requested===nothing || basename in requested || continue
        figure=Figure(size=(2050,980))
        for (column,width) in enumerate((1,2,4,8))
            axis=Axis(figure[1,column],title="$width "* (width==1 ? "worker" : "workers"),
                xlabel="Remaining cost (% of early optimized cohort)",
                ylabel=column==1 ? "Configuration" : "",yticks=(1:8,labels),
                yticklabelsvisible=column==1,yreversed=true)
            vlines!(axis,[100.];color=:black,linestyle=:dash,linewidth=2)
            limits=[100.]
            for (position,method) in enumerate(methods), (seed,marker,offset) in
                    ((41,:circle,-.22),(42,:utriangle,0.),(43,:diamond,.22))
                r=only(filter(r->r["workers"]==width && r["method"]==method && r["seed"]==seed,rows))
                metric_stats=r["metrics"][metric]
                ratio=metric_stats["median_remaining_percent"]
                spread=metric_stats["paired_remaining_percent"]
                lo,hi=spread["minimum"],spread["maximum"]
                color=startswith(method,"rp_meta") ? :purple3 : :dodgerblue3
                y=position+offset
                lines!(axis,[lo,hi],[y,y];color,linewidth=2)
                scatter!(axis,[ratio],[y];color,marker,markersize=15,strokecolor=:white,strokewidth=.8)
                append!(limits,(lo,hi,ratio))
            end
            xlims!(axis,0,max(108.,maximum(limits)*1.07))
            ylims!(axis,.4,8.6)
        end
        elements=Any[
            MarkerElement(color=:black,marker=:circle,markersize=12),
            MarkerElement(color=:black,marker=:utriangle,markersize=12),
            MarkerElement(color=:black,marker=:diamond,markersize=12),
            LineElement(color=:dodgerblue3,linewidth=3),
            LineElement(color=:purple3,linewidth=3),
            LineElement(color=:black,linestyle=:dash,linewidth=2)]
        Legend(figure[2,1:4],elements,["Seed 41","Seed 42","Seed 43","Private search lanes","MetaStrategist lifecycle","Fixed reference: 100%"];
            orientation=:horizontal,framevisible=false)
        Label(figure[0,1:4],"Original LR101: complete qualified cohort — $title";fontsize=25)
        Label(figure[3,1:4],"Markers: ratio of per-seed medians; bars: all 10 paired sample ratios (two order-reversed process rounds × five samples). Lower is better; no outliers removed.\nEach width has its own fixed original work and roles; 1,920 original-valid observations and complete trace/routes/RNG checks. Widths are not a strong-scaling or solution-quality comparison.\nEight reserved physical P cores at most; single BLAS/GC/native HiGHS thread. Independent E-core media work may share memory and power; desktop background remains. Reference marks and all ranges stay visible.";
            fontsize=14)
        export_figure(figure,basename)
    end
    if requested===nothing || "routing-cohort-reserved-cpu-gc" in requested
        figure=Figure(size=(2050,1320))
        for (column,width) in enumerate((1,2,4,8)), (row,key,title) in
                ((1,"mean_active_cpus","Mean active CPU equivalents"),(2,"gc_percent","Measured GC share (%)"))
            axis=Axis(figure[row,column],title="$width "* (width==1 ? "worker" : "workers")*": "*title,
                xlabel=row==1 ? "Process CPU seconds / elapsed seconds" : "GC seconds / elapsed seconds × 100",
                ylabel=column==1 ? "Configuration" : "",yticks=(1:8,labels),
                yticklabelsvisible=column==1,yreversed=true)
            limits=Float64[]
            row==1 && vlines!(axis,[Float64(width)];color=:black,linestyle=:dash,linewidth=2)
            for (position,method) in enumerate(methods), (side,color,marker,offset) in
                    (("before",:gray40,:rect,-.13),("after",:dodgerblue3,:circle,.13))
                selected=filter(r->r["workers"]==width && r["method"]==method,rows)
                stats=[row==1 ? r["metrics"][key][side] : r["runtime"][side][key] for r in selected]
                lo,hi=minimum(s["minimum"] for s in stats),maximum(s["maximum"] for s in stats)
                middle=median([s["median"] for s in stats])
                y=position+offset
                lines!(axis,[lo,hi],[y,y];color,linewidth=2)
                scatter!(axis,[middle],[y];color,marker,markersize=13)
                append!(limits,(lo,hi))
            end
            upper=row==1 ? max(width*1.08,maximum(limits)*1.07) : max(.01,maximum(limits)*1.12)
            xlims!(axis,-.025upper,upper) # Keep zero-GC markers fully visible.
            ylims!(axis,.4,8.6)
        end
        Legend(figure[3,1:4],Any[
            Any[MarkerElement(color=:gray40,marker=:rect,markersize=12),LineElement(color=:gray40,linewidth=2)],
            Any[MarkerElement(color=:dodgerblue3,marker=:circle,markersize=12),LineElement(color=:dodgerblue3,linewidth=2)],
            LineElement(color=:black,linestyle=:dash,linewidth=2)],
            ["Early optimized cohort","Final qualified cohort","Allocated worker capacity (top row)"];
            orientation=:horizontal,framevisible=false)
        Label(figure[0,1:4],"Original LR101: CPU use and GC during identical bounded work";fontsize=25)
        Label(figure[4,1:4],"Markers: median of the three seed medians; bars: complete observation range. All 30 attempts per side/configuration/width retained.\nPure lanes execute 1,024 steps; MetaStrategist executes eight finite episodes of 32 steps per lane with serial barriers, exchange and a single-threaded native master.\nFinite heterogeneous work can leave lanes waiting; this is not a sustained saturation test. GC shares cover measured operations only; the explicit pre-batch collection is excluded.\nReserved physical P cores; independent E-core media and desktop activity can still share hardware resources. CPU accounting includes runtime/GC/native work, not only useful search.";
            fontsize=14)
        export_figure(figure,"routing-cohort-reserved-cpu-gc")
    end
    end
end
