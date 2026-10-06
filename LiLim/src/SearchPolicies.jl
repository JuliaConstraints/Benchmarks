"Materialize existing local-search strategies without changing the historical profiles."
module SearchPolicies
using TOML
import LocalSearchSolvers as LS
# Reuse the acceptance policy already exercised by the solver smoke benchmarks.
include(joinpath(@__DIR__, "..", "..", "SolverSmoke", "src", "Profiles.jl"))

const CONFIG_PATH = joinpath(@__DIR__, "..", "config", "strategy-variants.toml")
const CONFIG = TOML.parsefile(CONFIG_PATH)
const VARIANTS = Dict(row["method"] => row for row in CONFIG["variants"])
const METHODS = Tuple(row["method"] for row in CONFIG["variants"])
const PORTFOLIOS = CONFIG["portfolios"]
const DEFAULTS = (acceptance="greedy", guide_infeasible=true, plateau_rejection=10,
    history=400, selector="worst", neighborhood="assign_swap", tabu="none",
    local_tenure=0, selected_tenure=0, clock="proposal", restart="random",
    probability=0.0, fraction=0.0, source="best", universal_scale=64,
    tabu_threshold=8, full_every=0)

function settings(id)
    haskey(CONFIG["profiles"], id) || throw(ArgumentError("unknown search policy $id"))
    row = CONFIG["profiles"][id]
    unknown = setdiff(Set(keys(row)), Set(string.(keys(DEFAULTS))))
    isempty(unknown) || throw(ArgumentError("unknown policy fields: $unknown"))
    merge(DEFAULTS, (; (Symbol(k)=>v for (k,v) in row)...))
end

function materialize(model, id; plateau_rejection=10)
    if id == "legacy"
        acceptance = LS.GreedyPlateauAcceptance(;guide_infeasible=false,
            reject_plateau_percent=plateau_rejection)
        restart = LS.restart_policy(LS.restart(nothing, Val(:random); rp=0.);
            reset_fraction=0., source=:best)
        strategy = LS.MetaStrategy(model;acceptance,tabu=LS.tabu(),restart)
        description = Dict{String,Any}("id"=>id,"acceptance"=>"greedy",
            "guide_infeasible"=>false,"plateau_rejection"=>plateau_rejection,
            "tabu"=>"none","restart"=>"random","probability"=>0.,
            "fraction"=>0.,"source"=>"best",
            "stagnation_reset"=>"native reset after more than variable-count rejected steps; restores best without perturbation")
        return (;strategy,description)
    end
    c = settings(id)
    0 <= c.probability <= 1 && isfinite(c.probability) || throw(ArgumentError("invalid restart probability"))
    c.universal_scale > 0 && c.history > 0 || throw(ArgumentError("positive sequence scale and history required"))
    acceptance = if c.acceptance == "greedy"
        LS.GreedyPlateauAcceptance(;guide_infeasible=c.guide_infeasible,
            reject_plateau_percent=c.plateau_rejection)
    elseif c.acceptance == "late"
        a = Profiles.LateAcceptance(c.history)
        a.delegate = LS.GreedyPlateauAcceptance(;guide_infeasible=c.guide_infeasible,
            reject_plateau_percent=0)
        a
    elseif c.acceptance == "compatibility"
        LS.BestImprovingAcceptance()
    else
        throw(ArgumentError("unknown acceptance"))
    end
    selector = c.selector == "remaining" ? LS.RemainingWorstSelector() :
        c.selector == "worst" ? LS.WorstVariableSelector() : throw(ArgumentError("unknown selector"))
    neighborhood, depths = c.neighborhood == "assignment" ?
        (LS.AssignmentNeighborhood(), LS.DepthSchedule(0)) :
        c.neighborhood == "assign_swap" ? (LS.AssignSwapNeighborhood(), LS.DepthSchedule(0,1)) :
        throw(ArgumentError("unknown neighborhood"))
    tabu = c.tabu == "event" ? LS.EventTabu(c.local_tenure;
        selected_tenure=c.selected_tenure,clock=Symbol(c.clock)) :
        c.tabu == "keen" ? LS.tabu(c.local_tenure) :
        c.tabu == "weak" ? LS.tabu(c.local_tenure,c.selected_tenure) :
        c.tabu == "none" ? LS.tabu() : throw(ArgumentError("unknown tabu"))
    restart = if c.restart == "exhaustion"
        c.source == "current" || throw(ArgumentError("native exhaustion resets use the current state"))
        LS.ExhaustionRestart(;tabu_threshold=c.tabu_threshold,
            reset_fraction=c.fraction,full_every=c.full_every)
    else
        trigger = if c.restart == "random"
            LS.restart(tabu,Val(:random);rp=c.probability)
        elseif c.restart == "universal"
            scale = c.universal_scale
            LS.RestartSequence(i->Base.checked_mul(scale,LS._universal_restart_length(i)))
        elseif c.restart == "tabu"
            c.local_tenure > c.selected_tenure || throw(ArgumentError("tabu restart needs positive tenure difference"))
            LS.restart(tabu,Val(:tabu))
        else
            throw(ArgumentError("unknown restart"))
        end
        LS.restart_policy(trigger;reset_fraction=c.fraction,source=Symbol(c.source))
    end
    if c.acceptance == "compatibility" &&
            (c.selector == "remaining" || c.tabu == "event" || c.restart == "exhaustion")
        throw(ArgumentError("event policies require explicit acceptance"))
    end
    strategy = LS.MetaStrategy(model;variable_selection=selector,neighborhood,depths,
        acceptance,tabu,restart)
    description = Dict{String,Any}(string(k)=>v for (k,v) in pairs(c))
    description["id"] = id
    description["stagnation_reset"] = c.restart == "exhaustion" ?
        "selection exhaustion or tabu threshold" : "native rejection-count stagnation trigger also applies"
    (;strategy,description)
end

"Synchronize policy caches after externally committed route or RO moves."
function synchronize!(solver)
    strategy = solver.strategies
    if strategy.acceptance isa LS.ExplicitMoveAcceptance
        LS._reset_proposal_acceptance!(strategy.acceptance,solver.model,solver.state)
        LS._selection_result!(strategy.variable_selection,:reset)
    end
    LS.empty_tabu!(strategy)
    nothing
end

function sequence_resets(restart)
    restart isa LS.RestartPolicy && return sequence_resets(restart.trigger)
    restart isa LS.ExhaustionRestart && return restart.resets
    restart isa LS.RestartSequence && return restart.index-1
    # Random and tabu-triggered reset counts are not exposed by their native types.
    -1
end
end
