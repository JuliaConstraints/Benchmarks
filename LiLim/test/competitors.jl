using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
@testset "Native competitor exchanges and independent audit" begin
    d=PickupDeliveryProblem(2,2,[0. 0.;1 1;2 1;-1 1;-2 1],[0,1,-1,1,-1],zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)])
    p=BenchmarkInstance("competitor-qualification",d);initial=[[2,3],[4,5]]
    q=validate_solution(p,initial).objective
    io=IOBuffer();CompetitorAdapters.export_common_start(io,p,initial)
    @test startswith(String(take!(io)),"lilim-common-start/1 5 2 2")
    @test_throws ArgumentError CompetitorAdapters.export_common_start(devnull,p,[[2,4,3]])
    event=Dict("seconds"=>0.1,"vehicles"=>q.vehicles,"distance"=>q.distance,"routes"=>initial)
    packet=Dict("schema"=>"li-lim-timefold-native/1","qualification_checks"=>1000,
        "trials"=>[Dict("seed"=>41,"budget_seconds"=>1.,"workers"=>[Dict("worker"=>1,"trajectory"=>[event])])])
    @test only(CompetitorAdapters.audit_timefold(p,initial,packet))["original_validation"]
    bad=deepcopy(packet);bad["trials"][1]["workers"][1]["trajectory"][1]["routes"]=[[3,2],[4,5]]
    @test_throws ErrorException CompetitorAdapters.audit_timefold(p,initial,bad)
    bad=deepcopy(packet);bad["trials"][1]["workers"][1]["trajectory"][1]["distance"]+=1
    @test_throws ErrorException CompetitorAdapters.audit_timefold(p,initial,bad)
    late=deepcopy(packet);late["trials"][1]["workers"][1]["trajectory"][1]["seconds"]=1.1
    @test only(CompetitorAdapters.audit_timefold(p,initial,late))["late_incumbents_censored"]==1
    @test only(CompetitorAdapters.audit_timefold(p,initial,late))["routes"]==initial
    hexaly=Dict("schema"=>"li-lim-hexaly-native/1","vehicles"=>q.vehicles,"distance"=>q.distance,"routes"=>initial)
    @test CompetitorAdapters.audit_hexaly(p,hexaly).valid
    hexaly["routes"]=[[2,3],[2,5]]
    @test_throws ErrorException CompetitorAdapters.audit_hexaly(p,hexaly)
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=2,seconds=5,seed=41,cpus=[8,8])
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=1,seconds=0.5,seed=41,cpus=[8])
end
