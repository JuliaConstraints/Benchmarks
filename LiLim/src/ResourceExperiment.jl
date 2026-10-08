"Equal wall-budget parallel trajectories and executable MetaStrategist portfolios."
module ResourceExperiment
using TOML, SHA, JuMP
using ..Benchmarks, ..Pilot, ..MetaRepair, ..Hybrid, ..ICNScoring
import MetaStrategist as MS

export allocation, run_case, warmup, prepare_portfolio, cpu_seconds

include("PlatformResources.jl")
include("StrategyPanel.jl")
include("StructuredRouting.jl")
const RoutingPanel=StructuredRouting.RoutingPanel
cpu_seconds(id=2)=PlatformResources.cpu_seconds(id)

const METHODS = ("cbls_naive","cbls_icn","cbls_icn_fused_scalar","cbls_icn_fused_all","cbls_direct","hybrid_specialized_icn",
    "hybrid_bridged_icn","highs_native","highs_portfolio","mixed_balanced","mixed_ls_heavy","cbls_mix_strategy",
    Hybrid.SearchPolicies.METHODS...,sort!(collect(keys(Hybrid.SearchPolicies.PORTFOLIOS)))...,StrategyPanel.methods()...,RoutingPanel.methods()...)

"Each entry is one serial search worker, including a serial HiGHS worker."
function allocation(method,threads)
    method in METHODS && threads > 0 || throw(ArgumentError("invalid configuration"))
    if haskey(StrategyPanel.CATALOG,method) || haskey(RoutingPanel.CATALOG,method)
        return [method*"@"*string(threads)*":"*string(i) for i in 1:threads]
    end
    if haskey(Hybrid.SearchPolicies.PORTFOLIOS,method)
        policies = Hybrid.SearchPolicies.PORTFOLIOS[method]
        return [policies[mod1(i,length(policies))] for i in 1:threads]
    elseif method == "highs_native"
        return ["highs_native"]
    elseif method == "highs_portfolio"
        return fill("highs_serial",threads)
    elseif method == "cbls_mix_strategy"
        policies=("cbls_icn","cbls_icn_first","cbls_icn_no_plateau","cbls_icn_sparse_first")
        return [policies[mod1(i,4)] for i in 1:threads]
    elseif startswith(method,"mixed_")
        threads >= 4 || throw(ArgumentError("mixed portfolios require at least four threads"))
        threads % 4 == 0 || throw(ArgumentError("portfolio width must be divisible by four"))
        q = threads ÷ 4
        return method == "mixed_balanced" ?
            vcat(fill("cbls_icn",q),fill("hybrid_specialized_icn",q),
                fill("hybrid_bridged_icn",q),fill("highs_serial",q)) :
            vcat(fill("cbls_icn",2q),fill("hybrid_specialized_icn",q),
                fill("hybrid_bridged_icn",max(0,q-1)),["highs_serial"])
    end
    fill(method,threads)
end

"Resolve the exact lane policy once, outside its search loop."
function panel_worker(worker)
    occursin('@',worker) || return nothing
    id,tail=split(worker,'@';limit=2);width,index=parse.(Int,split(tail,':'))
    StrategyPanel.allocation(id,width)[index]
end
function worker_settings(worker)
    panel=panel_worker(worker)
    if panel!==nothing
        return (;search_policy=panel.policy,policy_overrides=panel.overrides,
            hybrid=panel.hybrid,bridged=panel.bridged,max_visits=panel.max_visits,
            repair_every=panel.repair_every,fragment_seconds=panel.fragment_seconds,repair_fraction=panel.repair_fraction,
            repair_mode=panel.repair_mode,lp_solver=panel.lp_solver,mip_lp_solver=panel.mip_lp_solver,radius=panel.radius,
            fragment_selection=panel.fragment_selection,guide_mode=panel.guide_mode,guide_depth=panel.guide_depth,
            guide_every=panel.guide_every,guide_exploration=panel.guide_exploration,guide_fraction=panel.guide_fraction,
            pair_selection=panel.pair_selection,pair_every=panel.pair_every,warm_start=true)
    end
    variant = get(Hybrid.SearchPolicies.VARIANTS,worker,nothing)
    (; search_policy=variant===nothing ? "legacy" : variant["policy"],
        hybrid=variant===nothing ? startswith(worker,"hybrid") : get(variant,"hybrid",false),
        bridged=variant===nothing ? worker=="hybrid_bridged_icn" : get(variant,"bridged",false),
        pair_selection=worker in ("cbls_icn_first","cbls_icn_sparse_first") ? :first : :best,
        pair_every=worker=="cbls_icn_sparse_first" ? 4 : 1,
        plateau_rejection=worker=="cbls_icn_no_plateau" ? 100 : worker=="cbls_icn_sparse_first" ? 75 : 10)
end

mutable struct ExecutionContext{F}
    invoke::F
    records::Vector{Any}
end
struct ParallelPhase
    workers::Tuple
end
function (phase::ParallelPhase)(context::ExecutionContext)
    # A static thread assignment is part of this diagnostic. Invocation is on
    # Julia thread 1; worker states and counters are owned independently.
    # Learned ICN functions are generated at runtime. A long-lived Julia task
    # can retain the world age from before that generation, so enter the full
    # worker call at the latest world once rather than paying per-score dispatch.
    Threads.@threads :static for i in eachindex(phase.workers)
        context.records[i] = Base.invokelatest(context.invoke, i, phase.workers[i])
    end
    nothing
end

"Use MetaStrategist's real resolution, preparation and execution APIs."
function prepare_portfolio(workers)
    catalog = MS.PhaseCatalog()
    factory = (parameters,context)->ParallelPhase(parameters.workers)
    MS.register_phase!(catalog,MS.PhaseDefinition(:search,:li_lim_parallel,factory;
        version="1",reads=(:instance,),writes=(:incumbents,),requires=(:threads,)))
    profile = MS.StrategyProfile(:li_lim_fixed_resources,"1",Dict(:search=>
        MS.PhaseChoice(:li_lim_parallel,"1";workers=Tuple(workers))))
    ir = MS.resolve_strategy(catalog,profile;roots=(:search,),inputs=(:instance,),capabilities=(:threads,))
    prepared = MS.prepare_strategy(ir;mode=:typed)
    (;prepared,key=ir.semantic_key,snapshot=MS.strategy_snapshot(ir),workers=Tuple(workers))
end

function highs_worker(p,initial,seconds,seed,origin,threads;logpath=nothing)
    elapsed() = (time_ns()-origin)/1e9
    remaining() = max(0.,seconds-elapsed())
    best = deepcopy(initial); quality = validate_solution(p,best).objective
    trajectory = Any[]; rejected = Ref(0); callbacks = Ref(0)
    function consider(routes,source)
        checked = validate_solution(p,routes)
        checked.valid || error("HiGHS incumbent invalid")
        q = checked.objective
        if remaining() > 0 && (q.vehicles,q.distance)<(quality.vehicles,quality.distance)
            best = deepcopy(routes); quality = q
            push!(trajectory,Dict("seconds"=>elapsed(),"vehicles"=>q.vehicles,
                "distance"=>q.distance,"routes"=>deepcopy(routes),"source"=>source))
        end
    end
    trace = Dict{String,Any}("highs_threads_requested"=>threads,"parallel"=>"on")
    if remaining() > 0
        building = time_ns()
        f = Pilot.model(p;threads,seed,seconds=remaining(),logpath)
        trace["build_seconds"] = (time_ns()-building)/1e9
        trace["highs_threads_option"] = get_attribute(f.m,"threads")
        trace["highs_parallel_option"] = get_attribute(f.m,"parallel")
        trace["variables"] = num_variables(f.m)
        Pilot.warmstart!(f,initial)
        Pilot.observe_incumbents!(f,routes->begin
            callbacks[] += 1; consider(routes,"highs_callback")
        end;expired=()->remaining()<=0,rejected=error->(rejected[]+=1))
        if remaining() > 0
            set_time_limit_sec(f.m,remaining())
            routes,phases,solving = Pilot.solve!(f;seconds=remaining())
            trace["phases"] = phases;trace["solve_seconds"] = solving
            routes === nothing || consider(routes,"highs_return")
        end
    end
    trace["callbacks"] = callbacks[];trace["invalid_callback_solutions"] = rejected[]
    trace["trajectory"] = trajectory
    (;routes=best,validation=validate_solution(p,best),trace)
end

"Initialization and model construction are charged once on a shared monotonic clock."
function run_case(path,method,seconds,seed,policy,banks;threads=Threads.nthreads(),id=splitext(basename(path))[1],logpath=nothing,portfolio=nothing,max_episodes=typemax(Int))
    workers = allocation(method,threads)
    portfolio===nothing || portfolio.workers==Tuple(workers) || throw(ArgumentError("prepared portfolio allocation differs"))
    threads <= Threads.nthreads() || throw(ArgumentError("Julia thread pool too small"))
    isfinite(seconds) && seconds > 0 || throw(ArgumentError("positive finite budget required"))
    # A preceding trial has fully joined before this process-global reset.
    # All HiGHS instances in one mixed trial use the same cap of one thread.
    Pilot.HiGHS.Highs_resetGlobalScheduler(1)
    GC.gc()
    search_gc_origin = Base.gc_num().total_time
    origin = time_ns();process_cpu = cpu_seconds()
    elapsed() = (time_ns()-origin)/1e9
    p = read_benchmark(path,:li_lim;id)
    initial = Pilot.insertion(p;starts=policy["insertion_starts"],seed=policy["insertion_seed"])
    initial === nothing && error("no valid common start")
    checked = validate_solution(p,initial); checked.valid || error("invalid common start")
    initial_seconds = elapsed()
    initial_seconds < seconds || error("initialization exceeded budget")
    function invoke(i,worker)
        started = elapsed();tid = Threads.threadid();os_tid=PlatformResources.os_thread_id()
        cpu = cpu_seconds(3)
        # Lane 1 retains the repetition seed. Further lanes deterministically
        # diversify independently, identically in every homogeneous profile.
        lane_seed = seed + 10_000*(i-1)
        panel=panel_worker(worker)
        backend_kind = panel!==nothing ? panel.backend : worker == "cbls_naive" ? :naive : worker == "cbls_direct" ? :direct :
            worker == "cbls_icn_fused_scalar" ? :icn_fused_scalar :
            worker == "cbls_icn_fused_all" ? :icn_fused_all : :icn
        bank_kind = backend_kind in (:icn_fused_scalar,:icn_fused_all) ? :icn : backend_kind
        backend = ICNScoring.clone_backend(banks[bank_kind],backend_kind)
        result = if worker in ("highs_native","highs_serial")
            highs_worker(p,initial,seconds,lane_seed,origin,worker=="highs_native" ? threads : 1;logpath)
        else
            parameters=merge((;max_visits=policy["max_visits"],repair_every=policy["repair_every"],
                fragment_seconds=policy["fragment_seconds"],repair_fraction=policy["repair_fraction"]),worker_settings(worker))
            Hybrid.run_cbls(p,initial;seconds,seed=lane_seed,origin_ns=origin,
                scorer=backend,
                scorer_name="route constraints/2: "*string(backend_kind),
                instance_sha256=bytes2hex(sha256(read(path))),parameters...)
        end
        result.validation.valid || error("invalid worker solution")
        Dict{String,Any}("worker"=>i,"method"=>worker,"seed"=>lane_seed,
            "julia_thread_id"=>tid,"os_thread_id"=>os_tid,"started_seconds"=>started,
            "finished_seconds"=>elapsed(),"thread_cpu_seconds"=>cpu_seconds(3)-cpu,
            "routes"=>result.routes,"vehicles"=>result.validation.objective.vehicles,
            "distance"=>result.validation.objective.distance,"trace"=>result.trace,
            "error_backend"=>ICNScoring.metadata(backend))
    end
    records = Vector{Any}(undef,length(workers))
    strategy = nothing; structured = nothing
    if haskey(RoutingPanel.CATALOG,method)
        strategy = portfolio===nothing ? prepare_portfolio(workers) : portfolio
        executor=(;clone_backend=ICNScoring.clone_backend,metadata=ICNScoring.metadata,
            run=(plan,call,rows)->MS.execute!(plan.prepared.kernel,ExecutionContext(call,rows)))
        structured=StructuredRouting.run_portfolio(p,initial,method,seconds,seed,banks,strategy,executor;
            origin,initial_seconds,max_episodes,cpu_clock=()->cpu_seconds(3),instance_sha256=bytes2hex(sha256(read(path))))
        records=structured.workers
    elseif method == "highs_native"
        records[1] = invoke(1,only(workers))
    else
        strategy = portfolio===nothing ? prepare_portfolio(workers) : portfolio
        context = ExecutionContext(invoke,records)
        MS.execute!(strategy.prepared.kernel,context)
    end
    measured_wall = elapsed(); consumed_cpu = cpu_seconds()-process_cpu
    search_gc_seconds = (Base.gc_num().total_time-search_gc_origin)/1e9
    # Each worker only admits fully validated, in-budget snapshots. Audit and
    # merge outside the hot timer; do not invent an earlier receipt time.
    trajectory = Any[Dict("seconds"=>initial_seconds,"vehicles"=>checked.objective.vehicles,
        "distance"=>checked.objective.distance,"routes"=>deepcopy(initial),"source"=>"common_insertion")]
    observations = Any[]
    for record in records, event in record["trace"]["trajectory"]
        q = validate_solution(p,event["routes"])
        q.valid && q.objective.vehicles==event["vehicles"] && q.objective.distance==event["distance"] || error("invalid trajectory")
        0 <= event["seconds"] <= seconds || error("late incumbent")
        push!(observations,merge(event,Dict("source"=>record["method"],"worker"=>record["worker"])))
    end
    sort!(observations;by=e->e["seconds"])
    best = deepcopy(initial);quality = checked.objective
    for event in observations
        if (event["vehicles"],event["distance"]) < (quality.vehicles,quality.distance)
            best = deepcopy(event["routes"]);quality = validate_solution(p,best).objective
            push!(trajectory,event)
        end
    end
    return Dict{String,Any}("schema"=>"li-lim-resource-trial/1","instance"=>id,"method"=>method,
        "threads_requested"=>threads,"julia_threads_available"=>Threads.nthreads(),
        "threads_mode"=>structured!==nothing ? "cooperative serial lanes with typed episode barriers" : method=="highs_native" ? "native HiGHS pool" : "independent serial search trajectories; best incumbent merge",
        "workers"=>records,"allocation"=>workers,"seed"=>seed,"budget_seconds"=>seconds,
        "wall_seconds"=>measured_wall,"audit_merge_seconds"=>elapsed()-measured_wall,
        "process_cpu_seconds"=>consumed_cpu,"mean_active_cpus"=>consumed_cpu/measured_wall,
        "search_gc_seconds"=>search_gc_seconds,
        "gc_scope"=>"process-global collector time inside the shared search interval; forced precollection and final audit excluded",
        "initial_seconds"=>initial_seconds,"initial_vehicles"=>checked.objective.vehicles,
        "initial_distance"=>checked.objective.distance,"vehicles"=>quality.vehicles,"distance"=>quality.distance,
        "routes"=>best,"trajectory"=>trajectory,"original_validation"=>validate_solution(p,best).valid,
        "source_sha256"=>bytes2hex(sha256(read(path))),
        "metastrategist_executed"=>strategy!==nothing,
        "metastrategist_plan_reused"=>portfolio!==nothing,
        "metastrategist_plan_key"=>strategy===nothing ? "" : strategy.key,
        "strategy_panel"=>haskey(StrategyPanel.CATALOG,method) ? StrategyPanel.metadata(method,threads) : Dict{String,Any}(),
        "routing_panel"=>haskey(RoutingPanel.CATALOG,method) ? RoutingPanel.metadata(method,threads) : Dict{String,Any}(),
        "routing_coordination"=>structured===nothing ? Dict{String,Any}() : structured.coordination,
        "coordination"=>structured===nothing ? "static allocation, independently seeded workers, final best merge; no adaptive allocation or inter-worker incumbent exchange" :
            "typed episode barriers; validated solution/route pools; rotating or reward-adaptive roles; periodic bounded HiGHS master where configured")
end

function warmup(path,policy,banks;threads=Threads.nthreads())
    # Warm each concrete backend, serial HiGHS and the exact parallel wrapper.
    for method in ("cbls_naive","cbls_icn","cbls_icn_fused_scalar","cbls_icn_fused_all",
        "cbls_direct","hybrid_specialized_icn","hybrid_bridged_icn","highs_native","highs_portfolio")
        run_case(path,method,2.,41,policy,banks;threads)
    end
    if threads >= 4
        run_case(path,"mixed_balanced",2.,41,policy,banks;threads)
        run_case(path,"mixed_ls_heavy",2.,41,policy,banks;threads)
    end
    nothing
end
end
