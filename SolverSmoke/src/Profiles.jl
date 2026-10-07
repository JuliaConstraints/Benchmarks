module Profiles
import LocalSearchSolvers as LS
using Random
export profile, profile_ids
const profile_ids=["default","assignment","juls_greedy_like","ghost_assignment_like","timefold_late_acceptance_like"]

"Acceptance-only analogue; proposal enumeration/initialization differ from Timefold."
mutable struct LateAcceptance <: LS.ExplicitMoveAcceptance
    delegate::LS.GreedyPlateauAcceptance
    history::Vector{Tuple{Float64,Float64}}
    index::Int
end
LateAcceptance(n=400)=LateAcceptance(LS.GreedyPlateauAcceptance(reject_plateau_percent=0),fill((Inf,Inf),n),1)
function LS._reset_proposal_acceptance!(a::LateAcceptance,m,s)
    LS._reset_proposal_acceptance!(a.delegate,m,s)
    fill!(a.history,LS._current_proposal_rank(a.delegate,m,s));a.index=1
end
LS._current_proposal_rank(a::LateAcceptance,m,s)=LS._current_proposal_rank(a.delegate,m,s)
LS._accepted_objective!(a::LateAcceptance,m,s)=LS._accepted_objective!(a.delegate,m,s)
LS._proposal_rank(a::LateAcceptance,c,m)=LS._proposal_rank(a.delegate,c,m)
function LS.decide_move(a::LateAcceptance,proposed,current,rng=Random.default_rng())
    accepted=proposed<=current || proposed<a.history[a.index]
    a.history[a.index]=accepted ? proposed : current
    a.index=mod1(a.index+1,length(a.history))
    accepted ? :accepted : :rejected
end
function profile(model,id)
    n=LS.length_vars(model)
    id=="default" && return LS.MetaStrategy(model)
    id=="assignment" && return LS.MetaStrategy(model;neighborhood=LS.AssignmentNeighborhood(),depths=LS.DepthSchedule(0))
    id=="juls_greedy_like" && return LS.MetaStrategy(model;depths=LS.DepthSchedule(0,1),
        acceptance=LS.GreedyPlateauAcceptance(reject_plateau_percent=0),tabu=LS.NoTabu(),
        restart=LS.RandomRestart(0.0))
    if id=="ghost_assignment_like"
        tenure=max(min(5,n-1),n÷5)+1;fraction=max(2,ceil(Int,.1n))/n
        return LS.MetaStrategy(model;variable_selection=LS.RemainingWorstSelector(connected_only=true),
            neighborhood=LS.AssignmentNeighborhood(),depths=LS.DepthSchedule(0),
            acceptance=LS.GreedyPlateauAcceptance(reject_plateau_percent=10),
            tabu=LS.EventTabu(tenure;selected_tenure=0,clock=:accepted),
            restart=LS.ExhaustionRestart(tabu_threshold=tenure,reset_fraction=fraction,full_every=n))
    end
    id=="timefold_late_acceptance_like" && return LS.MetaStrategy(model;
        acceptance=LateAcceptance(400),tabu=LS.NoTabu(),restart=LS.RandomRestart(0.0))
    error("Unknown strategy profile $id")
end
end
