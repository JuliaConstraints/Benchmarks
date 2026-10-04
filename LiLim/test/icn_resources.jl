using Test, ConstraintModels, JuMP, TOML, Random
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","src","MetaRepair.jl"))
include(joinpath(@__DIR__,"..","src","ICNScoring.jl"))
include(joinpath(@__DIR__,"..","src","Hybrid.jl"))
include(joinpath(@__DIR__,"..","src","ResourceExperiment.jl"))
const BANKS = Dict(kind=>ICNScoring.load_backend(kind) for kind in (:naive,:icn,:direct))

function qualify()
    @testset "Recovered ICN route zero sets and magnitude" begin
        b = BANKS[:icn]
        @test b.witnesses == [4,2,52]
        for op in ((==),(<=),(>=)), bound in (-3.,0.,2.,100.), x in (-5.5,-3.,-0.5,0.,0.5,2.,100.,100.25)
            expected = op === (==) ? abs(x-bound) : op === (<=) ? max(0.,x-bound) : max(0.,bound-x)
            @test ICNScoring.scalar(b,x,op,bound) == expected
        end
        for capacity in (1,2), tight in (false,true)
            d = PickupDeliveryProblem(2,capacity,[0. 0.;1 1;2 1;-1 1;-2 1],
                [0,1,-1,1,-1],zeros(5),tight ? [20.,1.5,3.,1.5,3.] : fill(20.,5),zeros(5),[(2,3),(4,5)])
            p = BenchmarkInstance("icn-zero-set",d);D=Pilot.distances(d)
            for tuple in Iterators.product(ntuple(_->1:5,4)...)
                values=collect(tuple)
                valid = try
                    validate_solution(p,MetaRepair.routes_from_successors(p,values)).valid
                catch error
                    error isa ArgumentError || rethrow()
                    false
                end
                direct = Hybrid.routing_score(p,D,values)
                icn = ICNScoring.score(b,p,D,values)
                naive = ICNScoring.score(BANKS[:naive],p,D,values)
                @test iszero(icn.error) == valid
                @test iszero(naive.error) == valid
                @test icn.error ≈ direct.error atol=1e-12
            end
        end
        @test b.calls > 0
        cloned = ICNScoring.clone_backend(b)
        @test cloned.calls == 0 && cloned.evaluations == 0
        @test cloned.scalar === b.scalar
        @test cloned.witnesses !== b.witnesses
        mktemp() do path,io
            payload = TOML.parsefile(ICNScoring.BANK)
            payload["witnesses"][4]["schema_sha256"] = "bad"
            TOML.print(io,payload);close(io)
            @test_throws ErrorException ICNScoring.load_backend(:icn;bank=path)
        end
    end
    @testset "Resource accounting and executable portfolios" begin
        @test ResourceExperiment.allocation("mixed_balanced",16) ==
            vcat(fill("cbls_icn",4),fill("hybrid_specialized_icn",4),fill("hybrid_bridged_icn",4),fill("highs_serial",4))
        @test length(ResourceExperiment.allocation("mixed_ls_heavy",16)) == 16
        @test_throws ArgumentError ResourceExperiment.allocation("mixed_balanced",2)
        @test_throws ArgumentError ResourceExperiment.allocation("mixed_balanced",6)
        @test ResourceExperiment.cpu_seconds() >= 0
        policy=Dict("insertion_starts"=>2,"insertion_seed"=>41,"max_visits"=>4,
            "repair_every"=>1,"fragment_seconds"=>0.1,"repair_fraction"=>0.35)
        mktemp() do path,io
            write(io,"3 1 1\n0 0 0 0 0 100 0 0 0\n1 1 1 1 0 100 0 0 2\n2 2 1 -1 0 100 0 1 0\n3 -1 1 1 0 100 0 0 4\n4 -2 1 -1 0 100 0 3 0\n5 0 10 1 0 100 0 0 6\n6 0 11 -1 0 100 0 5 0\n");close(io)
            ResourceExperiment.warmup(path,policy,BANKS)
            methods = collect(ResourceExperiment.METHODS[1:7])
            Threads.nthreads() >= 4 && append!(methods,["mixed_balanced","mixed_ls_heavy"])
            for method in methods
                record=ResourceExperiment.run_case(path,method,0.5,41,policy,BANKS)
                @test record["original_validation"]
                @test record["vehicles"] <= 3
                @test record["process_cpu_seconds"] >= 0
                @test all(e["seconds"] <= 0.5 for e in record["trajectory"])
                if method != "highs_native"
                    @test record["metastrategist_executed"]
                    @test length(unique(w["julia_thread_id"] for w in record["workers"])) == Threads.nthreads()
                    @test length(unique(w["os_thread_id"] for w in record["workers"])) == Threads.nthreads()
                else
                    @test only(record["workers"])["trace"]["highs_threads_option"] == Threads.nthreads()
                end
                for w in record["workers"]
                    if endswith(w["method"],"icn")
                        @test w["error_backend"]["icn_decoder_calls"] > 0
                    end
                end
            end
        end
    end
end
Base.invokelatest(qualify)
