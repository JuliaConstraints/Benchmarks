using Test, Random, ConstraintModels, JuMP
using ConstraintModels.Benchmarks
import LocalSearchSolvers as LS
include(joinpath(@__DIR__, "..", "src", "Pilot.jl"))
include(joinpath(@__DIR__, "..", "src", "MetaRepair.jl"))
using .MetaRepair

@testset "Whole-route meta-variable RO repair" begin
    # Two free requests and a distant frozen third request. Integer capacity,
    # continuous time/distance, and a known fleet improvement from 3 to 2.
    coordinates = [0. 0.; 1 1; 2 1; -1 1; -2 1; 0 10; 0 11]
    d = PickupDeliveryProblem(3, 1, coordinates, [0,1,-1,1,-1,1,-1],
        zeros(7), fill(100.,7), zeros(7), [(2,3),(4,5),(6,7)])
    p = BenchmarkInstance("three-requests", d)
    initial = [[2,3],[4,5],[6,7]]
    s = RouteSnapshot(p, initial)
    variable = LS.MetaVariable(:two_routes, 1:4)
    request(seconds) = LS.MetaVariableRequest(variable, s, seconds, Xoshiro(41))
    @test routes_from_successors(p, s.values) == initial
    @test_throws ArgumentError routes_from_successors(p, [3,2,5,1,7,1])
    @test_throws ArgumentError routes_from_successors(p, [3,1,3,1,7,1])
    @test LS.resolve_meta_variable(HighsRouteResolver(), request(0)).status === :budget_exhausted
    @test LS.resolve_meta_variable(HighsRouteResolver(max_visits=2), request(10)).status === :resource_limited
    @test LS.resolve_meta_variable(HighsRouteResolver(), request(1e-9)).status === :budget_exhausted
    partial = LS.MetaVariableRequest(LS.MetaVariable(:partial, [1]), s, 10., Xoshiro(41))
    @test LS.resolve_meta_variable(HighsRouteResolver(), partial).status === :invalid_fragment
    outcomes = []
    for bridged in (false, true)
        outcome = LS.resolve_meta_variable(HighsRouteResolver(;bridged), request(20))
        @test outcome.status === :improved
        @test outcome.move isa LS.MetaMove
        outcome.move === nothing && continue
        values = [LS.value_after(outcome.move, s.values, i) for i in eachindex(s.values)]
        routes = routes_from_successors(p, values)
        result = validate_solution(p, routes)
        @test result.valid
        @test result.objective.vehicles == 2
        @test values[5:6] == s.values[5:6]
        @test LS.affected_variables(outcome.move) == [1,2,3,4]
        @test s.routes == initial && s.values == successors(p, initial)
        @test outcome.elapsed_seconds <= 20
        @test outcome.trace["threads"] == 1
        @test outcome.trace["outside_routes"] == 1
        @test outcome.trace["fragment_visits"] == 4
        @test length(outcome.trace["bridge_programs"]) == (bridged ? 2 : 0)
        @test all(phase["status"] == "OPTIMAL" for phase in outcome.trace["phases"])
        push!(outcomes, outcome)
    end
    @test length(outcomes) == 2
    if length(outcomes) == 2
        @test outcomes[1].trace["after"]["distance"] ≈ outcomes[2].trace["after"]["distance"] atol=1e-6
        @test outcomes[2].trace["variables"] > outcomes[1].trace["variables"]
        @test outcomes[2].trace["constraints"] > outcomes[1].trace["constraints"]
    end
    # The adapter cannot apply a repair to a changed parent snapshot.
    s.routes[1] = [3,2]
    @test_throws ArgumentError LS.resolve_meta_variable(HighsRouteResolver(), request(10))
end
