"Minimal CBLS controller with bounded whole-route meta-variable repairs."
module Hybrid
include("QUBOGuidance.jl")
using Random
import LocalSearchSolvers as LS
using ..Benchmarks
using ..MetaRepair
using ..Pilot
include("SearchPolicies.jl")

export run_cbls, routing_score, prepare_parent, pair_relocation

"Direct route scorer, separate from the original-problem validator; no learned ICN claim."
function routing_score(p, distances, values)
    routes = try
        routes_from_successors(p, values)
    catch error
        error isa ArgumentError || error isa DimensionMismatch || rethrow()
        return (error=1., distance=Inf, vehicles=typemax(Int))
    end
    d = p.data
    violation = Float64(max(0, length(routes)-d.vehicles))
    route_of = zeros(Int, length(d.demand))
    position = zeros(Int, length(d.demand))
    total = 0.
    for (r, route) in enumerate(routes)
        clock = d.earliest[1]
        load = 0
        previous = 1
        for (order, node) in enumerate(route)
            route_of[node], position[node] = r, order
            travel = distances[previous,node]
            total += travel
            clock = max(d.earliest[node], clock+d.service[previous]+travel)
            violation += max(0., clock-d.latest[node]-1e-8)
            load += d.demand[node]
            violation += max(0,-load)+max(0,load-d.capacity)
            previous = node
        end
        total += distances[previous,1]
        violation += max(0., clock+d.service[previous]+distances[previous,1]-d.latest[1]-1e-8)+abs(load)
    end
    for (pickup, delivery) in d.pairs
        route_of[pickup] == route_of[delivery] || (violation += 1)
        position[pickup] < position[delivery] || (violation += 1)
    end
    (; error=violation, distance=total, vehicles=length(routes))
end

"Reusable group vectors belong to one hybrid search lane."
struct RouteGroupWorkspace
    buffers::Vector{Vector{Int}}
    groups::Vector{Vector{Int}}
end
RouteGroupWorkspace() = RouteGroupWorkspace(Vector{Int}[],Vector{Int}[])
function route_groups!(workspace::RouteGroupWorkspace, routes, max_visits)
    groups = workspace.groups
    empty!(groups)
    function add_group(a,b=nothing)
        i=length(groups)+1
        while length(workspace.buffers)<i;push!(workspace.buffers,Int[]);end
        group=workspace.buffers[i]
        resize!(group,b===nothing ? 1 : 2)
        group[1]=a
        b===nothing || (group[2]=b)
        push!(groups,group)
    end
    for a in eachindex(routes), b in a+1:length(routes)
        length(routes[a])+length(routes[b]) <= max_visits && add_group(a,b)
    end
    if isempty(groups)
        for i in eachindex(routes)
            length(routes[i]) <= max_visits && add_group(i)
        end
    end
    groups
end
route_groups(routes,max_visits) = route_groups!(RouteGroupWorkspace(),routes,max_visits)

struct PairRelocationWorkspace
    base::Vector{Vector{Int}}
    candidate::Vector{Int}
end
PairRelocationWorkspace() = PairRelocationWorkspace(Vector{Int}[],Int[])

"Best feasible reinsertion of one complete request; current routes remain owned by the caller."
function pair_relocation(p, routes, distances, pair; deadline_ns=typemax(UInt64),
        workspace=PairRelocationWorkspace(), selection=:best)
    selection in (:best,:first) || throw(ArgumentError("unknown pair selection"))
    pickup, delivery = pair
    source = findfirst(route -> pickup in route, routes)
    source === nothing && throw(ArgumentError("request absent from routes"))
    delivery in routes[source] || throw(ArgumentError("split request"))
    original_cost = sum(route -> Pilot.route_distance(route, distances), routes)
    base = workspace.base
    while length(base)<length(routes)
        push!(base,Int[])
    end
    resize!(base,length(routes))
    for i in eachindex(routes)
        resize!(base[i],length(routes[i])); copyto!(base[i],routes[i])
    end
    filter!(node -> node != pickup && node != delivery, base[source])
    source_cost = isempty(base[source]) ? 0. : Pilot.route_distance(base[source], distances)
    removed_cost = Pilot.route_distance(routes[source], distances)-source_cost
    best = nothing
    best_key = (length(routes), original_cost-1e-8)
    examined = 0
    fleet = length(base)-count(isempty,base)
    candidate = workspace.candidate
    for target in eachindex(base)
        route = base[target]
        old_cost = isempty(route) ? 0. : Pilot.route_distance(route, distances)
        resize!(candidate,length(route)+2)
        for a in 1:length(route)+1, b in a+1:length(route)+2
            time_ns() < deadline_ns || return (; routes=best, examined)
            offset = 0
            for j in eachindex(candidate)
                if j==a
                    candidate[j] = pickup
                elseif j==b
                    candidate[j] = delivery
                else
                    offset += 1; candidate[j] = route[offset]
                end
            end
            examined += 1
            Pilot.feasible_route(candidate,p.data,distances) || continue
            vehicles = fleet+(isempty(route) ? 1 : 0)
            distance = original_cost-removed_cost-old_cost+Pilot.route_distance(candidate,distances)
            key = (vehicles,distance)
            key < best_key || continue
            best = deepcopy(base); best[target] = copy(candidate); filter!(!isempty,best)
            best_key = key
            selection===:first && return (;routes=best,examined)
        end
    end
    (; routes=best, examined)
end

function prepare_parent(p, initial; seed=41, scorer=nothing, plateau_rejection=10,
        search_policy="legacy",policy_overrides=(;))
    Random.seed!(seed)
    validate_solution(p, initial).valid || throw(ArgumentError("valid common start required"))
    d = p.data
    sum(abs, BigInt.(d.demand)) <= typemax(Int) || throw(ArgumentError("scorer load arithmetic exceeds Int budget"))
    n = length(d.demand)
    distances = [hypot(d.coordinates[i,1]-d.coordinates[j,1],d.coordinates[i,2]-d.coordinates[j,2]) for i in 1:n, j in 1:n]
    fleet_weight = 2(n-1)*maximum(distances)+1
    isfinite(fleet_weight*d.vehicles) || throw(ArgumentError("objective scalar exceeds Float64 budget"))
    model = LS.model()
    foreach(_->LS.variable!(model, LS.domain(1:n)), 2:n)
    evaluate = scorer === nothing ? v->routing_score(p,distances,v) : v->scorer(p,distances,v)
    LS.constraint!(model, (v; X=nothing)->evaluate(v).error, 1:n-1)
    LS.objective!(model, v->begin
        score = evaluate(v)
        fleet_weight*score.vehicles+score.distance
    end)
    policy = SearchPolicies.materialize(model,search_policy;plateau_rejection,overrides=policy_overrides)
    strategy = policy.strategy
    acceptance = strategy.acceptance
    options = LS.Options(dynamic=false, process_threads_map=Dict(1=>1),
        print_level=:silent, log_mode=:silent, log_to_file=false,
        progress_mode=:none, use_progress_meter=false)
    solver = LS.solver(model; options, strategies=strategy)
    LS._init!(solver)
    values = successors(p, initial)
    foreach(i->LS._value!(solver,i,values[i]), eachindex(values))
    LS._compute!(solver)
    SearchPolicies.synchronize!(solver)
    (; solver, acceptance, fleet_weight, distances, policy_description=policy.description)
end

function run_cbls(p, initial; seconds=3., seed=41, hybrid=false, bridged=true,
        max_visits=16, repair_every=5, fragment_seconds=0.1, repair_fraction=0.35,
        structured=true, origin_ns=nothing, scorer=nothing, scorer_name="direct full-route scorer/1 (no ICN)",
        pair_selection=:best, pair_every=1, plateau_rejection=10, search_policy="legacy",policy_overrides=(;),
        repair_mode="mip",lp_solver="simplex",mip_lp_solver="choose",radius=4,fragment_selection="random",
        guide_mode="none",guide_depth=4,guide_every=32,guide_exploration=0.1,guide_fraction=0.1,
        guide=nothing,instance_sha256=nothing,warm_start=false)
    entered = time_ns()
    started = origin_ns === nothing ? entered : UInt64(origin_ns)
    started <= entered || throw(ArgumentError("clock origin is in the future"))
    isfinite(seconds) && seconds > 0 || throw(ArgumentError("positive finite budget required"))
    0 <= repair_fraction <= 1 && repair_every > 0 && isfinite(fragment_seconds) && fragment_seconds > 0 || throw(ArgumentError("invalid repair policy"))
    rng = Xoshiro(seed)
    pair_selection in (:best,:first) && pair_every>0 || throw(ArgumentError("invalid pair policy"))
    fragment_selection in ("random","bottleneck","qubo") || throw(ArgumentError("unknown fragment selector"))
    guide_mode in ("none","absolute","conditional") && guide_every>0 && guide_depth>0 &&
        0<=guide_fraction<=1 && 0<=guide_exploration<=1 || throw(ArgumentError("invalid guide policy"))
    prepared = prepare_parent(p, initial; seed, scorer, plateau_rejection, search_policy,policy_overrides)
    solver = prepared.solver
    initialization = (time_ns()-entered)/1e9
    best = deepcopy(initial)
    best_quality = validate_solution(p, best).objective
    steps = 0
    infeasible_steps = 0
    max_tabu_entries = 0
    pair_candidates = 0
    pair_moves = 0
    repair_seconds = 0.
    repairs = Any[]
    trajectory = Any[]
    elapsed() = (time_ns()-started)/1e9
    remaining() = max(0.,seconds-elapsed())
    deadline_ns = started+UInt64(round(seconds*1e9))
    best_scalar = prepared.fleet_weight*best_quality.vehicles+best_quality.distance
    pair_workspace = PairRelocationWorkspace()
    route_workspace = SuccessorRouteWorkspace()
    group_workspace = RouteGroupWorkspace()
    function consider!()
        LS.best_value(solver) < best_scalar || return
        candidate = routes_from_successors(p, collect(LS.best_values(solver)))
        validated = validate_solution(p, candidate)
        validated.valid || error("CBLS incumbent failed independent validation")
        quality = validated.objective
        if remaining() > 0 && (quality.vehicles,quality.distance) < (best_quality.vehicles,best_quality.distance)
            best = candidate
            best_quality = quality
            best_scalar = prepared.fleet_weight*quality.vehicles+quality.distance
            push!(trajectory, Dict("seconds"=>elapsed(),"vehicles"=>quality.vehicles,
                "distance"=>quality.distance,"routes"=>deepcopy(candidate)))
        end
    end
    resolver = HighsRouteResolver(; bridged, max_visits,repair_mode,lp_solver,mip_lp_solver,radius,warm_start)
    guide_seconds=0.;guide_candidates=0;guide_moves=0
    guide_started=time_ns()
    if guide_mode!="none" && guide===nothing
        n=length(p.data.demand)
        guide=QUBOGuidance.configured_guide(fill(1:n,n-1),
            ((a-1,b-1,1.) for (a,b) in p.data.pairs);id=p.id,instance_sha256)
    end
    gw=guide===nothing ? nothing : QUBOGuidance.Workspace(guide)
    guide_mode=="none" || (guide_seconds+=(time_ns()-guide_started)/1e9)
    candidate_buffer=copy(successors(p,initial))
    while remaining() > 0
        # Native resets may temporarily break successor topology or feasibility.
        # The native scorer repairs these states; feasible-route operators and
        # RO snapshots are meaningful only once the current state is feasible.
        if hybrid && iszero(LS.get_error(solver)) && steps % repair_every == 0 && repair_seconds < repair_fraction*seconds
            current_routes = routes_from_successors!(route_workspace,p,LS.get_values(solver))
            groups = route_groups!(group_workspace,current_routes,max_visits)
            if !isempty(groups)
                group = if fragment_selection=="bottleneck"
                    argmax(g->sum(Pilot.route_distance(current_routes[r],prepared.distances) for r in g),groups)
                elseif fragment_selection=="qubo" && guide!==nothing && guide_seconds<guide_fraction*seconds
                    select_started=time_ns()
                    chosen=QUBOGuidance.scope!(gw,guide,LS.get_values(solver),guide_depth,rng;
                        mode=guide_mode=="none" ? "absolute" : guide_mode,exploration=guide_exploration)
                    # Sparse/capped guides can omit parent decisions outside their last mapped atom.
                    group=argmax(g->sum(node-1<=length(gw.selected) && gw.selected[node-1]
                        for r in g for node in current_routes[r]),groups)
                    guide_seconds+=(time_ns()-select_started)/1e9
                    group
                else
                    rand(rng,groups)
                end
                ids = sort!([node-1 for r in group for node in current_routes[r]])
                variable = LS.MetaVariable(:route_repair, ids)
                capture_started = time_ns()
                snapshot = RouteSnapshot(p, current_routes)
                capture_seconds = (time_ns()-capture_started)/1e9
                available = min(fragment_seconds, remaining(), repair_fraction*seconds-repair_seconds-capture_seconds)
                if available > 0
                    outcome = LS.resolve_meta_variable(resolver,
                        LS.MetaVariableRequest(variable, snapshot, available, rng))
                    repair_seconds += capture_seconds+outcome.elapsed_seconds
                    push!(repairs, Dict("status"=>string(outcome.status), "snapshot_seconds"=>capture_seconds,
                        "elapsed_seconds"=>outcome.elapsed_seconds, "trace"=>outcome.trace))
                    if outcome.move !== nothing && remaining() > 0
                        LS._commit!(solver.model, solver.state, outcome.move)
                        LS._compute!(solver)
                        SearchPolicies.synchronize!(solver)
                        consider!()
                    end
                end
            end
        end
        remaining() > 0 || break
        if guide_mode!="none" && guide!==nothing && iszero(LS.get_error(solver)) && steps%guide_every==0 && guide_seconds<guide_fraction*seconds
            guide_started=time_ns();values=LS.get_values(solver)
            proposal=QUBOGuidance.proposal!(gw,guide,values,guide_depth,rng;mode=guide_mode,exploration=guide_exploration)
            guide_candidates+=proposal.examined
            copyto!(candidate_buffer,values)
            for (i,v) in zip(proposal.ids,proposal.values);candidate_buffer[i]=v;end
            candidate=try routes_from_successors!(route_workspace,p,candidate_buffer) catch e
                e isa ArgumentError || rethrow();nothing
            end
            if candidate!==nothing && remaining()>0
                q=validate_solution(p,candidate)
                # Surrogate ranking supplies proposals; truth and fleet-first quality decide.
                if q.valid && iszero(LS.get_error(solver))
                    current_quality=routing_score(p,prepared.distances,values)
                    if (q.objective.vehicles,q.objective.distance)<(current_quality.vehicles,current_quality.distance)
                        move=LS.MetaMove(LS.MetaVariable(:qubo_depth,proposal.ids),proposal.values;
                            provenance=(source=:qubo_guidance,depth=guide_depth))
                        iszero(LS._candidate_cost(solver,move)) || error("QUBO proposal failed ICN validation")
                        if remaining()>0
                            LS._commit!(solver.model,solver.state,move);LS._compute!(solver);SearchPolicies.synchronize!(solver)
                            guide_moves+=1;consider!()
                        end
                    end
                end
            end
            guide_seconds+=(time_ns()-guide_started)/1e9
        end
        remaining() > 0 || break
        if structured && iszero(LS.get_error(solver)) && steps % pair_every == 0
            current = routes_from_successors!(route_workspace,p,LS.get_values(solver))
            relocation = pair_relocation(p,current,prepared.distances,rand(rng,p.data.pairs);
                deadline_ns,workspace=pair_workspace,selection=pair_selection)
            pair_candidates += relocation.examined
            if relocation.routes !== nothing && remaining() > 0
                validation = validate_solution(p,relocation.routes)
                validation.valid || error("pair relocation failed original validation")
                replacements = successors(p,relocation.routes)
                values = collect(LS.get_values(solver))
                ids = findall(i -> values[i] != replacements[i], eachindex(values))
                if !isempty(ids) && remaining() > 0
                    variable = LS.MetaVariable(:pair_relocation,ids)
                    move = LS.MetaMove(variable,replacements[ids];provenance=(source=:paired_reinsertion,))
                    iszero(LS._candidate_cost(solver,move)) || error("pair relocation failed CBLS score")
                    if remaining() > 0
                        LS._commit!(solver,move); LS._compute!(solver)
                        SearchPolicies.synchronize!(solver)
                        pair_moves += 1
                        consider!()
                    end
                end
            end
        end
        remaining() > 0 || break
        LS._step!(solver)
        steps += 1
        iszero(LS.get_error(solver)) || (infeasible_steps += 1)
        max_tabu_entries = max(max_tabu_entries,LS.length_tabu(solver.strategies))
        consider!()
    end
    # A bounded operation may finish after the deadline. It cannot backdate a
    # result into the budget: only the last fully validated in-budget incumbent
    # above is delivered. The common valid start remains the fallback.
    validation = validate_solution(p, best)
    validation.valid || error("invalid final CBLS incumbent")
    return (; routes=best, validation,
        trace=Dict("seconds"=>elapsed(), "budget_seconds"=>seconds,
            "initialization_seconds"=>initialization, "steps"=>steps,
            "search_policy"=>prepared.policy_description,
            "infeasible_steps"=>infeasible_steps,"max_tabu_entries"=>max_tabu_entries,
            "sequence_or_exhaustion_resets"=>SearchPolicies.sequence_resets(solver.strategies.restart),
            "reset_counter_scope"=>"native universal sequence index or exhaustion count; -1 means random/tabu-trigger count unavailable",
            "pair_candidates"=>pair_candidates, "pair_moves"=>pair_moves,
            "structured"=>structured, "pair_policy"=>"random request, $(pair_selection) feasible improving reinsertion/2",
            "pair_every"=>pair_every,"plateau_rejection_percent"=>plateau_rejection,
            "repair_seconds"=>repair_seconds, "repair_fraction"=>repair_fraction,
            "guide_seconds"=>guide_seconds,"guide_candidates"=>guide_candidates,"guide_moves"=>guide_moves,
            "guide"=>guide===nothing ? Dict("authority"=>"disabled") : QUBOGuidance.metadata(guide),
            "fragment_selection"=>fragment_selection,
            "repairs"=>repairs, "trajectory"=>trajectory, "threads"=>1,
            "scorer"=>scorer_name, "julia_thread_id"=>Threads.threadid(),
            "controller"=>"explicit native LS steps, paired reinsertion and atomic MetaMove commits/2",
            "hybrid"=>hybrid, "bridged"=>bridged, "fleet_weight"=>prepared.fleet_weight))
end

end
