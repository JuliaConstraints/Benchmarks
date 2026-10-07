using Test
include(joinpath(@__DIR__, "..", "src", "BenchmarkTargets.jl"))
using .BenchmarkTargets

@testset "SINTEF published-precision BKS attainment" begin
    @test REPORTED_DISTANCE_DIGITS == 2
    @test reaches_published_bks(10, 828.9449, 10, 828.94)
    @test !reaches_published_bks(10, 828.9451, 10, 828.94)
    @test reaches_published_bks(9, 9_999.0, 10, 828.94)
    @test !reaches_published_bks(11, 1.0, 10, 828.94)
    @test !reaches_published_bks(10, NaN, 10, 828.94)
    @test !reaches_published_bks(10, Inf, 10, 828.94)
    @test_throws ArgumentError reaches_published_bks(10, 1.0, 10, 1.0; distance_digits=-1)
    @test_throws ArgumentError reaches_published_bks(10, 1.0, 10, Inf)
end
