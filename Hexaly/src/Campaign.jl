module ReproductionCampaign
using TOML,SHA,Dates,Statistics,Random
import HiGHS
using ..ReproductionProblems,..ReproductionSelections,..ReproductionSolvers
using ..ReproductionORTools,..ReproductionHexaly
export run_campaign,summarize,METHODS,MIP_FAMILIES
const MIP_FAMILIES=(:bpp,:bppc,:vbp,:salbp,:rcpsp,:jssp,:fjsp,:aircraft_landing)
const METHODS=vcat(["cbls_naive","cbls_direct","cbls_icn","cbls_icn_fused","strategies",
    "hybrid_highs","metastrategist","metastrategist_mixed","highs","ortools","ghost","ghost_icn","hexaly"],
    ["strategy:"*p for p in POLICIES],ReproductionSolvers.StrategyPanel.methods(),
    ["cbls-panel","hybrid-panel","meta-panel","qubo-panel","extended-panel"])
digest(path)=bytes2hex(sha256(read(path)))
function code_hash(root)
    paths=sort!(vcat([joinpath(dir,file) for (dir,_,files)in walkdir(joinpath(root,"Hexaly"))
        for file in files if (endswith(file,".jl") || endswith(file,".py") || endswith(file,".toml")) &&
        !("data" in splitpath(relpath(dir,joinpath(root,"Hexaly")))) && !("results" in splitpath(relpath(dir,joinpath(root,"Hexaly"))))],
        [joinpath(root,"LiLim",p) for p in ("config/strategy-variants.toml","resources/icn-pdptw-witnesses.toml",
            "config/workspace-cohort.toml","config/hexaly-benchmark-catalog.toml","src/NativeSolvers.jl",
            "src/PlatformResources.jl","src/SearchPolicies.jl","src/SolverArtifacts.jl",
            "config/strategy-panel.toml","src/StrategyPanel.jl","src/QUBOGuidance.jl","src/ROFragments.jl",
            "src/PanelPlotStyles.jl")]))
    bytes2hex(sha256(join([relpath(p,root)*":"*digest(p) for p in paths],"\n")))
end
function status_result(p,values,status;bound=NaN,seconds=NaN)
    checked=isempty(values) ? nothing : validate(p,values)
    checked===nothing || checked.valid || error("Exported solution fails original validator")
    Dict{String,Any}("status"=>checked===nothing ? "no_feasible_solution" : "feasible","solver_status"=>string(status),
        "values"=>values,"objective"=>checked===nothing ? Float64[] : Float64.(collect(checked.objective)),
        "bound"=>bound,"seconds"=>seconds,"trajectory"=>Dict{String,Any}[],
        "trajectory_status"=>"native_endpoint_only_time_to_target_unobserved")
end
function solve(root,row,p,path,method;seconds,threads,seed,max_cells)
    if method=="highs"
        p.family in MIP_FAMILIES || return Dict("status"=>"unsupported_model")
        t=time_ns();r=solve_mip(p,HiGHS.Optimizer;seconds,threads,max_cells)
        return status_result(p,r.values,r.status;bound=r.bound,seconds=(time_ns()-t)/1e9)
    elseif method=="ortools"
        ReproductionORTools.NativeSolvers.resolve_ortools(ReproductionORTools.NativeSolvers.default_python(root);root)
        p.family in MIP_FAMILIES || return Dict("status"=>"unsupported_model","reason"=>"classical_CP_SAT_adapter_has_no_routing_model_use_LiLim_for_PDPTW")
        r=solve_ortools(p;seconds,threads,seed,max_cells)
        return status_result(p,r["values"],r["status"];bound=r["bound"],seconds=r["seconds"])
    elseif method in ("ghost","ghost_icn")
        ReproductionORTools.NativeSolvers.resolve_ghost(;root)
        r=solve_ghost(p;seconds,seed,kind=method=="ghost" ? :direct : :icn_fused)
        result=status_result(p,r.values,r.status);result["seed_policy"]=r.seed_policy
        result["threads"]=1;return result
    elseif method=="hexaly"
        ReproductionHexaly.NativeSolvers.resolve_hexaly(get(ENV,"HEXALY_EXECUTABLE","hexaly"))
        p.family in keys(TEMPLATES) || return Dict("status"=>"unsupported_model","reason"=>"vendor_model_and_exporter_not_qualified")
        r=solve_hexaly(root,p,path;seconds,threads,seed,max_cells)
        return r
    elseif method in ("hybrid_highs","metastrategist_mixed")
        p.family in MIP_FAMILIES || return Dict("status"=>"unsupported_model")
    end
    panel=haskey(ReproductionSolvers.StrategyPanel.CATALOG,method)
    if panel
        recipes=ReproductionSolvers.StrategyPanel.allocation(method,threads)
        any(lane->lane.bridged,recipes) && return Dict("status"=>"unsupported_model","reason"=>"qualified_XCSP3_bridge_scope_is_LiLim_only")
        any(lane->lane.hybrid,recipes) && !(p.family in MIP_FAMILIES) &&
            return Dict("status"=>"unsupported_model","reason"=>"no_qualified_original_integer_fragment")
        workers=[(;kind=l.backend==:icn_fused_all ? :icn_fused : l.backend,policy=l.policy,overrides=l.overrides,
            hybrid=l.hybrid,max_cells,max_visits=l.max_visits,repair_every=l.repair_every,
            fragment_seconds=l.fragment_seconds,repair_fraction=l.repair_fraction,repair_mode=l.repair_mode,
            lp_solver=l.lp_solver,mip_lp_solver=l.mip_lp_solver,radius=l.radius,fragment_selection=l.fragment_selection,
            guide_mode=l.guide_mode,guide_depth=l.guide_depth,guide_every=l.guide_every,
            guide_exploration=l.guide_exploration,guide_fraction=l.guide_fraction,id=row["id"],
            instance_sha256=row["sha256"],warm_start=true) for l in recipes]
    else
    policy=startswith(method,"strategy:") ? method[10:end] : "greedy_guided"
    kind=method=="cbls_naive" ? :naive : method=="cbls_direct" ? :direct : method=="cbls_icn" ? :icn : :icn_fused
    phases=startswith(method,"metastrategist") ? ["late_400","tabu_short","exhaustion_partial","universal_best"] : [policy]
    # Select only actual existing profile IDs; each worker owns its solver, ICN and buffers.
    phases=filter(p->p in POLICIES,phases);isempty(phases) && error("Missing portfolio profiles")
    workers=[(;kind=method=="metastrategist_mixed" && mod1(i,4)==3 ? :direct : kind,
        policy=phases[mod1(i,length(phases))],hybrid=method=="hybrid_highs" || (method=="metastrategist_mixed" && mod1(i,4)==2),max_cells) for i in 1:threads]
    end
    prepared_at=time_ns()
    lanes=[prepare_cbls(p;w...,seed=seed+i-1) for (i,w)in enumerate(workers)]
    preparation=(time_ns()-prepared_at)/1e9
    # Prime the actual policy kernel; reconstruct state before the timed search.
    for lane in lanes;Base.invokelatest(search!,lane;seconds=.01,max_steps=1);end
    warm_at=time_ns();lanes=[prepare_cbls(p;w...,seed=seed+i-1) for(i,w)in enumerate(workers)]
    preparation+=(time_ns()-warm_at)/1e9
    outcomes=Vector{Any}(undef,threads)
    if startswith(method,"metastrategist") || (panel && ReproductionSolvers.StrategyPanel.CATALOG[method].category==:meta)
        outcomes=portfolio(p;workers,seconds,seed,prepared_lanes=lanes)
    else
        Threads.@threads :static for i in eachindex(lanes)
            Random.seed!(lanes[i].seed)
            outcomes[i]=Base.invokelatest(search!,lanes[i];seconds)
        end
    end
    feasible=filter(r->r["status"]=="feasible",outcomes)
    result=isempty(feasible) ? Dict{String,Any}("status"=>"no_feasible_solution","values"=>Int[],"objective"=>Float64[],"trajectory"=>[]) :
        deepcopy(argmin(r->Tuple(r["objective"]),feasible))
    events=sort!(vcat([get(r,"trajectory",[]) for r in outcomes]...);by=r->r["seconds"])
    trajectory=Dict{String,Any}[];best=nothing
    for row in events
        q=Tuple(row["objective"])
        if best===nothing || q<best;push!(trajectory,row);best=q;end
    end
    result["trajectory"]=trajectory;result["lanes"]=outcomes
    result["preparation_seconds"]=preparation;result["trajectory_status"]="original_validated_incumbents"
    result["threads"]=threads;result
    panel && (result["strategy_panel"]=ReproductionSolvers.StrategyPanel.metadata(method,threads))
    result
end
function save(path,value)
    temporary=path*".partial"
    ispath(temporary) && error("Unsealed output exists and was preserved: $temporary")
    open(io->TOML.print(io,value;sorted=true),temporary,"w");mv(temporary,path)
end
function validate_trajectory(p,result)
    previous=nothing;time=-Inf
    for event in get(result,"trajectory",[])
        checked=validate(p,event["values"]);q=Tuple(event["objective"])
        checked.valid && Float64.(collect(checked.objective))≈Float64.(event["objective"]) || error("Trajectory fails original validation")
        0<=event["seconds"] && event["seconds"]>=time || error("Trajectory time is not ordered")
        event["seconds"]<=get(result,"budget_seconds",Inf) || error("Post-budget incumbent cannot be exported")
        previous===nothing || q<previous || error("Trajectory is not a strict incumbent sequence")
        previous=q;time=event["seconds"]
    end
end
function run_campaign(root,manifest;ids,methods,seconds,threads,seeds,output,resume=false,max_cells=250_000)
    threads>=1 && threads<=Threads.nthreads() || error("Julia thread count is smaller than requested width")
    seconds>0 && isfinite(seconds) || error("Positive finite budget required")
    all(id->id in getindex.(manifest["instances"],"id"),ids) || error("Unknown instance ID")
    all(m->m in METHODS,methods) || error("Unknown method")
    expanded=ReproductionSolvers.StrategyPanel.expand(vcat(filter(!=("strategies"),methods),"strategies" in methods ? ["strategy:"*p for p in POLICIES] : String[]))
    allunique(expanded) || error("Duplicate methods after strategy expansion")
    rows=filter(r->r["id"] in ids,manifest["instances"])
    # Fail before solving if an original instance has changed.
    for row in rows;load_instance(root,row);end
    identity=Dict("schema"=>"discrete-reproduction-campaign/1","instances"=>ids,"methods"=>expanded,
        "seconds"=>seconds,"threads"=>threads,"seeds"=>seeds,"max_cells"=>max_cells,
        "source_sha256"=>code_hash(root),"instance_sha256"=>Dict(r["id"]=>r["sha256"] for r in rows),
        "qubo_guides"=>ReproductionSolvers.QUBOGuidance.input_manifest(ids),
        "strategy_panel"=>Dict(m=>ReproductionSolvers.StrategyPanel.metadata(m,threads) for m in expanded
            if haskey(ReproductionSolvers.StrategyPanel.CATALOG,m)),
        "environment_sha256"=>digest(joinpath(dirname(Base.active_project()),"Manifest.toml")),"selection_rows"=>rows,
        "host"=>Dict("julia"=>string(VERSION),"os"=>string(Sys.KERNEL),"architecture"=>string(Sys.ARCH),
            "logical_cpus"=>Sys.CPU_THREADS,"cpu_models"=>unique([c.model for c in Sys.cpu_info()]),
            "ram_gib"=>Sys.total_memory()/2.0^30,"allowed_cpus"=>ReproductionSolvers.PlatformResources.allowed_cpus(),
            "blas_threads"=>1,"gc_threads_requested"=>1))
    manifest_path=joinpath(output,"manifest.toml")
    if ispath(output)
        resume && isfile(manifest_path) && TOML.parsefile(manifest_path)["identity"]==identity || error("Existing campaign differs and was preserved")
    else
        mkpath(joinpath(output,"trials"));save(manifest_path,Dict("identity"=>identity,"complete"=>false))
    end
    for row in rows,method in expanded,seed in seeds
        ReproductionSolvers.QUBOGuidance.input_manifest(ids)==identity["qubo_guides"] ||
            error("QUBO guide inputs changed; preserve sealed trials and use a new cohort")
        key=row["id"]*"--"*replace(method,":"=>"-")*"--"*string(seed)
        all(c->isletter(c)||isdigit(c)||c in ('-','_','.'),key) || error("Unsafe trial ID")
        path=joinpath(output,"trials",key*".toml");seal=path*".sha256"
        if isfile(path)
            isfile(seal) && strip(read(seal,String))==digest(path) || error("Trial seal missing/mismatched; existing output preserved")
            continue
        end
        loaded=load_instance(root,row);started=time_ns()
        result=try
            Base.invokelatest(solve,root,row,loaded.p,loaded.path,method;seconds,threads,seed,max_cells)
        catch e
            if e isa ReproductionORTools.NativeSolvers.UnavailableSolver || e isa ReproductionHexaly.NativeSolvers.UnavailableSolver
                Dict{String,Any}("status"=>"skipped_unavailable_solver","reason"=>e.reason)
            elseif e isa ArgumentError && (occursin("size cap",e.msg) || occursin("model-size cap",e.msg))
                Dict{String,Any}("status"=>"unsupported_model","reason"=>"bounded_model_size_cap")
            elseif e isa ArgumentError && (occursin("exact integer data",e.msg) || occursin("would change",e.msg) || occursin("integer distances only",e.msg))
                Dict{String,Any}("status"=>"unsupported_model","reason"=>"original_model_variant_requires_a_separately_qualified_adapter")
            else
                # No fallback conceals a model/validator error. Native diagnostics may contain secrets.
                Dict{String,Any}("status"=>"failed","reason"=>"model_or_native_qualification_failed","exception_type"=>string(typeof(e)))
            end
        end
        result["trial_id"]=key;result["instance"]=row["id"];result["method"]=method;result["seed"]=seed
        result["scope"]=row["scope"];result["requested_threads"]=threads;result["budget_seconds"]=seconds
        result["end_to_end_seconds"]=(time_ns()-started)/1e9;result["instance_sha256"]=row["sha256"]
        result["reference"]=get(row,"reference",Float64[])
        result["reference_kind"]=get(row,"reference_kind","unavailable")
        if !isempty(get(result,"values",[]))
            validate(loaded.p,result["values"]).valid || error("Trial failed original validation before sealing")
        end
        validate_trajectory(loaded.p,result)
        save(path,result);write(seal,digest(path)*"\n")
        println(key,": ",result["status"])
        if isfile(joinpath(output,"STOP_AFTER_TRIAL"))
            summarize(root,output,manifest);return false
        end
    end
    summarize(root,output,manifest)
    # A complete attempt set may include explicitly skipped/unsupported/failed methods.
    open(io->TOML.print(io,Dict("identity"=>identity,"complete"=>true);sorted=true),manifest_path,"w");true
end
function summarize(root,output,manifest)
    groups=Dict{Tuple{String,String},Vector{Any}}()
    for file in sort(readdir(joinpath(output,"trials");join=true))
        endswith(file,".toml") || continue
        isfile(file*".sha256") && strip(read(file*".sha256",String))==digest(file) || error("Trial seal mismatch")
        r=TOML.parsefile(file);row=only(filter(x->x["id"]==r["instance"],manifest["instances"]));loaded=load_instance(root,row)
        isempty(get(r,"values",[])) || validate(loaded.p,r["values"]).valid || error("Saved solution failed original validator")
        validate_trajectory(loaded.p,r)
        push!(get!(groups,(r["instance"],r["method"]),Any[]),r)
    end
    summaries=Dict{String,Any}[]
    for ((id,method),trials)in sort!(collect(groups);by=first)
        good=filter(r->get(r,"status","")=="feasible",trials)
        row=Dict{String,Any}("instance"=>id,"method"=>method,"trials"=>length(trials),"feasible"=>length(good),
            "success_rate"=>length(good)/length(trials),"statuses"=>[r["status"] for r in trials])
        if !isempty(good)
            objectives=[Float64.(r["objective"]) for r in good];n=length(first(objectives))
            row["best"]=first(sort(objectives;by=Tuple));row["worst"]=last(sort(objectives;by=Tuple))
            row["mean"]=[mean(q[i] for q in objectives) for i in 1:n];row["median"]=[median([q[i] for q in objectives]) for i in 1:n]
            row["std"]=[std([q[i] for q in objectives];corrected=false) for i in 1:n]
            row["spread"]=[maximum(q[i] for q in objectives)-minimum(q[i] for q in objectives) for i in 1:n]
            row["component_min"]=[minimum(q[i] for q in objectives) for i in 1:n]
            row["component_max"]=[maximum(q[i] for q in objectives) for i in 1:n]
            ref=get(first(good),"reference",Float64[]);row["reference"]=ref
            if !isempty(ref)
                row["bks_attained"]=count(r->Tuple(r["objective"])<=Tuple(ref) || all(isapprox.(r["objective"],ref;atol=1e-6,rtol=1e-9)),good)
                row["time_to_target_observed_seconds"]=[minimum(e["seconds"] for e in r["trajectory"] if Tuple(e["objective"])<=Tuple(ref))
                    for r in good if any(e->Tuple(e["objective"])<=Tuple(ref),get(r,"trajectory",[]))]
            end
        end
        push!(summaries,row)
    end
    report=Dict("schema"=>"discrete-reproduction-summary/1","groups"=>summaries,
        "statistical_policy"=>"Best/worst are lexicographic; mean/median/spread are component-wise over feasible trials only. Success rate includes all attempts. Native time-to-target is unobserved without trajectories.")
    open(io->TOML.print(io,report;sorted=true),joinpath(output,"summary.toml"),"w")
    open(joinpath(output,"report.md"),"w") do io
        println(io,"# Discrete local comparison\n\n",report["statistical_policy"],"\n\nNative endpoints do not supply a measured time-to-target. Original-format smoke inputs are not published benchmark replications.\n")
        println(io,"| Instance | Method | Feasible / attempts | Best | Mean | Median | Spread |\n|---|---|---|---|---|---|---|")
        for row in summaries
            println(io,"| $(row["instance"]) | $(row["method"]) | $(row["feasible"]) / $(row["trials"]) | ",
                join(get(row,"best",[]),", ")," | ",join(get(row,"mean",[]),", ")," | ",
                join(get(row,"median",[]),", ")," | ",join(get(row,"spread",[]),", ")," |")
        end
    end
    report
end
end
