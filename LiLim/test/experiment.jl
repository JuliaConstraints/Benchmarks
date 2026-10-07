using Test, ConstraintModels, TOML, JuMP
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","src","MetaRepair.jl"))
include(joinpath(@__DIR__,"..","src","Hybrid.jl"))
include(joinpath(@__DIR__,"..","src","Experiment.jl"))
config = TOML.parsefile(joinpath(@__DIR__,"..","config","current-pilot.toml"))

@testset "Timed original-problem evidence" begin
    # Force an improving fleet incumbent and ensure the C callback's column
    # mapping returns a valid route, without retaining HiGHS-owned memory.
    p = read_benchmark(IOBuffer(Experiment.WARMUP_TEXT),:li_lim)
    f = Pilot.model(p;threads=1,seconds=20.)
    original = [[2,3],[4,5],[6,7]]
    Pilot.warmstart!(f,original)
    events = Any[]
    Pilot.observe_incumbents!(f,routes->push!(events,deepcopy(routes)))
    solution,_,_ = Pilot.solve!(f;seconds=20.)
    @test !isempty(events)
    @test all(routes->validate_solution(p,routes).valid,events)
    @test minimum(routes->validate_solution(p,routes).objective.vehicles,events)==1
    @test validate_solution(p,solution).valid
    Experiment.warmup(config["policy"])
    mktemp() do path,io
        write(io,Experiment.WARMUP_TEXT);close(io)
        for method in config["methods"]
            record = Experiment.run_case(path,method,1.,41,config["policy"])
            @test record["eligible"]
            @test validate_solution(p,record["routes"]).valid
            @test record["routes_source_node_ids"] == [r.-1 for r in record["routes"]]
            @test all(event["seconds"]<=1 for event in record["trajectory"])
            @test last(record["trajectory"])["vehicles"]==record["vehicles"]
            @test last(record["trajectory"])["distance"]==record["distance"]
            # Round-trip actual traces (including bridge programs) through the
            # immutable evidence format used by the campaign.
            mktempdir() do dir
                resultpath = joinpath(dir,"result.toml")
                Experiment.save_record(resultpath,record)
                parsed = TOML.parsefile(resultpath)
                @test parsed["routes"]==record["routes"]
                @test parsed["distance"]==record["distance"]
                @test_throws ErrorException Experiment.save_record(resultpath,record)
            end
        end
        late = Experiment.run_case(path,"cbls",1e-9,41,config["policy"])
        @test !late["eligible"] && isempty(late["trajectory"])
        @test_throws ArgumentError Experiment.run_case(path,"unknown",1.,41,config["policy"])
    end
end
