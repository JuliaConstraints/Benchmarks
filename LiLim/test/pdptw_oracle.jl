using Test, ConstraintModels, JuMP, HiGHS
using ConstraintModels.Benchmarks
import MathOptInterface as MOI
isdefined(@__MODULE__, :Pilot) || include(joinpath(@__DIR__, "..", "src", "Pilot.jl"))

@testset "Pilot second-phase budget guard" begin
    started=UInt64(1_000_000_000)
    @test Pilot.remaining_budget(1.0,started,started+UInt64(949_000_000)) ≈ 0.051
    @test Pilot.remaining_budget(1.0,started,started+UInt64(951_000_000)) === nothing
    @test Pilot.remaining_budget(1.0,started,started+UInt64(1_000_000_000)) === nothing
end

function permutations(values)
    isempty(values) && return [Int[]]
    [[x; tail] for x in values for tail in permutations(filter(!=(x), values))]
end

@testset "PDPTW validator and fixed-arc MILP exhaustive agreement" begin
    problems = [
        PickupDeliveryProblem(2,1,zeros(5,2),[0,1,-1,1,-1],zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)]),
        PickupDeliveryProblem(2,1,[0. 0.;1 0;2 0;-1 0;-2 0],[0,1,-1,1,-1],
            [0.,1,2,1,2],[10.,1,3,1,3],zeros(5),[(2,3),(4,5)]),
        PickupDeliveryProblem(1,2,[0. 0.;1 1;2 1;-1 1;-2 1],[0,1,-1,1,-1],
            zeros(5),fill(30.,5),zeros(5),[(2,3),(4,5)])]
    checked = 0
    for (case, data) in enumerate(problems)
        p = BenchmarkInstance("exhaustive-$case", data)
        f = Pilot.model(p; threads=1, seconds=1.)
        best = (typemax(Int), Inf)
        for order in permutations(collect(2:5)), mask in 0:7
            routes = [Int[]]
            for (position, node) in enumerate(order)
                push!(last(routes), node)
                position < 4 && !iszero(mask & (1<<(position-1))) && push!(routes, Int[])
            end
            validation = validate_solution(p, routes)
            arcs = Set((i,j) for route in routes for (i,j) in zip([1;route], [route;1]))
            if all(haskey(f.x, arc) for arc in arcs)
                for (arc, variable) in f.x
                    fix(variable, arc in arcs ? 1. : 0.; force=true)
                end
                optimize!(f.m)
                @test termination_status(f.m) === (validation.valid ? MOI.OPTIMAL : MOI.INFEASIBLE)
            else
                @test !validation.valid
            end
            validation.valid && (best=min(best,(validation.objective.vehicles,validation.objective.distance)))
            checked += 1
        end
        # Separately solve the unfixed formulation and compare with the oracle.
        original = Pilot.model(p; threads=1, seconds=5.)
        solution, phases, _ = Pilot.solve!(original; seconds=5.)
        @test solution !== nothing
        if solution !== nothing
            result = validate_solution(p, solution)
            @test result.valid
            @test result.objective.vehicles == best[1]
            @test result.objective.distance ≈ best[2] atol=1e-6
        end
        @test all(phase["status"] == "OPTIMAL" for phase in phases)
    end
    @test checked == 576
end
