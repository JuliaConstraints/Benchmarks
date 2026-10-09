using Test, ConstraintModels, Random
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))

@testset "Insertion probes preserve every insertion position" begin
    buffer=Int[];sizehint!(buffer,128)
    for n in 0:40, a in 1:n+1, b in a+1:n+2
        route=collect(1:n);saved=copy(route)
        expected=copy(route);insert!(expected,a,-1);insert!(expected,b,-2)
        @test Pilot.insertion_candidate!(buffer,route,a,b,-1,-2)===buffer
        @test buffer==expected
        @test route==saved
    end
    function probe_allocations(buffer,route)
        Pilot.insertion_candidate!(buffer,route,10,20,-1,-2)
        @allocated Pilot.insertion_candidate!(buffer,route,10,20,-1,-2)
    end
    route=collect(1:40)
    probe_allocations(buffer,route)
    @test probe_allocations(buffer,route)==0
end

@testset "Insertion returns independent feasible routes" begin
    data=PickupDeliveryProblem(3,1,[0. 0.;1 1;2 1;-1 1;-2 1;0 10;0 11],
        [0,1,-1,1,-1,1,-1],zeros(7),fill(100.,7),zeros(7),[(2,3),(4,5),(6,7)])
    problem=BenchmarkInstance("insertion-workspace",data)
    a=Pilot.insertion(problem;starts=5,seed=41)
    b=Pilot.insertion(problem;starts=5,seed=41)
    @test validate_solution(problem,a).valid
    @test a==b
    @test allunique(objectid(route) for route in a)
    @test all(x!==y for x in a for y in b)
    first(a)[1]=-1
    @test validate_solution(problem,b).valid
end
