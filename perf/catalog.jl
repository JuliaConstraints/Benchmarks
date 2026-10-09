using PerfChecker
include("../LiLim/src/StrategyPanel.jl")
include("../LiLim/src/RoutingPanel.jl")

"Explicit PerfChecker scenarios; the full 496-method grid is opt-in."
function build_catalog(;scope=:kernels,methods=String[],families=Symbol[],backends=[:direct],width=1,collectors=[:profile,:profile_alloc])
    width in (1,2,4,8,16) || throw(ArgumentError("qualified resource widths are 1/2/4/8/16"))
    source=joinpath(@__DIR__,"scenarios.jl")
    fixtures=[joinpath(@__DIR__,"../LiLim/src",f) for f in ("QUBOGuidance.jl","StrategyPanel.jl","ROFragments.jl","SearchPolicies.jl")]
    push!(fixtures,StrategyPanel.CONFIG_PATH)
    push!(fixtures,joinpath(@__DIR__,"../LiLim/config/strategy-variants.toml"))
    push!(fixtures,joinpath(@__DIR__,"../LiLim/resources/icn-pdptw-witnesses.toml"))
    push!(fixtures,joinpath(@__DIR__,"../SolverSmoke/src/Profiles.jl"))
    scenarios=ScenarioSpec[]
    if scope==:trace_counters
        source=joinpath(@__DIR__,"trace_scenarios.jl")
        fixtures=[joinpath(@__DIR__,"../LiLim/src/TraceCounters.jl")]
        for mode in ("integer","mixed","dynamic_assignment")
            push!(scenarios,ScenarioSpec("routing_trace_"*mode;source,factory="trace_counter_case",
                implementation="owned-numeric-trace-v1",parameters=Dict("mode"=>mode,"repetitions"=>100000),
                fixtures,collectors,repeatable=true))
        end
    elseif scope==:kernels
        for size in (32,128,256),operation in ("energy","delta","full_move","scope","proposal"),depth in
                (operation in ("scope","proposal") ? (2,4,8) : (4,))
            push!(scenarios,ScenarioSpec("qubo_$(operation)_n$(size)_d$(depth)";source,factory="kernel_case",
                implementation="sparse-owned-buffers-v1",parameters=Dict("operation"=>operation,"variables"=>size,
                    "depth"=>depth,"repetitions"=>1024),fixtures,collectors,repeatable=true))
        end
    elseif scope in (:classical_scoring,:classical_objectives)
        isempty(families) && throw(ArgumentError("select explicit classical problem families"))
        isempty(backends) && throw(ArgumentError("select explicit scoring backends"))
        all(k->k in (:naive,:direct,:icn,:icn_fused),backends) || throw(ArgumentError("unknown scoring backend"))
        append!(fixtures,[joinpath(dir,file) for (dir,_,files) in walkdir(joinpath(@__DIR__,"../Hexaly/src"))
            for file in files if endswith(file,".jl")])
        push!(fixtures,joinpath(@__DIR__,"../Hexaly/test/fixtures.jl"))
        for family in families,backend in backends
            objective=scope==:classical_objectives
            push!(scenarios,ScenarioSpec("classical_$(objective ? "objective_" : "")$(family)_$(backend)";source,
                factory=objective ? "classical_objective_case" : "classical_scoring_case",
                implementation=objective ? "owned-original-objective-callbacks-v1" : "prepared-original-zero-set-callbacks-v1",parameters=Dict("family"=>string(family),
                    "backend"=>string(backend),"repetitions"=>128),fixtures,collectors,repeatable=true))
        end
    elseif scope==:strategies
        isempty(methods) && throw(ArgumentError("select explicit strategy IDs or opt-in aliases"))
        measured=StrategyPanel.expand(methods)
        all(id->haskey(StrategyPanel.CATALOG,id),measured) || throw(ArgumentError("unknown strategy"))
        # Every included source belongs to the scenario fingerprint, not just the factory.
        append!(fixtures,[joinpath(dir,file) for (dir,_,files) in walkdir(joinpath(@__DIR__,"../Hexaly/src"))
            for file in files if endswith(file,".jl")])
        push!(fixtures,joinpath(@__DIR__,"../Hexaly/test/fixtures.jl"))
        for id in measured
            any(l->l.bridged,StrategyPanel.allocation(id,width)) && continue # Li-Lim-only bridge qualification
            push!(scenarios,ScenarioSpec(id*"_w$width";source,factory="solver_case",implementation="original-validated-v1",
                parameters=Dict("method"=>id,"width"=>width,"steps"=>256,"seed"=>41),
                fixtures,collectors,repeatable=true))
        end
    elseif scope in (:routing_kernels,:routing_strategies)
        source=joinpath(@__DIR__,"routing_scenarios.jl")
        append!(fixtures,[joinpath(@__DIR__,"../LiLim/src",f) for f in
            ("StructuredRouting.jl","TraceCounters.jl","RoutingPanel.jl","Pilot.jl","MetaRepair.jl","Hybrid.jl","ICNScoring.jl","ResourceExperiment.jl","PlatformResources.jl")])
        push!(fixtures,RoutingPanel.CONFIG_PATH)
        if scope==:routing_kernels
            for requests in (8,32,128)
                push!(scenarios,ScenarioSpec("routing_owned_snapshot_n$requests";source,
                    factory="routing_snapshot_case",implementation="owned-primitive-snapshots-v1",
                    parameters=Dict("requests"=>requests,"seed"=>41,"repetitions"=>128),
                    fixtures,collectors,repeatable=true))
                push!(scenarios,ScenarioSpec("routing_pair_relocation_n$requests";source,
                    factory="pair_relocation_case",implementation="owned-surviving-incumbent-v2",
                    parameters=Dict("requests"=>requests,"seed"=>41,"repetitions"=>128),
                    fixtures,collectors,repeatable=true))
            end
            for operation in ("insertion","insertion_options","cache","cache_reuse","repair","ejection","pool_reuse","duplicate_admission","arc_reuse","route_copy","successor_fill","request_selection","exchange_rejection","original_validation")
                push!(scenarios,ScenarioSpec("routing_"*operation;source,factory="routing_kernel_case",
                    implementation=operation=="insertion_options" ? "paired-insertion-prepared-views-v2" :
                        operation in ("request_selection","exchange_rejection","original_validation","pool_reuse") ? "paired-original-owned-workspaces-v2" : "paired-original-sequences-v1",parameters=Dict("operation"=>operation,
                        "repetitions"=>operation in ("insertion","duplicate_admission","arc_reuse","route_copy","successor_fill","request_selection","exchange_rejection","original_validation") ? 1024 :
                            operation in ("insertion_options","cache","cache_reuse","pool_reuse") ? 128 : 8),
                    fixtures,collectors,repeatable=true))
            end
        else
            isempty(methods) && throw(ArgumentError("explicit routing methods required"))
            for id in RoutingPanel.expand(methods)
                haskey(RoutingPanel.CATALOG,id) || throw(ArgumentError("unknown routing strategy"))
                meta=RoutingPanel.CATALOG[id].category==:meta
                push!(scenarios,ScenarioSpec(id*"_w$width";source,factory=meta ? "routing_meta_case" : "routing_solver_case",
                    implementation=meta ? "typed-cooperative-routing-four-episodes-v1" : "configured-error-routing-fixed-steps-v1",
                    parameters=Dict("method"=>id,"width"=>width,"steps"=>meta ? 4 : 8),
                    fixtures,collectors,repeatable=true))
            end
        end
    else
        throw(ArgumentError("scope must be trace_counters, kernels, classical_scoring, classical_objectives, strategies, routing_kernels or routing_strategies"))
    end
    ScenarioCatalog(normpath(joinpath(@__DIR__,"..")),scenarios)
end
