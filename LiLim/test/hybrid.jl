using Test, ConstraintModels, Random, JuMP
using ConstraintModels.Benchmarks
import LocalSearchSolvers as LS
include(joinpath(@__DIR__, "..", "src", "Pilot.jl"))
include(joinpath(@__DIR__, "..", "src", "MetaRepair.jl"))
include(joinpath(@__DIR__, "..", "src", "Hybrid.jl"))

@testset "Native CBLS hybrid controller" begin
    d = PickupDeliveryProblem(3, 1, [0. 0.;1 1;2 1;-1 1;-2 1;0 10;0 11],
        [0,1,-1,1,-1,1,-1], zeros(7), fill(100.,7), zeros(7), [(2,3),(4,5),(6,7)])
    p = BenchmarkInstance("hybrid-qualification", d)
    initial = [[2,3],[4,5],[6,7]]
    # Exhaust all 625 successor assignments for a smaller two-request model,
    # including disconnected cycles and repeated incoming arcs.
    for capacity in (1,2)
        small = PickupDeliveryProblem(2, capacity, d.coordinates[1:5,:], d.demand[1:5],
            zeros(5), fill(20.,5), zeros(5), [(2,3),(4,5)])
        fixture = BenchmarkInstance("score-$capacity", small)
        D = Pilot.distances(small)
        valid_routes = Vector{Vector{Int}}[]
        for tuple in Iterators.product(ntuple(_->1:5,4)...)
            values = collect(tuple)
            expected = try
                validate_solution(fixture, MetaRepair.routes_from_successors(fixture,values)).valid
            catch error
                error isa ArgumentError || rethrow()
                false
            end
            @test iszero(Hybrid.routing_score(fixture,D,values).error) == expected
            expected && push!(valid_routes,MetaRepair.routes_from_successors(fixture,values))
        end
        canonical(routes) = sort([join(route,",") for route in routes if !isempty(route)])
        for routes in valid_routes, pair in small.pairs
            before = deepcopy(routes)
            remainder(candidate) = canonical([[i for i in route if !(i in pair)] for route in candidate])
            reachable = filter(candidate -> remainder(candidate)==remainder(routes),valid_routes)
            quality(candidate) = begin
                v = validate_solution(fixture,candidate).objective
                (v.vehicles,v.distance)
            end
            optimum = minimum(quality,reachable)
            moved = Hybrid.pair_relocation(fixture,routes,D,pair)
            chosen = moved.routes === nothing ? routes : moved.routes
            @test validate_solution(fixture,chosen).valid
            @test quality(chosen)[1] == optimum[1]
            @test quality(chosen)[2] ≈ optimum[2] atol=1e-8
            @test routes == before
        end
        stopped = Hybrid.pair_relocation(fixture,first(valid_routes),D,first(small.pairs);deadline_ns=UInt64(0))
        @test stopped.routes === nothing && stopped.examined==0
    end
    # Warm every operation explicitly; warm-up is outside timed assertions.
    parent = Hybrid.prepare_parent(p, initial)
    LS._step!(parent.solver)
    @test validate_solution(p, MetaRepair.routes_from_successors(p,
        collect(LS.best_values(parent.solver)))).valid
    variable = LS.MetaVariable(:warm, 1:4)
    for bridged in (false,true)
        outcome = LS.resolve_meta_variable(MetaRepair.HighsRouteResolver(;bridged),
            LS.MetaVariableRequest(variable, MetaRepair.RouteSnapshot(p,initial),20.,Xoshiro(41)))
        @test outcome.status === :improved
    end
    Hybrid.run_cbls(p,initial;seconds=0.05,hybrid=true,bridged=true,max_visits=4)
    for (hybrid,bridged) in ((false,false),(true,false),(true,true))
        result = Hybrid.run_cbls(p, initial; seconds=1., seed=41, hybrid, bridged,
            max_visits=4, repair_every=1, fragment_seconds=0.2, repair_fraction=0.5)
        @test result.validation.valid
        @test result.trace["steps"] > 0
        @test result.trace["pair_candidates"] > 0
        @test result.validation.objective.vehicles <= 3
        @test all(point["seconds"] <= 1 for point in result.trace["trajectory"])
        if hybrid
            @test !isempty(result.trace["repairs"])
            @test result.validation.objective.vehicles <= 2
        end
    end
end
