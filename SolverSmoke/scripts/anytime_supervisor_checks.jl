include("activate.jl")
using Test,TOML
include("../src/AnytimeRunner.jl");using .AnytimeRunner
out=datadir("anytime-checks");mkpath(out)
@testset "four-CPU process supervision" begin
    cmd=`$(Base.julia_cmd()) --startup-file=no --threads=1,0 --gcthreads=1 -e 'sleep(1)'`
    result=execute(cmd,joinpath(out,"supervisor-ok.log");wall=15.)
    @test result["exitcode"]==0
    @test result["affinity"]=="f0"
    @test !result["resource_censored"]
    @test result["peak_observed_rss_bytes"]>0
    timeout=execute(cmd,joinpath(out,"supervisor-timeout.log");wall=.1)
    @test timeout["timed_out"]
    @test timeout["resource_censored"]
    @test timeout["resource_reason"]=="process wall deadline"
end
open(io->TOML.print(io,Dict("supervisor_checks_passed"=>true)),joinpath(out,"supervisor.toml"),"w")
