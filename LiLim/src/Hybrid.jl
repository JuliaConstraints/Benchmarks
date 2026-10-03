"Minimal CBLS controller with bounded whole-route meta-variable repairs."
module Hybrid
using Random
import LocalSearchSolvers as LS
using ..Benchmarks
using ..MetaRepair
using ..Pilot

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

function route_groups(routes, max_visits)
    groups = Vector{Int}[]
    for a in eachindex(routes), b in a+1:length(routes)
        length(routes[a])+length(routes[b]) <= max_visits && push!(groups, [a,b])
    end
    isempty(groups) && append!(groups, [[i] for i in eachindex(routes) if length(routes[i]) <= max_visits])
    groups
end

"Best feasible reinsertion of one complete request; current routes remain owned by the caller."
function pair_relocation(p, routes, distances, pair; deadline_ns=typemax(UInt64))
    pickup, delivery = pair
    source = findfirst(route -> pickup in route, routes)
    source === nothing && throw(ArgumentError("request absent from routes"))
    delivery in routes[source] || throw(ArgumentError("split request"))
    original_cost = sum(route -> Pilot.route_distance(route, distances), routes)
    base = deepcopy(routes)
    filter!(node -> node != pickup && node != delivery, base[source])
    source_cost = isempty(base[source]) ? 0. : Pilot.route_distance(base[source], distances)
    removed_cost = Pilot.route_distance(routes[source], distances)-source_cost
    best = nothing
    best_key = (length(routes), original_cost-1e-8)
    examined = 0
    for target in eachindex(base)
        route = base[target]
        old_cost = isempty(route) ? 0. : Pilot.route_distance(route, distances)
        for a in 1:length(route)+1, b in a+1:length(route)+2
            time_ns() < deadline_ns || return (; routes=best, examined)
            candidate = copy(route)
            insert!(candidate,a,pickup); insert!(candidate,b,delivery)
            examined += 1
            Pilot.feasible_route(candidate,p.data,distances) || continue
            vehicles = length(base)-count(isempty,base)+(isempty(route) ? 1 : 0)
            distance = original_cost-removed_cost-old_cost+Pilot.route_distance(candidate,distances)
            key = (vehicles,distance)
            key < best_key || continue
            best = deepcopy(base); best[target] = candidate; filter!(!isempty,best)
            best_key = key
        end
    end
    (; routes=best, examined)
end

function prepare_parent(p, initial; seed=41)
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
    LS.constraint!(model, (v; X=nothing)->routing_score(p,distances,v).error, 1:n-1)
    LS.objective!(model, v->begin
        score = routing_score(p,distances,v)
        fleet_weight*score.vehicles+score.distance
    end)
    acceptance = LS.GreedyPlateauAcceptance(;guide_infeasible=false)
    restart = LS.restart_policy(LS.restart(nothing, Val(:random); rp=0.);
        reset_fraction=0., source=:best)
    strategy = LS.MetaStrategy(model; acceptance, tabu=LS.tabu(), restart)
    options = LS.Options(dynamic=false, process_threads_map=Dict(1=>1),
        print_level=:silent, log_mode=:silent, log_to_file=false,
        progress_mode=:none, use_progress_meter=false)
    solver = LS.solver(model; options, strategies=strategy)
    LS._init!(solver)
    values = successors(p, initial)
    foreach(i->LS._value!(solver,i,values[i]), eachindex(values))
    LS._compute!(solver)
    LS._reset_proposal_acceptance!(acceptance, solver.model, solver.state)
    (; solver, acceptance, fleet_weight, distances)
end

function run_cbls(p, initial; seconds=3., seed=41, hybrid=false, bridged=true,
        max_visits=16, repair_every=5, fragment_seconds=0.1, repair_fraction=0.35,
        structured=true)
    started = time_ns()
    isfinite(seconds) && seconds > 0 || throw(ArgumentError("positive finite budget required"))
    0 <= repair_fraction <= 1 && repair_every > 0 && isfinite(fragment_seconds) && fragment_seconds > 0 || throw(ArgumentError("invalid repair policy"))
    rng = Xoshiro(seed)
    prepared = prepare_parent(p, initial; seed)
    solver, acceptance = prepared.solver, prepared.acceptance
    initialization = (time_ns()-started)/1e9
    best = deepcopy(initial)
    best_quality = validate_solution(p, best).objective
    steps = 0
    pair_candidates = 0
    pair_moves = 0
    repair_seconds = 0.
    repairs = Any[]
    trajectory = Any[]
    elapsed() = (time_ns()-started)/1e9
    remaining() = max(0.,seconds-elapsed())
    deadline_ns = started+UInt64(round(seconds*1e9))
    best_scalar = prepared.fleet_weight*best_quality.vehicles+best_quality.distance
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
            push!(trajectory, Dict("seconds"=>elapsed(),"vehicles"=>quality.vehicles,"distance"=>quality.distance))
        end
    end
    resolver = HighsRouteResolver(; bridged, max_visits)
    while remaining() > 0
        if hybrid && steps % repair_every == 0 && repair_seconds < repair_fraction*seconds
            current_routes = routes_from_successors(p, collect(LS.get_values(solver)))
            groups = route_groups(current_routes, max_visits)
            if !isempty(groups)
                group = rand(rng, groups)
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
                        LS._reset_proposal_acceptance!(acceptance, solver.model, solver.state)
                        consider!()
                    end
                end
            end
        end
        remaining() > 0 || break
        if structured
            current = routes_from_successors(p, collect(LS.get_values(solver)))
            relocation = pair_relocation(p,current,prepared.distances,rand(rng,p.data.pairs);deadline_ns)
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
                        LS._reset_proposal_acceptance!(acceptance,solver.model,solver.state)
                        pair_moves += 1
                        consider!()
                    end
                end
            end
        end
        remaining() > 0 || break
        LS._step!(solver)
        steps += 1
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
            "pair_candidates"=>pair_candidates, "pair_moves"=>pair_moves,
            "structured"=>structured, "pair_policy"=>"random request, best feasible greedy reinsertion/1",
            "repair_seconds"=>repair_seconds, "repair_fraction"=>repair_fraction,
            "repairs"=>repairs, "trajectory"=>trajectory, "threads"=>1,
            "scorer"=>"direct full-route scorer/1 (no ICN)",
            "controller"=>"explicit native LS steps, paired reinsertion and atomic MetaMove commits/2",
            "hybrid"=>hybrid, "bridged"=>bridged, "fleet_weight"=>prepared.fleet_weight))
end

end
