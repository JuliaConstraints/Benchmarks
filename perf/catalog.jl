using PerfChecker
include("../LiLim/src/StrategyPanel.jl")

"Explicit PerfChecker scenarios; the full 496-method grid is opt-in."
function build_catalog(;scope=:kernels,methods=String[],width=1,collectors=[:profile,:profile_alloc])
    width in (1,2,4,8,16) || throw(ArgumentError("qualified resource widths are 1/2/4/8/16"))
    source=joinpath(@__DIR__,"scenarios.jl")
    fixtures=[joinpath(@__DIR__,"../LiLim/src",f) for f in ("QUBOGuidance.jl","StrategyPanel.jl","ROFragments.jl","SearchPolicies.jl")]
    push!(fixtures,StrategyPanel.CONFIG_PATH)
    push!(fixtures,joinpath(@__DIR__,"../LiLim/config/strategy-variants.toml"))
    push!(fixtures,joinpath(@__DIR__,"../LiLim/resources/icn-pdptw-witnesses.toml"))
    push!(fixtures,joinpath(@__DIR__,"../SolverSmoke/src/Profiles.jl"))
    scenarios=ScenarioSpec[]
    if scope==:kernels
        for size in (32,128,256),operation in ("energy","delta","full_move","scope","proposal"),depth in
                (operation in ("scope","proposal") ? (2,4,8) : (4,))
            push!(scenarios,ScenarioSpec("qubo_$(operation)_n$(size)_d$(depth)";source,factory="kernel_case",
                implementation="sparse-owned-buffers-v1",parameters=Dict("operation"=>operation,"variables"=>size,
                    "depth"=>depth,"repetitions"=>1024),fixtures,collectors,repeatable=true))
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
    else
        throw(ArgumentError("scope must be kernels or strategies"))
    end
    ScenarioCatalog(normpath(joinpath(@__DIR__,"..")),scenarios)
end
