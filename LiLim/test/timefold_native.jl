using Test,TOML,ConstraintModels
using ConstraintModels.Benchmarks
include("../src/Pilot.jl")
include("../competitors/Adapters.jl")
include("../src/NativeSolvers.jl")
const ROOT=normpath(joinpath(@__DIR__,"../.."))
const CPU=parse(Int,get(ENV,"JULIACONSTRAINTS_TEST_CPU",string(first(NativeSolvers.PlatformResources.allowed_cpus()))))
const IDENTITY=try
    NativeSolvers.resolve_timefold(;root=ROOT)
catch e
    e isa NativeSolvers.UnavailableSolver || rethrow()
    println("Skipped ",e.method,": ",e.reason);nothing
end
@testset "Actual Timefold incremental scorer and original PDPTW validation" begin
    if IDENTITY===nothing
        @test_skip false
    else
        command=NativeSolvers.timefold_command(IDENTITY,"bench.PdptwQualification";cpus=[CPU])
        result=NativeSolvers.capture(command;timeout=60)
        @test result.code==0 && !result.timed_out
        @test occursin("Qualified 480 exhaustive route partitions and 4 native FULL_ASSERT searches.",result.output)
        data=PickupDeliveryProblem(3,1,[0. 0.;1 1;2 1;-1 1;-2 1],[0,1,-1,1,-1],
            zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)])
        p=BenchmarkInstance("timefold-unit-capacity",data)
        initial=[[2,3],[4,5]]
        mktempdir() do directory
            input=joinpath(directory,"instance.txt");output=joinpath(directory,"result.toml")
            open(io->CompetitorAdapters.export_common_start(io,p,initial),input,"w")
            command=NativeSolvers.timefold_command(IDENTITY,"bench.Pdptw",input,"default","0.25","1","41",output,"assert";cpus=[CPU])
            result=NativeSolvers.capture(command;timeout=60)
            @test result.code==0 && !result.timed_out && isfile(output)
            native=TOML.parsefile(output)
            @test native["version"]=="2.6.0" && native["native_move_threads"]==0
            audited=CompetitorAdapters.audit_timefold(p,initial,native)
            @test length(audited)==1 && only(audited)["original_validation"]
            @test all(validate_solution(p,event["routes"]).valid for event in only(audited)["trajectory"])
        end
    end
end
