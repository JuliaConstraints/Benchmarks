module StrategyPanelQualification
using Test, Random, TOML
include("../src/Reproduction.jl")
using .HexalyReproduction.ReproductionProblems
const ReproductionProblems=HexalyReproduction.ReproductionProblems
const S=HexalyReproduction.ReproductionSolvers
const C=HexalyReproduction.ReproductionCampaign
include("fixtures.jl")
const CASES=fixtures()

@testset "Classical strategy lanes, guide proposals and ownership" begin
    for f in (:bpp,:jssp,:tsp),policy in ("tabu_short","late_400","universal_current_full")
        p=CASES[f];lane=S.prepare_cbls(p;kind=:icn_fused,policy,guide_mode="conditional",guide_every=1)
        result=Base.invokelatest(S.search!,lane;seconds=.03,max_steps=2)
        @test result["steps"]<=2
        @test all(row->validate(p,row["values"]).valid,result["trajectory"])
        @test result["guide"]["authority"]=="guidance_only"
    end
    a=S.prepare_cbls(CASES[:bpp];kind=:direct,guide_mode="absolute")
    b=S.prepare_cbls(CASES[:bpp];kind=:direct,guide_mode="absolute")
    @test a.candidate!==b.candidate && a.workspace.active!==b.workspace.active
    lanes=(a,);result=S.portfolio(CASES[:bpp];workers=[(;kind=:direct)],prepared_lanes=lanes,seconds=.03,max_steps=2)
    @test length(result)==1 && result[1]["steps"]<=2
end
@testset "Semantic integer repairs preserve original decisions" begin
    LS=S.LS
    for f in (:bpp,:jssp,:fjsp),mode in ("mip","rins","local_branching")
        p=CASES[f];current=initial(p);ids=collect(eachindex(current))[1:end-1]
        request=LS.MetaVariableRequest(LS.MetaVariable(:fragment,ids),(;p,values=current),20.,Xoshiro(41))
        resolver=S.MIPResolver(;mode,lp_solver="ipx",warm_start=true,radius=4)
        outcome=LS.resolve_meta_variable(resolver,request)
        @test outcome.trace["mode"]==mode
        if outcome.move!==nothing
            candidate=copy(current);candidate[outcome.move.variables]=outcome.move.replacements
            @test candidate[end]==current[end]
            @test validate(p,candidate).valid
        end
    end
    p=CASES[:bpp];row=Dict("id"=>"fixture","sha256"=>repeat("a",64))
    id=first(S.StrategyPanel.methods(:meta))
    result=Base.invokelatest(C.solve,dirname(dirname(@__DIR__)),row,p,"",id;seconds=.03,threads=1,seed=41,max_cells=250_000)
    @test result["strategy_panel"]["workers"]==1
    @test all(event->validate(p,event["values"]).valid,result["trajectory"])
    bridge=first(filter(id->occursin("bridge_ro",id),S.StrategyPanel.methods(:meta)))
    @test C.solve("",row,p,"",bridge;seconds=.03,threads=4,seed=41,max_cells=250_000)["status"]=="unsupported_model"
end
end # module
