include("activate.jl")
using Test, TOML, SHA
include(projectdir("vendor","formulations","Benchmarks.jl"))
include(srcdir("Pilot.jl"))
using .Benchmarks
import MathOptInterface as MOI

function permutations(v)
    isempty(v) && return [Int[]]
    [[x;tail] for x in v for tail in permutations(filter(!=(x),v))]
end
function oracle(p)
    best=(typemax(Int),Inf)
    for order in permutations(collect(2:length(p.data.demand)))
        for mask in 0:(1<<(length(order)-1))-1
            routes=[Int[]]
            for (i,x) in enumerate(order)
                push!(last(routes),x)
                i<length(order) && !iszero(mask & (1<<(i-1))) && push!(routes,Int[])
            end
            v=validate_solution(p,routes)
            if v.valid
                best=min(best,(v.objective.vehicles,v.objective.distance))
            end
        end
    end
    best
end

@testset "Compact PDPTW against exhaustive routes" begin
    problems=[
        PickupDeliveryProblem(2,1,zeros(5,2),[0,1,-1,1,-1],zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)]),
        PickupDeliveryProblem(2,1,[0. 0.;1 0;2 0;-1 0;-2 0],[0,1,-1,1,-1],
            [0.,1,2,1,2],[10.,1,3,1,3],zeros(5),[(2,3),(4,5)]),
        PickupDeliveryProblem(1,2,[0. 0.;1 1;2 1;-1 1;-2 1],[0,1,-1,1,-1],
            zeros(5),fill(30.,5),zeros(5),[(2,3),(4,5)])]
    for (i,d) in enumerate(problems)
        p=BenchmarkInstance("oracle-$i",d)
        ref=oracle(p)
        f=Pilot.model(p;threads=length(COMPARISON_CPUS),seconds=5.0)
        start=Pilot.insertion(p)
        @test start!==nothing
        Pilot.warmstart!(f,start)
        solution,phases,_=Pilot.solve!(f;seconds=5.0)
        @test solution!==nothing
        v=validate_solution(p,solution)
        @test v.valid
        @test v.objective.vehicles==ref[1]
        @test v.objective.distance≈ref[2] atol=1e-6
        @test last(phases)["status"]=="OPTIMAL"
    end
    # With one vehicle the overlapping-window instance is infeasible.
    d=problems[2]
    p=BenchmarkInstance("infeasible",PickupDeliveryProblem(1,d.capacity,d.coordinates,d.demand,d.earliest,d.latest,d.service,d.pairs))
    @test oracle(p)[1]==typemax(Int)
    f=Pilot.model(p;threads=length(COMPARISON_CPUS),seconds=5.0)
    solution,phases,_=Pilot.solve!(f;seconds=5.0)
    @test solution===nothing
    @test phases[1]["status"]=="INFEASIBLE"
end
