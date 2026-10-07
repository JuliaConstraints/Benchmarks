# Loaded after the original qualification, so these checks reuse its compiled models.
include("../src/Campaign.jl")
using .ReproductionCampaign
@testset "Bounded fragments and independent worker state" begin
    p=CASES[:bpp]
    # Fixed original bin label 3 must not force empty bin 2 to count as used.
    request=ReproductionSolvers.LS.MetaVariableRequest(ReproductionSolvers.LS.MetaVariable(:bins,[1,2]),
        (p=p,values=[1,2,3]),5.,Random.Xoshiro(41))
    first=ReproductionSolvers.LS.resolve_meta_variable(ReproductionSolvers.MIPResolver(),request)
    outcome=ReproductionSolvers.LS.resolve_meta_variable(ReproductionSolvers.MIPResolver(),request)
    @test outcome.move!==nothing
    # A repaired fragment must keep the original third item/bin fixed.
    if outcome.move!==nothing
        @test outcome.move.variables==[1,2]
        @test validate(p,vcat(outcome.move.replacements,[3])).valid
    end
    restricted=problem(:vbp,Dict("weights"=>[[1,3],[3,1],[2,2]],"capacity"=>[4,4],"max_bins"=>2))
    @test validate(restricted,initial(restricted)).valid
    r=solve_mip(restricted,ReproductionSolvers.HiGHS.Optimizer;seconds=1.)
    @test validate(restricted,r.values).valid
    if Threads.nthreads()>=2
        result=portfolio(p;workers=[(;kind=:direct,policy="tabu_short"),(;kind=:icn_fused,policy="late_400")],seconds=.01,max_steps=1)
        @test length(result)==2
        @test result[1]["seed"]!=result[2]["seed"]
    end
end
@testset "Original hashes, seals, resume and trajectory checks" begin
    manifest=selection(joinpath(ROOT,"Hexaly/config/instances.toml"))
    row=only(filter(r->r["id"]=="bpp_t60_00",manifest["instances"]))
    if !isfile(joinpath(ROOT,row["path"]));@test_skip false
    else
        bad=deepcopy(row);bad["sha256"]=repeat("0",64)
        @test_throws ErrorException load_instance(ROOT,bad)
        loaded=load_instance(ROOT,row)
        @test_throws ErrorException ReproductionCampaign.validate_trajectory(loaded.p,
            Dict("budget_seconds"=>1.,"trajectory"=>[Dict("seconds"=>2.,"values"=>initial(loaded.p),"objective"=>collect(validate(loaded.p,initial(loaded.p)).objective))]))
        mktempdir() do d
            output=joinpath(d,"sealed")
            kwargs=(ids=[row["id"]],methods=["cbls_direct"],seconds=.01,threads=1,seeds=[41],output=output)
            @test run_campaign(ROOT,manifest;kwargs...)
            @test only(TOML.parsefile(joinpath(output,"summary.toml"))["groups"])["feasible"]==1
            seals=Dict(f=>read(f,String) for f in readdir(joinpath(output,"trials");join=true) if endswith(f,".sha256"))
            @test run_campaign(ROOT,manifest;kwargs...,resume=true)
            @test all(read(f,String)==content for(f,content)in seals)
            @test_throws ErrorException run_campaign(ROOT,manifest;kwargs...,seconds=.2,resume=true)
            trial=only(filter(f->endswith(f,".toml"),readdir(joinpath(output,"trials");join=true)))
            open(io->write(io,"\n# changed original seal\n"),trial,"a")
            @test_throws ErrorException summarize(ROOT,output,manifest)
        end
    end
end
