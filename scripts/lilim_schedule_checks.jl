include(joinpath(@__DIR__,"..","Solvers","scripts","resources.jl"))
using Test
include(joinpath(@__DIR__,"..","src","LiLimSchedule.jl"));using .LiLimSchedule
@testset "Li-Lim time and thread policy" begin
    c=thread_configurations([(engine="cbls_jump",profile="default"),(engine="timefold_native",profile="default")])
    @test length(c.ready)==4
    @test length(c.unavailable)==2
    rows(b;failed=false)=[Dict{String,Any}("instance"=>i,"engine"=>x.engine,"profile"=>x.profile,"threads"=>x.threads,
        "seed"=>s,"budget"=>b,"state"=>failed && i=="b" ? "no_observed_feasible_incumbent" : "feasible_incumbent") for i in ["a","b"] for x in c.ready for s in 1:3]
    for b in (30,60)
        @test next_stage(b,["a","b"],c.ready,rows(b)).budget==2b
    end
    @test isempty(next_stage(120,["a","b"],c.ready,rows(120)).instances)
    @test next_stage(120,["a","b"],c.ready,rows(120;failed=true)).budget==240
    @test next_stage(240,["a","b"],c.ready,rows(240;failed=true)).instances==["b"]
    @test next_stage(240,["a","b"],c.ready,rows(240;failed=true)).budget==480
    @test isempty(next_stage(240,["a","b"],c.ready,[rows(30);rows(240;failed=true)]).instances)
    more=filter(r->r["instance"]=="b",rows(480;failed=true))
    @test next_stage(480,["b"],c.ready,more).budget==960
    more[1]["state"]="feasible_incumbent"
    @test isempty(next_stage(480,["b"],c.ready,more).instances)
    @test_throws ErrorException next_stage(480,["b"],c.ready,more[2:end])
    @test_throws ErrorException next_stage(480,["b"],c.ready,[more;more[1]])
    more[1]["state"]="execution_error"
    @test_throws ErrorException next_stage(480,["b"],c.ready,more)
    more[1]["state"]="resource_censored"
    @test_throws ErrorException next_stage(480,["b"],c.ready,more)
end
