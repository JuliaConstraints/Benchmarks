using Test, ConstraintModels, Random, JuMP
using ConstraintModels.Benchmarks
import LocalSearchSolvers as LS
include(joinpath(@__DIR__, "..", "src", "Pilot.jl"))
include(joinpath(@__DIR__, "..", "src", "MetaRepair.jl"))
include(joinpath(@__DIR__, "..", "src", "Hybrid.jl"))

@testset "Native CBLS hybrid controller" begin
    d = PickupDeliveryProblem(3, 1, [0. 0.;1 1;2 1;-1 1;-2 1;0 10;0 11],
        [0,1,-1,1,-1,1,-1], zeros(7), fill(100.,7), zeros(7), [(2,3),(4,5),(6,7)])
    p = BenchmarkInstance("hybrid-qualification", d)
    initial = [[2,3],[4,5],[6,7]]
    @testset "Surviving primitive route snapshots remain fully independent" begin
        for n in 1:8,target in 1:n
            base=[iseven(i) ? Int[] : [2i,2i+1] for i in 1:n]
            saved=deepcopy(base);candidate=[999,1000]
            result=Hybrid.relocation_incumbent(base,target,candidate)
            expected=[i==target ? [999,1000] : copy(base[i]) for i in 1:n if i==target || !isempty(base[i])]
            @test result==expected
            @test base==saved && candidate==[999,1000]
            @test all(route!==candidate && all(route!==buffer for buffer in base) for route in result)
            second=Hybrid.relocation_incumbent(base,target,candidate)
            @test all(a!==b for (a,b) in zip(result,second))
            first(result)[1]=-1
            @test second==expected && base==saved && candidate==[999,1000]
        end
        @test Hybrid.relocation_incumbent(Vector{Int}[],0,Int[])===nothing
        @test_throws BoundsError Hybrid.relocation_incumbent([[2,3]],2,[4,5])
    end
    @testset "Relocation scratch survives fleet changes and retains independent incumbents" begin
        distances=Pilot.distances(d);workspace=Hybrid.PairRelocationWorkspace()
        other=Hybrid.PairRelocationWorkspace()
        @test workspace.storage===nothing && other.storage===nothing
        result=Hybrid.pair_relocation(p,initial,distances,(2,3);workspace)
        retained=deepcopy(result.routes)
        buffers=copy(workspace.storage.buffers)
        merged=[[2,3,4,5],[6,7]]
        for routes in (merged,initial,[[2,3,4,5,6,7]],initial)
            original=deepcopy(routes)
            moved=Hybrid.pair_relocation(p,routes,distances,(2,3);workspace)
            reference=Hybrid.pair_relocation(p,routes,distances,(2,3))
            @test moved.routes==reference.routes && moved.examined==reference.examined
            @test routes==original
            @test result.routes==retained
            @test all(workspace.storage.buffers[i]===buffers[i] for i in eachindex(buffers))
            @test moved.routes===nothing || validate_solution(p,moved.routes).valid
        end
        Hybrid.pair_relocation(p,initial,distances,(2,3);workspace=other)
        @test workspace.storage!==other.storage
        @test workspace.storage.best_candidate!==other.storage.best_candidate
        @test workspace.candidate!==workspace.storage.best_candidate
        @test allunique(objectid(v) for v in workspace.storage.buffers)
        @test all(workspace.storage.buffers[i]!==other.storage.buffers[i] for i in eachindex(buffers))
        stopped=Hybrid.pair_relocation(p,initial,distances,(2,3);workspace,deadline_ns=UInt64(0))
        @test stopped.routes===nothing && stopped.examined==0
        @test result.routes==retained
    end
    groups=Hybrid.RouteGroupWorkspace()
    @test Hybrid.route_groups!(groups,initial,4)==[[1,2],[1,3],[2,3]]
    @test Hybrid.route_groups!(groups,initial,2)==[[1],[2],[3]]
    @test Hybrid.route_groups!(groups,initial,1)==Vector{Int}[]
    function group_allocations(workspace,routes,cap)
        Hybrid.route_groups!(workspace,routes,cap)
        @allocated Hybrid.route_groups!(workspace,routes,cap)
    end
    group_allocations(groups,initial,4)
    @test group_allocations(groups,initial,4)==0
    other=Hybrid.RouteGroupWorkspace()
    Hybrid.route_groups!(other,initial,4)
    @test other.groups!==groups.groups && other.buffers[1]!==groups.buffers[1]
    resolver=MetaRepair.HighsRouteResolver()
    first_template=MetaRepair.equality_template!(resolver,1:4)
    @test MetaRepair.equality_template!(resolver,1:4)===first_template
    @test length(resolver.bridge_templates)==1
    MetaRepair.equality_template!(resolver,1:6)
    @test length(resolver.bridge_templates)==2
    second_resolver=MetaRepair.HighsRouteResolver()
    @test MetaRepair.equality_template!(second_resolver,1:4)[2]!==first_template[2]
    # Exhaust all 625 successor assignments for a smaller two-request model,
    # including disconnected cycles and repeated incoming arcs.
    for capacity in (1,2)
        small = PickupDeliveryProblem(2, capacity, d.coordinates[1:5,:], d.demand[1:5],
            zeros(5), fill(20.,5), zeros(5), [(2,3),(4,5)])
        fixture = BenchmarkInstance("score-$capacity", small)
        D = Pilot.distances(small)
        valid_routes = Vector{Vector{Int}}[]
        for tuple in Iterators.product(ntuple(_->1:5,4)...)
            values = collect(tuple)
            expected = try
                validate_solution(fixture, MetaRepair.routes_from_successors(fixture,values)).valid
            catch error
                error isa ArgumentError || rethrow()
                false
            end
            @test iszero(Hybrid.routing_score(fixture,D,values).error) == expected
            expected && push!(valid_routes,MetaRepair.routes_from_successors(fixture,values))
        end
        canonical(routes) = sort([join(route,",") for route in routes if !isempty(route)])
        workspace = Hybrid.PairRelocationWorkspace()
        for routes in valid_routes, pair in small.pairs
            before = deepcopy(routes)
            remainder(candidate) = canonical([[i for i in route if !(i in pair)] for route in candidate])
            reachable = filter(candidate -> remainder(candidate)==remainder(routes),valid_routes)
            quality(candidate) = begin
                v = validate_solution(fixture,candidate).objective
                (v.vehicles,v.distance)
            end
            optimum = minimum(quality,reachable)
            moved = Hybrid.pair_relocation(fixture,routes,D,pair)
            chosen = moved.routes === nothing ? routes : moved.routes
            @test validate_solution(fixture,chosen).valid
            @test quality(chosen)[1] == optimum[1]
            @test quality(chosen)[2] ≈ optimum[2] atol=1e-8
            @test routes == before
            reused = Hybrid.pair_relocation(fixture,routes,D,pair;workspace)
            @test reused.examined == moved.examined
            @test reused.routes == moved.routes
            first_move=Hybrid.pair_relocation(fixture,routes,D,pair;workspace,selection=:first)
            @test first_move.examined<=moved.examined
            @test first_move.routes===nothing || (validate_solution(fixture,first_move.routes).valid && quality(first_move.routes)<quality(routes))
            @test routes == before
            # A later use must not mutate an earlier returned incumbent.
            saved = deepcopy(reused.routes)
            Hybrid.pair_relocation(fixture,routes,D,last(small.pairs);workspace)
            @test reused.routes == saved
        end
        stopped = Hybrid.pair_relocation(fixture,first(valid_routes),D,first(small.pairs);deadline_ns=UInt64(0))
        @test stopped.routes === nothing && stopped.examined==0
    end
    # Warm every operation explicitly; warm-up is outside timed assertions.
    parent = Hybrid.prepare_parent(p, initial)
    LS._step!(parent.solver)
    @test validate_solution(p, MetaRepair.routes_from_successors(p,
        collect(LS.best_values(parent.solver)))).valid
    variable = LS.MetaVariable(:warm, 1:4)
    for bridged in (false,true)
        outcome = LS.resolve_meta_variable(MetaRepair.HighsRouteResolver(;bridged),
            LS.MetaVariableRequest(variable, MetaRepair.RouteSnapshot(p,initial),20.,Xoshiro(41)))
        @test outcome.status === :improved
    end
    Hybrid.run_cbls(p,initial;seconds=0.05,hybrid=true,bridged=true,max_visits=4)
    for (hybrid,bridged) in ((false,false),(true,false),(true,true))
        result = Hybrid.run_cbls(p, initial; seconds=1., seed=41, hybrid, bridged,
            max_visits=4, repair_every=1, fragment_seconds=0.2, repair_fraction=0.5)
        @test result.validation.valid
        @test result.trace["steps"] > 0
        @test result.trace["pair_candidates"] > 0
        @test result.validation.objective.vehicles <= 3
        @test all(point["seconds"] <= 1 for point in result.trace["trajectory"])
        if hybrid
            @test !isempty(result.trace["repairs"])
            @test result.validation.objective.vehicles <= 2
        end
    end
end
