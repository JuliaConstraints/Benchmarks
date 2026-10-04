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
                @test icn.distance == direct.distance
                @test icn.vehicles == direct.vehicles
            end
        end
        @test b.calls > 0
        cloned = ICNScoring.clone_backend(b)
        @test cloned.calls == 0 && cloned.evaluations == 0
        @test cloned.scalar === b.scalar
        @test cloned.witnesses !== b.witnesses
        @test cloned.workspace !== b.workspace
        @test cloned.workspace.pair !== b.workspace.pair
        @test cloned.workspace.scalar_real !== b.workspace.scalar_real
        mktemp() do path,io
            payload = TOML.parsefile(ICNScoring.BANK)
            payload["witnesses"][4]["schema_sha256"] = "bad"
            TOML.print(io,payload);close(io)
            @test_throws ErrorException ICNScoring.load_backend(:icn;bank=path)
        end
    end
    @testset "Private scoring workspaces and allocation regression" begin
        d = PickupDeliveryProblem(2,2,[0. 0.;1 1;2 1;-1 1;-2 1],
            [0,1,-1,1,-1],zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)])
        p = BenchmarkInstance("workspace",d);D=Pilot.distances(d)
        values = [3,1,5,1]; b=ICNScoring.clone_backend(BANKS[:icn])
        expected = Hybrid.routing_score(p,D,values)
        for invalid in ([1,1,1], [0,1,1,1], [NaN,1,1,1], [Inf,1,1,1],
                [1.5,1,1,1], [6,1,1,1], [3,2,5,4], [3,3,1,1])
            @test ICNScoring.score(b,p,D,invalid)==(error=1.,distance=Inf,vehicles=typemax(Int))
            @test ICNScoring.score(b,p,D,values)==expected
        end
        @test ICNScoring.score(b,p,D,Float64.(values))==expected
        # Measure inside a specialized function, after compiling both score paths.
        function allocation_bytes(b,p,D,values)
            ICNScoring.score(b,p,D,values)
            @allocated ICNScoring.score(b,p,D,values)
        end
        allocation_bytes(b,p,D,values)
        @test allocation_bytes(b,p,D,values)==0
        invalid=[3,2,5,4]
        allocation_bytes(b,p,D,invalid)
        @test allocation_bytes(b,p,D,invalid)==0
        lanes=[ICNScoring.clone_backend(b) for _ in 1:Threads.nthreads()]
        scores=Vector{typeof(expected)}(undef,length(lanes))
        Threads.@threads :static for lane in eachindex(lanes)
            for _ in 1:1000
                scores[lane]=ICNScoring.score(lanes[lane],p,D,values)
                ICNScoring.score(lanes[lane],p,D,invalid)
            end
        end
        @test all(==(expected),scores)
        @test length(unique(objectid(lane.workspace.pair) for lane in lanes))==length(lanes)
        @test length(unique(objectid(lane.workspace.route_of) for lane in lanes))==length(lanes)
        route_workspace=MetaRepair.SuccessorRouteWorkspace()
        routes=MetaRepair.routes_from_successors!(route_workspace,p,values)
        @test routes==MetaRepair.routes_from_successors(p,values)
        snapshot=MetaRepair.RouteSnapshot(p,routes)
        decoded=MetaRepair.routes_from_successors!(route_workspace,p,[3,4,5,1])
        @test decoded==[[2,3,4,5]]
        @test snapshot.routes==[[2,3],[4,5]]
        @test routes===decoded
        function decode_allocations(workspace,p,values)
            MetaRepair.routes_from_successors!(workspace,p,values)
            @allocated MetaRepair.routes_from_successors!(workspace,p,values)
        end
        decode_allocations(route_workspace,p,values)
        @test decode_allocations(route_workspace,p,values)==0
        @test_throws ArgumentError MetaRepair.routes_from_successors!(route_workspace,p,invalid)
        @test_throws DimensionMismatch MetaRepair.routes_from_successors!(route_workspace,p,[1])
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
