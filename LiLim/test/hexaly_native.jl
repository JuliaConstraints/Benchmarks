# Runs only on the colleague's licensed Hexaly Optimizer/Modeler 15.0 host.
using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))
const HEXALY = try
    NativeSolvers.resolve_hexaly(get(ENV,"HEXALY_EXECUTABLE","hexaly"))
catch e
    e isa NativeSolvers.UnavailableSolver || rethrow()
    println("Skipped ",e.method,": ",e.reason)
    nothing
end
const CPU = parse(Int,get(ENV,"JULIACONSTRAINTS_TEST_CPU",string(first(CompetitorAdapters.PlatformResources.allowed_cpus()))))
@testset "Licensed Hexaly model and original validator" begin
    if HEXALY===nothing
        @test_skip false
    else
    for zero_travel in (false,true)
        coordinates = zero_travel ? zeros(5,2) : [0. 0.;1 1;2 1;-1 1;-2 1]
        d = PickupDeliveryProblem(3,1,coordinates,[0,1,-1,1,-1],zeros(5),fill(30.,5),[0.5,0.,0.,0.,0.],[(2,3),(4,5)])
        p = BenchmarkInstance("hexaly-qualification",d); initial = [[2,3],[4,5]]
        mktempdir() do directory
            input = joinpath(directory,"input.txt"); output = joinpath(directory,"native.toml")
            epoch = floor(Int,time()*1000)
            open(io->CompetitorAdapters.export_common_start(io,p,initial),input,"w")
            run(CompetitorAdapters.hexaly_command(HEXALY,input,output;threads=1,seconds=8,seed=41,cpus=[CPU],trial_start_epoch_ms=epoch))
            final = TOML.parsefile(output); trace = TOML.parsefile(output*".trajectory.toml")
            audited = CompetitorAdapters.audit_hexaly_trial(p,initial,final,trace;budget_seconds=8)
            @test audited["original_validation"] && audited["within_budget_feasible"]
            @test validate_solution(p,final["routes"]).valid
            @test audited["vehicles"] == 1
            @test all(validate_solution(p,e["routes"]).valid for e in audited["trajectory"])
        end
    end
    end
end
