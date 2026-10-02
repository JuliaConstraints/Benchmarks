"Bounded whole-route RO fragments; this adapter alone is not a complete CBLS hybrid."
module MetaRepair
using JuMP, Random
import LocalSearchSolvers as LS
import XCSP3Bridges as XB
import MathOptInterface as MOI
using ..Benchmarks
using ..Pilot

export RouteSnapshot, HighsRouteResolver, successors, routes_from_successors

"Each parent variable is one customer's successor; value 1 denotes the depot."
function successors(instance, routes)
    validate_solution(instance, routes).valid || throw(ArgumentError("invalid parent routes"))
    values = ones(Int, length(instance.data.demand)-1)
    for route in routes, (node, next) in zip(route, [route[2:end]; 1])
        values[node-1] = next
    end
    values
end

"Decode a complete successor assignment, rejecting duplicates, missing nodes and cycles."
function routes_from_successors(instance, values)
    n = length(instance.data.demand)
    length(values) == n-1 || throw(DimensionMismatch("successor assignment"))
    all(x -> x isa Real && isfinite(x) && isinteger(x) && 1 <= x <= n, values) ||
        throw(ArgumentError("invalid successor value"))
    next = Int.(values)
    incoming = zeros(Int, n)
    for node in next
        node == 1 || (incoming[node] += 1)
    end
    all(<=(1), incoming[2:end]) || throw(ArgumentError("duplicate incoming arc"))
    routes = Vector{Int}[]
    visited = falses(n)
    for first in 2:n
        incoming[first] == 0 || continue
        route = Int[]
        node = first
        while node != 1
            visited[node] && throw(ArgumentError("cycle or repeated service"))
            visited[node] = true
            push!(route, node)
            node = next[node-1]
        end
        push!(routes, route)
    end
    all(visited[2:end]) || throw(ArgumentError("disconnected customer cycle"))
    routes
end

struct RouteSnapshot{P}
    instance::P
    routes::Vector{Vector{Int}}
    values::Vector{Int}
    function RouteSnapshot(instance, routes)
        owned = deepcopy(instance)
        copy = [Int[route...] for route in routes]
        values = successors(owned, copy)
        new{typeof(owned)}(owned, copy, values)
    end
end

struct HighsRouteResolver <: LS.AbstractMetaVariableResolver
    bridged::Bool
    max_visits::Int
    function HighsRouteResolver(; bridged=true, max_visits=16)
        2 <= max_visits <= 20 || throw(ArgumentError("fragment cap must be between 2 and 20 visits"))
        new(Bool(bridged), Int(max_visits))
    end
end

function LS.resolve_meta_variable(resolver::HighsRouteResolver, request::LS.MetaVariableRequest)
    started = time_ns()
    budget = Float64(request.budget)
    isfinite(budget) && budget >= 0 || throw(ArgumentError("finite nonnegative seconds required"))
    elapsed() = (time_ns()-started)/1e9
    remaining() = max(0.0, budget-elapsed())
    trace = Dict{String,Any}("representation"=>"customer-successor/1",
        "fragment"=>"union of complete current routes", "bridged"=>resolver.bridged,
        "threads"=>1, "budget_seconds"=>budget, "mip_start"=>false,
        "semantics"=>SEMANTICS_VERSION)
    finish(status, move=nothing) = (; status, move, elapsed_seconds=elapsed(), trace)
    budget == 0 && return finish(:budget_exhausted)
    snapshot = request.snapshot
    snapshot isa RouteSnapshot || throw(ArgumentError("RouteSnapshot required"))
    p = snapshot.instance
    current = successors(p, snapshot.routes)
    current == snapshot.values || throw(ArgumentError("snapshot was mutated"))
    ids = LS.scope(request.variable)
    all(i -> 1 <= i <= length(current), ids) || return finish(:invalid_fragment)
    nodes = sort!(Int[i+1 for i in ids])
    isempty(nodes) && return finish(:invalid_fragment)
    length(nodes) <= resolver.max_visits || return finish(:resource_limited)
    selected = Set(nodes)
    group = Int[]
    for (r, route) in enumerate(snapshot.routes)
        count = sum(i -> i in selected, route)
        count in (0, length(route)) || return finish(:invalid_fragment)
        count > 0 && push!(group, r)
    end
    isempty(group) && return finish(:invalid_fragment)
    outside = [copy(route) for (r, route) in enumerate(snapshot.routes) if !(r in group)]
    d = p.data
    mapping = [1; nodes]
    local_index = Dict(node=>index for (index, node) in enumerate(mapping))
    pairs = [(local_index[a], local_index[b]) for (a,b) in d.pairs if a in selected && b in selected]
    2 * length(pairs) == length(nodes) || return finish(:invalid_fragment)
    data = PickupDeliveryProblem(d.vehicles-length(outside), d.capacity,
        d.coordinates[mapping,:], d.demand[mapping], d.earliest[mapping],
        d.latest[mapping], d.service[mapping], pairs)
    fragment = BenchmarkInstance(p.id * "::whole-routes", data)
    trace["parent_visits"] = length(current)
    trace["fragment_visits"] = length(nodes)
    trace["outside_routes"] = length(outside)
    trace["bridge_programs"] = Any[]
    trace["bridge_program_provenance"] = "manual one-atom equality DAG, not a learned or recovered optimum"
    bridge = resolver.bridged ? (model, left, right, domain)->begin
        space = XB.NetworkSpace([domain, domain]; slots=1, operators=(:eq,), constants=0:1)
        weights = BigInt[findfirst(==(:eq), space.operators), 1, 2, 0, 0, 3]
        program = XB.decode_network(space, weights)
        # An outer bridge optimizer emits primitive constraints into the JuMP
        # cache while preserving the existing source variable identities.
        backend = XB.add_bridges!(MOI.Bridges.LazyBridgeOptimizer(JuMP.backend(model)))
        XB.add_program!(backend, program, MOI.VariableIndex[index(left), index(right)])
        push!(trace["bridge_programs"], XB.network_payload(space, weights))
        nothing
    end : nothing
    remaining() > 0 || return finish(:budget_exhausted)
    seed = rand(request.rng, 1:1_000_000)
    trace["highs_seed"] = seed
    build_started = time_ns()
    f = Pilot.model(fragment; threads=1, seed, seconds=remaining(), pair_bridge=bridge)
    trace["build_seconds"] = (time_ns()-build_started)/1e9
    trace["variables"] = num_variables(f.m)
    trace["constraints"] = num_constraints(f.m; count_variable_in_set_constraints=true)
    remaining() > 0 || return finish(:budget_exhausted)
    set_time_limit_sec(f.m, remaining())
    routes, phases, seconds = Pilot.solve!(f; seconds=remaining())
    trace["solve_seconds"] = seconds
    trace["phases"] = phases
    routes === nothing && return finish(:no_incumbent)
    repair = [[mapping[i] for i in route] for route in routes]
    validation_started = time_ns()
    combined = [outside; repair]
    validation = validate_solution(p, combined)
    trace["validation_seconds"] = (time_ns()-validation_started)/1e9
    validation.valid || return finish(:invalid_solution)
    before = validate_solution(p, snapshot.routes).objective
    after = validation.objective
    trace["before"] = Dict("vehicles"=>before.vehicles, "distance"=>before.distance)
    trace["after"] = Dict("vehicles"=>after.vehicles, "distance"=>after.distance)
    next = successors(p, combined)
    all(i -> i in ids || next[i] == current[i], eachindex(next)) || return finish(:invalid_solution)
    remaining() > 0 || return finish(:budget_exhausted)
    # Keep a valid incumbent on ties, timeouts and non-improving fragments.
    (after.vehicles, after.distance) < (before.vehicles, before.distance-1e-8) || return finish(:no_improvement)
    move = LS.MetaMove(request.variable, next[ids];
        provenance=(source=:highs_whole_route_repair, bridged=resolver.bridged))
    finish(:improved, move)
end

end
