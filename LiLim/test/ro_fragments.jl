using Test, JuMP, Random, ConstraintModels
using ConstraintModels.Benchmarks
import LocalSearchSolvers as LS, MathOptInterface as MOI
include("../src/ROFragments.jl")
include("../src/Pilot.jl")
include("../src/MetaRepair.jl")
include("../src/Hybrid.jl")

function binary_fixture()
    m=Model();@variable(m,x[1:3],Bin)
    @constraint(m,sum(x)>=1);@objective(m,Min,sum(i*x[i] for i in 1:3))
    m,x
end
@testset "Native LP algorithms and bounded integer RO fragments" begin
    for (mode,lp,root) in (("mip","simplex","choose"),("mip","simplex","ipx"),
            ("mip","simplex","hipo"),("rins","simplex","choose"),("rins","ipx","choose"),
            ("rins","hipo","choose"),("local_branching","simplex","choose"))
        m,x=binary_fixture();fix(x[3],0;force=true)
        trace=Dict{String,Any}();start=time_ns();remaining()=max(0.,30-(time_ns()-start)/1e9)
        ok=ROFragments.optimize_fragment!(m;remaining,assignment=Dict(x[1]=>1.,x[2]=>1.,x[3]=>0.),
            mode,lp_solver=lp,mip_lp_solver=root,radius=1,trace)
        @test ok && termination_status(m)==MOI.OPTIMAL
        @test value(x[3])==0 && all(abs(value(v)-round(value(v)))<1e-8 for v in x)
        @test objective_value(m)≈1
        @test trace["threads"]==1 && trace["bound_scope"]=="restricted_fragment_not_global_original_bound"
        if mode=="rins"
            @test trace["lp_status"]=="OPTIMAL"
            @test trace["rins_fixed_variables"]>=1
        end
        mode=="local_branching" && @test trace["neighborhood_metric"]=="binary_hamming"
    end
    m=Model();@variable(m,2<=x<=5,Int);@objective(m,Min,x)
    @test ROFragments.optimize_fragment!(m;remaining=()->10.,assignment=Dict(x=>5.),mode="local_branching",radius=1)
    @test value(x)≈4 # L1 restriction is effective, rather than unconstrained optimum 2.
    m,x=binary_fixture()
    @test !ROFragments.optimize_fragment!(m;remaining=()->0.)
    @test_throws ArgumentError ROFragments.optimize_fragment!(m;remaining=()->1.,mode="unknown")
end

@testset "Route meta-variables retain original truth and fixed outside routes" begin
    d=PickupDeliveryProblem(3,1,[0. 0.;1 1;2 1;-1 1;-2 1;0 10;0 11],
        [0,1,-1,1,-1,1,-1],zeros(7),fill(100.,7),zeros(7),[(2,3),(4,5),(6,7)])
    p=BenchmarkInstance("ro-panel-qualification",d);initial=[[2,3],[4,5],[6,7]]
    request=LS.MetaVariableRequest(LS.MetaVariable(:routes,1:4),MetaRepair.RouteSnapshot(p,initial),30.,Xoshiro(41))
    for (mode,lp,root) in (("mip","simplex","ipx"),("mip","simplex","hipo"),
            ("rins","simplex","choose"),("rins","ipx","choose"),("local_branching","simplex","choose"))
        resolver=MetaRepair.HighsRouteResolver(;bridged=false,max_visits=4,repair_mode=mode,
            lp_solver=lp,mip_lp_solver=root,radius=8,warm_start=true)
        outcome=LS.resolve_meta_variable(resolver,request)
        @test outcome.status in (:improved,:no_improvement,:budget_exhausted)
        if outcome.move!==nothing
            candidate=MetaRepair.successors(p,initial);candidate[outcome.move.variables]=outcome.move.replacements
            routes=MetaRepair.routes_from_successors(p,candidate)
            @test validate_solution(p,routes).valid
            @test candidate[5:6]==MetaRepair.successors(p,initial)[5:6]
        end
        @test outcome.trace["repair_mode"]==mode
    end
    result=Hybrid.run_cbls(p,initial;seconds=.03,guide_mode="conditional",guide_every=1,
        search_policy="late_400",policy_overrides=(;history=32),seed=41)
    @test result.validation.valid
    @test result.trace["guide"]["authority"]=="guidance_only"
    @test all(point["seconds"]<=.03 for point in result.trace["trajectory"])
    @test initial==[[2,3],[4,5],[6,7]]
end
