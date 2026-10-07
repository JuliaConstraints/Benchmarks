using Test,TOML,Random
include("../src/Problems.jl")
include("../src/Readers.jl")
include("../src/Scoring.jl")
include("../src/Solvers.jl")
include("fixtures.jl")
using .ReproductionProblems,.ReproductionReaders,.ReproductionScoring,.ReproductionSolvers
const CASES=fixtures()
@testset "Original validators and quantitative/ICN zero sets" begin
    @test Set(keys(CASES))==Set(FAMILY_IDS)
    backends=[prepare_backend(k) for k in (:naive,:direct,:icn,:icn_fused)]
    for (f,p) in CASES
        ds=domains(p);@test !validate(p,[first(r) for r in ds[1:end-1]]).valid
        @test !validate(p,fill(NaN,length(ds))).valid
        @test !validate(p,[last(r)+1 for r in ds]).valid
        @test !validate(p,[first(r)+.5 for r in ds]).valid
        @test prod(length.(ds))<=10_000
        for tuple in Iterators.product(ds...)
            x=collect(tuple);checked=validate(p,x)
            direct=Base.invokelatest(error_value,backends[2],p,x)
            @test iszero(direct)==checked.valid
            @test Base.invokelatest(search_objective_value,backends[2],p,x)≈ReproductionScoring.objective_value(p,x)
            for b in backends
                e=Base.invokelatest(error_value,b,p,x)
                @test isfinite(e) && e>=0 && iszero(e)==checked.valid
                b.kind in (:icn,:icn_fused) && @test e≈direct
            end
        end
    end
    @test validate(CASES[:qap],[1,2]).objective==(big(14),)
    @test validate(CASES[:mssc],[1,1,2]).objective[1]≈2.
    @test validate(CASES[:tsp],[1,2,3]).objective==(4.,)
    @test validate(CASES[:top],[1,2,1,1]).objective==(-9.,)
    @test validate(CASES[:maintenance],[1,2]).objective[1]≈1.25
    @test search_objective_value(backends[2],CASES[:bpp],[NaN,1,2])==Inf
    @test search_objective_value(backends[2],CASES[:bpp],[1,1])==Inf
    @test !validate(CASES[:maintenance],[1,1]).valid
    @test_throws ArgumentError problem(:jssp,Dict("duration"=>[1,1],"machine"=>[1,2],"precedence"=>[[1,2],[2,1]],"horizon"=>2))
    @test_throws ArgumentError problem(:qap,Dict("flow"=>[[1]],"distance"=>[[0,1],[1,0]]))
end
@testset "Packing callback buffers reduce allocation pressure" begin
    p=CASES[:bpp];a=prepare_backend(:direct);b=prepare_backend(:direct);x=[1,2,3]
    error_value(a,p,x);error_value(b,p,x)
    @test a.workspace!==b.workspace && a.workspace.integers!==b.workspace.integers
    function objective_allocations(backend,p,x)
        search_objective_value(backend,p,x);ReproductionScoring.objective_value(p,x)
        optimized=@allocated for _ in 1:1024;search_objective_value(backend,p,x);end
        oracle=@allocated for _ in 1:1024;ReproductionScoring.objective_value(p,x);end
        (;optimized,oracle)
    end
    objective_allocations(a,p,x)
    bytes=objective_allocations(a,p,x)
    @test bytes.optimized<bytes.oracle÷8
    icn=prepare_backend(:icn);fused=prepare_backend(:icn_fused)
    @test icn.decoder===fused.decoder
    @test icn.input!==fused.input && icn.residuals!==fused.residuals
    clones=Vector{Any}(undef,Threads.nthreads())
    Threads.@threads :static for i in eachindex(clones)
        clones[i]=prepare_backend(:icn_fused)
        for _ in 1:100;Base.invokelatest(error_value,clones[i],p,i%2==0 ? [1,1,1] : x);end
    end
    @test all(b->b.decoder===icn.decoder && b.calls==100,clones)
    @test allunique(objectid(b.input) for b in clones)
    mktemp() do path,io
        original=joinpath(@__DIR__,"../../LiLim/resources/icn-pdptw-witnesses.toml")
        row=TOML.parsefile(original);row["witnesses"][4]["schema_sha256"]="invalid"
        TOML.print(io,row);close(io)
        @test_throws ErrorException prepare_backend(:icn;bank=path)
        @test prepare_backend(:icn).decoder===icn.decoder
    end
end
@testset "Original reader boundaries and metrics" begin
    mktempdir() do d
        path=joinpath(d,"original")
        write(path,"NAME: triangle\nTYPE: TSP\nDIMENSION: 3\nEDGE_WEIGHT_TYPE: EUC_2D\nNODE_COORD_SECTION\n1 0 0\n2 3 0\n3 3 4\nEOF\n")
        p=read_problem(path;family=:tsp);@test validate(p,[1,2,3]).objective==(12.,)
        for (metric,cost) in ((:EUC_2D,5.),(:CEIL_2D,5.),(:MAN_2D,7.),(:MAX_2D,4.),(:ATT,2.),(:euclidean,5.))
            @test CoordinateDistances([0. 0.;3. 4.],metric)[1,2]==cost
        end
        @test CoordinateDistances([0. 0. 0.;1. 2. 3.],:MAN_3D)[1,2]==6
        @test CoordinateDistances([16.47 96.10;16.47 94.44],:GEO)[1,2]==153
        write(path,"2\n0 3 4 0\n0 2 2 0\n");@test validate(read_problem(path;family=:qap),[1,2]).objective==(big(14),)
        write(path,"3\n4\n2 2 3\n");@test validate(read_problem(path;family=:bpp),[1,1,2]).valid
        write(path,"2\n4 4\n3\n1 3\n3 1\n2 2\n3\n");@test validate(read_problem(path;family=:vbp),[1,1,2]).valid
        write(path,"n 4\nm 1\ntmax 4\n0 0 0\n1 0 4\n2 0 5\n3 0 0\n");@test validate(read_problem(path;family=:top),[1,2,1,1]).objective==(-9.,)
        write(path,"3 1 2 1 2 1\n1 2 1\n1 2 1\n2 1 0\n0 0 1\n")
        p=read_problem(path;family=:car_sequencing);@test validate(p,[1,2]).valid;@test p.data["history"]==[3]
        write(path,"2 1\n1 2 1 1 3 1\n1 1 1 2\n")
        @test_throws Exception read_problem(path;family=:fjsp)
        @test_throws ArgumentError read_problem(path;family=:irp)
    end
end
@testset "CBLS front end and existing strategies execute bounded steps" begin
    for (f,p) in CASES
        lane=prepare_cbls(p;kind=:direct)
        result=Base.invokelatest(search!,lane;seconds=.01,max_steps=1)
        @test result["steps"]<=1
        @test all(row->validate(p,row["values"]).valid,result["trajectory"])
    end
    for policy in POLICIES
        lane=prepare_cbls(CASES[:bpp];policy,kind=:icn_fused)
        result=Base.invokelatest(search!,lane;seconds=.01,max_steps=1)
        @test result["policy"]["id"]==policy
    end
    # Real MetaStrategist API with a single lane also qualifies 1-thread hosts.
    result=portfolio(CASES[:bpp];seconds=.01,max_steps=1,workers=[(;kind=:icn_fused,policy="late_400")])
    @test length(result)==1
end
@testset "Optional exact HiGHS formulations" begin
    import HiGHS
    for f in (:bpp,:bppc,:vbp,:rcpsp,:jssp,:fjsp,:salbp,:aircraft_landing)
        p=CASES[f];r=solve_mip(p,HiGHS.Optimizer;seconds=1.)
        @test !isempty(r.values) && validate(p,r.values).valid
        optimum=minimum(validate(p,collect(x)).objective[1] for x in Iterators.product(domains(p)...) if validate(p,collect(x)).valid)
        @test validate(p,r.values).objective[1]≈optimum
        @test r.bound<=optimum+1e-6
    end
    @test_throws ArgumentError mip_model(CASES[:rcpsp];max_cells=1)
end
