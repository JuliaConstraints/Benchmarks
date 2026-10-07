using Test, Random, TOML
import LocalSearchSolvers as LS
include(joinpath(@__DIR__,"..","src","SearchPolicies.jl"))

function policy_fixture(id;seed=41)
    Random.seed!(seed)
    model=LS.model()
    foreach(_->LS.variable!(model,LS.domain(1:4)),1:4)
    LS.constraint!(model,(values;X=nothing)->abs(sum(values)-10),1:4)
    LS.objective!(model,values->sum(i*values[i] for i in eachindex(values)))
    policy=SearchPolicies.materialize(model,id)
    solver=LS.solver(model;strategies=policy.strategy,
        options=LS.Options(dynamic=false,process_threads_map=Dict(1=>1),
            print_level=:silent,log_mode=:silent,log_to_file=false,
            progress_mode=:none,use_progress_meter=false))
    LS._init!(solver)
    for i in 1:4;LS._value!(solver,i,i);end
    LS._compute!(solver)
    SearchPolicies.synchronize!(solver)
    (;solver,policy)
end

@testset "Existing strategies are materialized and execute" begin
    @test length(SearchPolicies.METHODS)==35
    @test allunique(SearchPolicies.METHODS)
    @test length(SearchPolicies.CONFIG["profiles"])==27
    @test all(row->haskey(SearchPolicies.CONFIG["profiles"],row["policy"]),values(SearchPolicies.VARIANTS))
    @test all(worker->worker=="highs_serial" || worker in SearchPolicies.METHODS,
        Iterators.flatten(values(SearchPolicies.PORTFOLIOS)))
    @test_throws ArgumentError SearchPolicies.settings("missing")
    legacy=policy_fixture("legacy")
    @test legacy.solver.strategies.tabu isa LS.NoTabu
    @test LS.restart_fraction(legacy.solver.strategies.restart)==0
    @test LS.restart_source(legacy.solver.strategies.restart)==:best
    @test !LS._guide_infeasible(legacy.solver.strategies.acceptance)
    for id in sort!(collect(keys(SearchPolicies.CONFIG["profiles"])))
        a=policy_fixture(id);b=policy_fixture(id)
        @test a.policy.description["id"]==id
        @test sum(LS.best_values(a.solver))==10
        tabu=a.solver.strategies.tabu
        if !(tabu isa LS.NoTabu)
            @test LS.tabu_list(tabu)!==LS.tabu_list(b.solver.strategies.tabu)
            LS.insert_tabu!(tabu,1,:tabu)
            @test LS.length_tabu(tabu)==1
            @test LS.length_tabu(b.solver.strategies.tabu)==0
            LS.empty_tabu!(tabu)
        end
        for _ in 1:64;LS._step!(a.solver);end
        # Random resets may be infeasible; the retained incumbent must not be.
        @test sum(LS.best_values(a.solver))==10
        @test all(v->1<=v<=4,LS.get_values(a.solver))
        SearchPolicies.synchronize!(a.solver)
        @test LS.length_tabu(a.solver.strategies)==0
        selector=a.solver.strategies.variable_selection
        selector isa LS.RemainingWorstSelector && @test selector.refresh
        if id=="compatibility"
            @test a.solver.strategies.acceptance isa LS.BestImprovingAcceptance
        elseif startswith(id,"late_")
            acceptance=a.solver.strategies.acceptance
            @test length(acceptance.history)==a.policy.description["history"]
            @test acceptance.history!==b.solver.strategies.acceptance.history
            @test acceptance.index==1
        end
    end
end

@testset "Native reset triggers and late acceptance semantics" begin
    m=LS.model();foreach(_->LS.variable!(m,LS.domain(1:4)),1:4)
    seq=SearchPolicies.materialize(m,"universal_best").strategy.restart
    @test LS.restart_fraction(seq)==0.1 && LS.restart_source(seq)==:best
    @test seq.trigger.current==64
    @test !LS.check_restart!(seq;tabu_length=0)
    seq.trigger.last_restart=seq.trigger.current
    @test LS.check_restart!(seq;tabu_length=0)
    @test SearchPolicies.sequence_resets(seq)==1
    @test seq.trigger.current==64
    exhaustion=SearchPolicies.materialize(m,"exhaustion_full").strategy.restart
    @test LS.restart_fraction(exhaustion)==1 # native zero-count convention
    exhaustion.resets=1
    @test LS.restart_fraction(exhaustion)==0.1
    exhaustion.resets=8
    @test LS.restart_fraction(exhaustion)==1
    full=SearchPolicies.materialize(m,"exhaustion_always_full").strategy.restart
    for count in (0,1,7,8,9)
        full.resets=count
        @test LS.restart_fraction(full)==1
    end
    for id in ("reset_best_full","reset_current_full","universal_best_full","universal_current_full","tabu_reset_full","tabu_random_full")
        @test LS.restart_fraction(SearchPolicies.materialize(m,id).strategy.restart)==1
    end
    a=SearchPolicies.Profiles.LateAcceptance(2)
    a.history.=[(0.,20.),(0.,20.)]
    @test LS.decide_move(a,(0.,15.),(0.,10.),Xoshiro(41))==:accepted
    @test LS.decide_move(a,(1.,0.),(0.,15.),Xoshiro(41))==:rejected
    @test LS.decide_move(a,(0.,25.),(0.,15.),Xoshiro(41))==:rejected
end

# Optional original-problem integration, with the recovered learned ICNs. This
# exercises native steps and route guards; it never invokes a HiGHS solve.
if "--routes" in ARGS
    @eval using ConstraintModels, JuMP
    @eval using ConstraintModels.Benchmarks
    for source in ("Pilot","MetaRepair","ICNScoring","Hybrid","ResourceExperiment")
        include(joinpath(@__DIR__,"..","src",source*".jl"))
    end
    @testset "ICN route policies preserve independently validated incumbents" begin
        d=PickupDeliveryProblem(3,1,[0. 0.;1 1;2 1;-1 1;-2 1;0 10;0 11],
            [0,1,-1,1,-1,1,-1],zeros(7),fill(100.,7),zeros(7),[(2,3),(4,5),(6,7)])
        p=BenchmarkInstance("strategy-route-qualification",d)
        initial=[[2,3],[4,5],[6,7]]
        bank=ICNScoring.load_backend(:icn)
        for id in sort!(collect(keys(Hybrid.SearchPolicies.CONFIG["profiles"])))
            backend=ICNScoring.clone_backend(bank)
            parent=Hybrid.prepare_parent(p,initial;search_policy=id,scorer=backend)
            for _ in 1:64;LS._step!(parent.solver);end
            @test backend.evaluations>64
            @test validate_solution(p,MetaRepair.routes_from_successors(p,collect(LS.best_values(parent.solver)))).valid
            Hybrid.run_cbls(p,initial;seconds=0.001,search_policy=id,
                scorer=ICNScoring.clone_backend(bank),hybrid=false)
            result=Hybrid.run_cbls(p,initial;seconds=0.03,search_policy=id,
                scorer=ICNScoring.clone_backend(bank),hybrid=false)
            @test result.validation.valid
            @test result.trace["search_policy"]["id"]==id
            @test all(e->e["seconds"]<=0.03,result.trace["trajectory"])
        end
        for width in (1,2,4,8,16)
            @test ResourceExperiment.allocation("cbls_icn",width)==fill("cbls_icn",width)
            @test length(ResourceExperiment.allocation("cbls_strategy_diverse",width))==width
            @test length(ResourceExperiment.allocation("mixed_strategy_diverse",width))==width
        end
        for method in Hybrid.SearchPolicies.METHODS
            c=ResourceExperiment.worker_settings(method)
            @test c.search_policy==Hybrid.SearchPolicies.VARIANTS[method]["policy"]
            @test c.bridged==get(Hybrid.SearchPolicies.VARIANTS[method],"bridged",false)
        end
        @test ResourceExperiment.worker_settings("cbls_icn_sparse_first").plateau_rejection==75
        @test ResourceExperiment.worker_settings("cbls_icn_first").pair_selection==:first
        @test ResourceExperiment.worker_settings("hybrid_bridged_icn").bridged
    end
end
