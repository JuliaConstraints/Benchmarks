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
    one_route=[[2,3,4,5]]; one_route_q=validate_solution(p,one_route).objective
    final=Dict("schema"=>"li-lim-hexaly-native/1","vehicles"=>one_route_q.vehicles,
        "distance"=>one_route_q.distance,"routes"=>one_route,"seconds"=>1.1)
    trace=Dict("schema"=>"li-lim-hexaly-trajectory/1","trajectory"=>[
        Dict("seconds"=>0.2,"vehicles"=>one_route_q.vehicles,"distance"=>one_route_q.distance,"routes"=>one_route),
        Dict("seconds"=>1.2,"vehicles"=>one_route_q.vehicles,"distance"=>one_route_q.distance,"routes"=>one_route)])
    audited=CompetitorAdapters.audit_hexaly_trial(p,initial,final,trace;budget_seconds=1.,clock_offset_seconds=0.3)
    @test audited["routes"]==one_route
    @test length(audited["trajectory"])==2
    @test audited["trajectory"][1]["seconds"]==0.3
    @test audited["trajectory"][2]["seconds"]==0.5
    @test audited["audited_incumbents"]==1
    @test audited["late_incumbents_censored"]==2
    bad_trace=deepcopy(trace);bad_trace["trajectory"][1]["routes"]=[[3,2,4,5]]
    @test_throws ErrorException CompetitorAdapters.audit_hexaly_trial(p,initial,final,bad_trace;budget_seconds=1.,clock_offset_seconds=0.3)
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=2,seconds=5,seed=41,cpus=[8,8])
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=1,seconds=0.5,seed=41,cpus=[8])
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=2,seconds=60,seed=41,cpus=[8])
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=8.0,seconds=60,seed=41,cpus=collect(0:7))
    automatic=CompetitorAdapters.hexaly_command("hexaly","in","out";threads=0,seconds=60,seed=41,
        cpus=[8,10,0,2,4,6,12,14])
    @test "hxNbThreads=0" in automatic.exec
    @test "hxTimeLimit=50,10" in automatic.exec
    @test "trajectoryFileName=out.trajectory.toml" in automatic.exec
    @test "hxTimeBetweenDisplays=1" in automatic.exec
    long=CompetitorAdapters.hexaly_command("hexaly","in","out";threads=16,seconds=600,seed=41,
        cpus=collect(0:15))
    @test "hxTimeLimit=500,100" in long.exec
    @test_throws ArgumentError CompetitorAdapters.hexaly_command("hexaly","in","out";threads=0,seconds=60,seed=41,cpus=Int[])
end
