include(joinpath(@__DIR__,"..","Solvers","scripts","resources.jl"))
using Test,TOML
include(joinpath(@__DIR__,"..","SolverSmoke","src","AnytimeRunner.jl"));using .AnytimeRunner
include(joinpath(@__DIR__,"..","src","LiLimSchedule.jl"));using .LiLimSchedule
@testset "Thread-specific native commands and controller syntax" begin
    cs=thread_configurations(configurations)
    @test length(cs.ready)==38 && length(cs.unavailable)==4
    for c in cs.ready
        job=Dict("engine"=>c.engine,"profile"=>c.profile,"threads"=>c.threads,"budget"=>480,
            "input"=>"fixture.txt","out"=>"result.toml","seed"=>1)
        args=collect(command(job,"warm.txt"))
        if c.engine=="timefold_native"
            @test "-XX:ActiveProcessorCount=1" in args
        else
            flag=c.engine=="juls_native" ? "--threads=$(c.threads)" : "--threads=$(c.threads),0"
            @test flag in args
        end
    end
    @test_throws ErrorException command(Dict("engine"=>"ghost_native_cpp"),"warm")
    job=Dict("engine"=>"timefold_native","profile"=>"default","threads"=>2,"budget"=>30,"input"=>"x","out"=>"y","seed"=>1)
    @test_throws ErrorException command(job,"warm")
    for file in ("lilim_adaptive.jl","lilim_historical_check.jl","lilim_thread_qualify.jl","lilim_thread_seal.jl","lilim_progress.jl")
        parsed=Meta.parseall(read(joinpath(@__DIR__,file),String))
        function bad(x)
            x isa Expr || return false
            x.head in (:error,:incomplete) || any(bad,x.args)
        end
        @test !bad(parsed)
    end
end
