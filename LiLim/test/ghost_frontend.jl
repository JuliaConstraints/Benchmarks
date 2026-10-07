using Test, TOML
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
include(joinpath(ROOT,"SolverSmoke/src/AnytimeRunner.jl"))
include(joinpath(ROOT,"src/LiLimSchedule.jl"))

@testset "GHOST uses its Julia wrapper exclusively" begin
    project=TOML.parsefile(joinpath(ROOT,"SolverSmoke/Project.toml"))
    @test project["deps"]["GHOST"]=="11b06263-fdad-4e56-a327-8fd38a91e0b8"
    @test project["deps"]["GHOST_jll"]=="8d604a99-d805-502d-a593-62e3c19f5ba4"
    @test project["deps"]["GHOST"]!="15e77ac6-27be-4ffc-bec8-881fdb9edcea"
    @test all(c->c.engine!="ghost_native_cpp",AnytimeRunner.configurations)
    @test_throws ErrorException AnytimeRunner.command(Dict("engine"=>"ghost_native_cpp"),"warm")
    scheduled=LiLimSchedule.thread_configurations(AnytimeRunner.configurations)
    @test length(scheduled.ready)==38
    @test length(scheduled.unavailable)==4

    # Obsolete entry points must fail before importing a dependency, building,
    # downloading, solving or creating a result directory, even on a clean host.
    mktempdir() do temporary
        output=joinpath(temporary,"result.toml")
        scripts=[("LiLim/scripts/local_search_pilot.jl",["ghost","1","1","default",output]),
            ("SolverSmoke/scripts/run_ghost.jl",["missing-input",output]),
            ("SolverSmoke/scripts/build_ghost.jl",String[]),
            ("SolverSmoke/scripts/build_ghost_portable.jl",String[]),
            ("SolverSmoke/scripts/run.jl",String[])]
        for (script,args) in scripts
            cmd=`$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=1 --gcthreads=1 $(joinpath(ROOT,script)) $args`
            captured=IOBuffer()
            process=run(pipeline(ignorestatus(cmd);stdout=captured,stderr=captured))
            diagnostics=String(take!(captured))
            @test !success(process)
            @test occursin("GHOST.jl",diagnostics)
            @test occursin("disabled",diagnostics)
            @test !ispath(output)
            @test !occursin("Package ",diagnostics)
        end
    end
end
