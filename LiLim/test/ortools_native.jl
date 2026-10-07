using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__, "..", "src", "Pilot.jl"))
include(joinpath(@__DIR__, "..", "competitors", "Adapters.jl"))

const PYTHON = get(ENV, "ORTOOLS_PYTHON", joinpath(@__DIR__, "..", "native", "ortools", ".venv", "bin", "python"))
const RUNNER = normpath(joinpath(@__DIR__, "..", "native", "ortools", "pdptw.py"))
const CPU = parse(Int, get(ENV, "JULIACONSTRAINTS_TEST_CPU", "8"))

@testset "Actual OR-Tools 9.14 GLS and original PDPTW validation" begin
    for (name, capacity, coordinates, ready, due, service) in (
        ("fractional depot service and padded empty vehicle", 2,
            [0. 0.;1 1;2 1;-1 1;-2 1], fill(0.25,5), fill(30.75,5), [0.5,0.1,0.1,0.1,0.1]),
        ("unit capacity and pickup precedence", 1,
            [0. 0.;1 1;2 1;-1 1;-2 1], zeros(5), fill(20.,5), zeros(5)),
        ("zero travel requires actual pickup order", 1,
            zeros(5,2), zeros(5), fill(1.,5), zeros(5)))
        @testset "$name" begin
            d = PickupDeliveryProblem(3,capacity,coordinates,[0,1,-1,1,-1],ready,due,service,[(2,3),(4,5)])
            p = BenchmarkInstance(name,d); initial = [[2,3],[4,5]]
            @test validate_solution(p,initial).valid
            mktempdir() do directory
                input = joinpath(directory,"input.txt"); output = joinpath(directory,"output.toml")
                epoch = round(Int,time()*1e9)
                open(io->CompetitorAdapters.export_common_start(io,p,initial),input,"w")
                run(CompetitorAdapters.ortools_command(PYTHON,RUNNER,input,output;
                    seconds=3,seed=41,trial_start_epoch_ns=epoch,cpus=[CPU]))
                native = TOML.parsefile(output)
                @test native["solver_status"] == "solution"
                @test native["common_start_accepted"]
                @test native["solver_seconds"] > 0
                @test native["search_start_seconds"] < 3
                @test native["internal_search_threads"] == 1
                @test native["guided_local_search"]
                @test !native["seed_used_by_routing_search"]
                audited = CompetitorAdapters.audit_ortools_trial(p,initial,native;budget_seconds=3)
                @test audited["original_validation"]
                @test audited["vehicles"] == 1
                @test all(e["seconds"] <= 3 for e in audited["trajectory"])
                @test all(validate_solution(p,e["routes"]).valid for e in audited["trajectory"])
                bad = deepcopy(native); bad["routes"] = [[3,2,4,5]]
                @test_throws ErrorException CompetitorAdapters.audit_ortools_trial(p,initial,bad;budget_seconds=3)
            end
        end
    end
end
