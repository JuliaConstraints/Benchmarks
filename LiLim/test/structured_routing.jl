using Test, Random, TOML, ConstraintModels, JuMP, LinearAlgebra
using ConstraintModels.Benchmarks
include("../src/Pilot.jl")
include("../src/MetaRepair.jl")
include("../src/ICNScoring.jl")
include("../src/Hybrid.jl")
include("../src/ResourceExperiment.jl")
include("../src/CampaignCatalog.jl")
include("../src/PanelPlotStyles.jl")
const R=ResourceExperiment.StructuredRouting
const PANEL=ResourceExperiment.RoutingPanel
const DATA=PickupDeliveryProblem(4,2,[0. 0.;1 0;2 0;-1 0;-2 0;0 1;0 2],
    [0,1,-1,1,-1,1,-1],zeros(7),fill(40.,7),zeros(7),[(2,3),(4,5),(6,7)])
const P=BenchmarkInstance("routing-functional",DATA)
const INITIAL=[[2,3],[4,5],[6,7]]
const D=Pilot.distances(DATA)
const BANKS=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:direct,:icn))
LSvalues(lane)=collect(Hybrid.LS.get_values(lane.parent.solver))

struct PoolAppendingDistances <: AbstractMatrix{Float64}
    storage::Matrix{Float64}
    routes::Vector{Vector{Int}}
    fired::Base.RefValue{Bool}
end
Base.size(d::PoolAppendingDistances)=size(d.storage)
function Base.getindex(d::PoolAppendingDistances,i::Int,j::Int)
    if !d.fired[];push!(d.routes,[2]);d.fired[]=true;end
    d.storage[i,j]
end

@testset "Native pool columns retain ordering, aliases and custom eager effects" begin
    pool=R.RoutePool();R.collect!(pool,P,D,INITIAL)
    for routes in (INITIAL,[[2,3,4,5],[6,7]],pool.routes,Vector{Int}[])
        retained=deepcopy((routes,pool.routes))
        expected=vcat(routes,pool.routes)
        borrowed=R.pool_column_candidates(pool,P,D,routes)
        actual=collect(borrowed)
        @test actual==expected
        @test all(a===b for (a,b) in zip(actual,expected))
        @test (routes,pool.routes)==retained
        generic=R.pool_column_candidates(pool,P,D,view(routes,:))
        @test generic isa Vector && generic==expected
        @test all(a===b for (a,b) in zip(generic,expected))
    end
    # A custom matrix may mutate caller storage while a route is being checked.
    # Its original eager outer snapshot must exclude newly appended columns.
    candidate=[collect(2:7)];fired=Ref(false)
    custom=PoolAppendingDistances(D,candidate,fired)
    eager=R.pool_column_candidates(pool,P,custom,candidate)
    @test eager isa Vector && length(eager)==length(candidate)+length(pool.routes)
    @test !fired[] && candidate==[collect(2:7)]
    R.collect!(pool,P,custom,candidate)
    @test fired[] && candidate==[collect(2:7),[2]]
    @test all(routes->validate_solution(P,routes).valid,pool.solutions)
    @test all(route->R.route_valid(P,D,route),pool.routes)
    @test !([2] in pool.routes) && !([2] in first(pool.solutions))
    retained=deepcopy(pool.solutions)
    push!(first(candidate),2)
    @test pool.solutions==retained
    function column_iteration_bytes(pool,p,D,routes)
        R.pool_column_candidates(pool,p,D,routes)
        @allocated for _ in 1:1000
            for route in R.pool_column_candidates(pool,p,D,routes);isempty(route);end
        end
    end
    @test column_iteration_bytes(pool,P,D,INITIAL)==0
end

@testset "Private pool membership preserves original routes, epochs and ownership" begin
    workspace=R.RouteMembershipWorkspace()
    for n in 0:5,index in 0:9^n-1
        route=[mod(div(index,9^(i-1)),9) for i in 1:n]
        @test R.route_valid(P,D,route,workspace)==R.route_valid(P,D,route)
    end
    for route in (Int[],[2,3],[3,2],[2,3,4,5],[2,3,2,3],[2,4],collect(2:7),[1,2,3],[2,8])
        retained=copy(route)
        @test R.route_valid(P,D,route,workspace)==R.route_valid(P,D,route)
        @test route==retained
        for generic in (Int32.(route),big.(route),view(route,:))
            @test R.route_valid(P,D,generic,workspace)==R.route_valid(P,D,generic)
        end
    end
    workspace.epoch=typemax(UInt)
    fill!(workspace.stamps,typemax(UInt))
    @test R.route_valid(P,D,[2,3],workspace)
    @test workspace.epoch==1
    @test !R.route_valid(P,D,[2],workspace)
    @test R.route_valid(P,D,[4,5],workspace)
    for nodes in (3,17,5,19,7)
        data=PickupDeliveryProblem(nodes,2,zeros(nodes,2),vcat(0,repeat([1,-1],(nodes-1)÷2)),
            zeros(nodes),fill(40.,nodes),zeros(nodes),[(2i,2i+1) for i in 1:(nodes-1)÷2])
        problem=BenchmarkInstance("membership-resized-$nodes",data);distances=Pilot.distances(data)
        route=collect(2:nodes)
        @test R.route_valid(problem,distances,route,workspace)==R.route_valid(problem,distances,route)
        @test length(workspace.stamps)==length(workspace.positions)==nodes
    end
    resize!(workspace.positions,0)
    @test R.route_valid(P,D,[2,3],workspace)
    @test length(workspace.positions)==length(DATA.demand)
    # Pair indices outside the node domain retain the original absent/present rule.
    for pairs in ([(0,8)],[(2,8)],[(0,3)],[(2,2)],[(3,2)],[(2,3)])
        data=PickupDeliveryProblem(DATA.vehicles,DATA.capacity,DATA.coordinates,DATA.demand,
            DATA.earliest,DATA.latest,DATA.service,DATA.pairs)
        empty!(data.pairs);append!(data.pairs,pairs)
        problem=BenchmarkInstance("membership-pair-boundaries",data)
        for route in (Int[],[2,3],[4,5],collect(2:7))
            @test R.route_valid(problem,D,route,workspace)==R.route_valid(problem,D,route)
        end
    end
    first_pool=R.RoutePool();second_pool=R.RoutePool();snapshot=deepcopy(first_pool)
    @test first_pool.membership!==second_pool.membership && snapshot.membership!==first_pool.membership
    @test snapshot.membership.stamps!==first_pool.membership.stamps
    @test snapshot.membership.positions!==first_pool.membership.positions
    R.collect!(first_pool,P,D,INITIAL)
    retained=deepcopy(first_pool.solutions);snapshot=deepcopy(first_pool)
    @test first_pool.membership.stamps!==snapshot.membership.stamps
    @test first_pool.membership.positions!==snapshot.membership.positions
    @test all(R.pool_route_valid(first_pool,P,D,route) for route in first_pool.routes)
    @test first_pool.solutions==retained && snapshot.solutions==retained
    legacy=R.RoutePool(Vector{Int}[],Vector{Vector{Int}}[],8,4)
    @test legacy.max_routes==8 && legacy.max_solutions==4 && isempty(legacy.membership.stamps)
    generic_pool=(;routes=copy(first_pool.routes))
    @test R.pool_route_valid(generic_pool,P,D,[2,3])==R.route_valid(P,D,[2,3])
    function membership_bytes(workspace,p,D,route)
        R.route_valid(p,D,route,workspace)
        @allocated for _ in 1:1000;R.route_valid(p,D,route,workspace);end
    end
    @test membership_bytes(workspace,P,D,collect(2:7))==0
end

@testset "Independent primitive snapshots preserve aliases and retained observations" begin
    for n in (0,1,2,8,32,64,128,129,256),visits in (0,2,16)
        original=[collect(1:visits) for _ in 1:n]
        first=R.owned_route_snapshot(original);second=R.owned_route_snapshot(original)
        @test first==deepcopy(original) && first isa Vector{Vector{Int}}
        @test first!==original && second!==first
        @test all(first[i]!==original[i] && first[i]!==second[i] for i in eachindex(original))
        @test all((first[i]===first[j])==(original[i]===original[j]) for i in eachindex(original),j in eachindex(original))
        saved=deepcopy(first)
        isempty(original) || push!(original[1],500)
        @test first==saved
    end
    for n in (2,8,128,129),empty_row in (false,true)
        row=empty_row ? Int[] : [2,3]
        original=[collect(4:5) for _ in 1:n];original[1]=row;original[end]=row
        result=R.owned_route_snapshot(original)
        @test result==deepcopy(original)
        @test result[1]===result[end] && result[1]!==row
        @test all((result[i]===result[j])==(original[i]===original[j]) for i in eachindex(original),j in eachindex(original))
        push!(result[1],6)
        @test result[end][end]==6 && !(6 in row)
    end
    nested=Any[Any[1,[2]],Any[3]];nested_copy=R.owned_route_snapshot(nested)
    @test nested_copy==deepcopy(nested) && nested_copy[1][2]!==nested[1][2]
    undefined=Vector{Vector{Int}}(undef,2);undefined[1]=[2,3]
    undefined_copy=R.owned_route_snapshot(undefined)
    @test isassigned(undefined_copy,1) && !isassigned(undefined_copy,2)
    @test undefined_copy[1]==undefined[1] && undefined_copy[1]!==undefined[1]
    lane=R.Lane(P,INITIAL);pool=lane.pool
    @test lane.current!==lane.best && lane.current!==INITIAL
    @test all(lane.current[i]!==lane.best[i] && lane.current[i]!==INITIAL[i] for i in eachindex(INITIAL))
    @test pool.solutions[1]!==INITIAL && pool.routes!==pool.solutions[1]
    @test all(pool.routes[i]!==pool.solutions[1][i] for i in eachindex(pool.routes))
    retained=deepcopy(pool.solutions)
    R.collect!(pool,P,D,[[2,3,4,5],[6,7]])
    @test pool.solutions[1]==retained[1] || retained[1] in pool.solutions
    @test lane.current==INITIAL && lane.best==INITIAL
end

@testset "Private lane counters preserve numeric observations and exported snapshots" begin
    first_lane=R.Lane(P,INITIAL);second_lane=R.Lane(P,INITIAL)
    @test first_lane.trace isa R.TraceCounters.Trace
    @test first_lane.trace.integers!==second_lane.trace.integers
    @test first_lane.trace.scalars!==second_lane.trace.scalars
    @test first_lane.trace.values!==second_lane.trace.values
    reference=R.TraceCounters.snapshot(first_lane.trace)
    retained=copy(reference)
    for (key,amount) in ("summary_evaluations"=>2000,"summary_evaluations"=>3,
            "thread_cpu_seconds"=>0.1,"thread_cpu_seconds"=>0.2,
            "custom_number"=>big(2),"custom_number"=>3)
        reference[key]=get(reference,key,0)+amount
        R.counter!(first_lane.trace,key,amount)
        @test isequal(R.TraceCounters.snapshot(first_lane.trace),reference)
        @test !haskey(second_lane.trace,key)
    end
    @test !haskey(retained,"summary_evaluations")
    function warm_counters!(trace)
        for _ in 1:100000;R.counter!(trace,"summary_evaluations",3);end
        nothing
    end
    warm_counters!(first_lane.trace)
    @test (@allocated warm_counters!(first_lane.trace))==0
    @test first_lane.trace["summary_evaluations"]==602003
    exported=R.TraceCounters.snapshot(first_lane.trace)
    @test exported isa Dict{String,Any}
    R.counter!(first_lane.trace,"summary_evaluations")
    @test exported["summary_evaluations"]==602003
end

@testset "Guidance, compaction and pheromone buffers preserve historical work" begin
    rng=Xoshiro(81)
    for _ in 1:200
        mask=rand(rng,Bool,7);nodes=rand(rng,1:7,rand(rng,0:30))
        expected=filter(node->!mask[node],nodes)
        actual=copy(nodes)
        @test R.remove_nodes!(actual,mask)===actual
        @test actual==expected
    end
    function compaction_bytes(nodes,mask)
        R.remove_nodes!(nodes,mask)
        @allocated for _ in 1:128;R.remove_nodes!(nodes,mask);end
    end
    @test compaction_bytes([2,3,4],falses(7))==0
    for seed in 1:12,guidance in (:critical,:incompatibility,:qubo)
        actual=R.Lane(P,INITIAL;seed,guidance)
        reference=R.Lane(P,INITIAL;seed,guidance)
        settings=merge(PANEL.DEFAULT,(;guidance))
        expected=collect(eachindex(P.data.pairs))
        if guidance==:critical
            sort!(expected;by=i->let; a,b=P.data.pairs[i]
                P.data.latest[b]-max(P.data.earliest[b],P.data.earliest[a]+P.data.service[a]+D[a,b])
            end)
        elseif guidance==:incompatibility
            sort!(expected;by=i->-sum(@view reference.graph[i,:]))
        else
            values=MetaRepair._successors!(reference.successor_values,reference.current)
            scope=Hybrid.QUBOGuidance.scope!(reference.guide_workspace,reference.guide,values,
                min(8,length(values)),reference.rng;mode="conditional")
            selected=Set(i+1 for i in scope)
            sort!(expected;by=i->let; a,b=P.data.pairs[i];a in selected || b in selected ? 0 : 1;end)
        end
        ids=R.guidance_ids(actual,P,settings)
        @test ids==expected
        @test ids===actual.repair_workspace.guidance_requests
        @test actual.repair_workspace.guidance_nodes!==reference.repair_workspace.guidance_nodes
        @test rand(actual.rng,UInt64)==rand(reference.rng,UInt64)
        partial=deepcopy(INITIAL);partial_reference=deepcopy(INITIAL)
        trace_reference=copy(actual.trace)
        rng_reference=copy(actual.rng)
        bank=R.destroy_guided!(partial,actual,P,settings,D,:shaw,2,ids)
        expected_bank=R.destroy!(partial_reference,P,D,rng_reference,:shaw,2;
            trace=trace_reference,guide_ids=expected,string_requests=R.LIMITS.string_requests,
            workspace=R.RepairWorkspace())
        @test bank==expected_bank && partial==partial_reference
        @test actual.trace==trace_reference
        @test rand(actual.rng,UInt64)==rand(rng_reference,UInt64)
    end
    lane=R.Lane(P,INITIAL);other=R.Lane(P,INITIAL)
    empty_ids=R.guidance_ids(lane,P,PANEL.DEFAULT)
    @test isempty(empty_ids) && empty_ids===lane.repair_workspace.guidance_requests
    @test empty_ids!==R.guidance_ids(other,P,PANEL.DEFAULT)
    for priority in ([3,1,2],2:3)
        lane.trace["master_priority_requests"]=priority
        @test R.guidance_ids(lane,P,PANEL.DEFAULT)===priority
    end
    delete!(lane.trace,"master_priority_requests")
    @test isempty(R.guidance_ids(lane,P,PANEL.DEFAULT))
    arc_workspace=Set{Tuple{Int,Int}}()
    actual=rand(rng,7,7).*110;expected=copy(actual)
    for _ in 1:80
        routes=[rand(rng,2:7,rand(rng,0:8)) for _ in 1:rand(rng,0:5)]
        R.reinforce!(actual,routes;arc_workspace)
        R.reinforce!(expected,routes)
        @test actual==expected
        @test arc_workspace==R.arcs(routes)
    end
end

@testset "Uniform repair priorities preserve explicit fresh defaults and RNG" begin
    first=R.RepairWorkspace();second=R.RepairWorkspace()
    priorities=R.uniform_difficulty!(first,3)
    @test priorities==ones(Int,3)
    @test priorities!==R.uniform_difficulty!(second,3)
    priorities[2]=100
    @test R.uniform_difficulty!(first,3)===priorities
    @test priorities==ones(Int,3)
    @test R.uniform_difficulty!((;),3)==ones(Int,3)
    function warmed_priorities_bytes(workspace)
        R.uniform_difficulty!(workspace,3)
        @allocated for _ in 1:128;R.uniform_difficulty!(workspace,3);end
    end
    warmed_priorities_bytes(first)
    @test warmed_priorities_bytes(first)==0
    for seed in 1:12,mode in (:random,:shaw,:worst,:route,:sisr),regret in (1,2,3),blinks in (0.,.15,.30)
        left=deepcopy(INITIAL);right=deepcopy(INITIAL)
        rng_left=Xoshiro(seed);rng_right=Xoshiro(seed)
        ws_left=R.RepairWorkspace();ws_right=R.RepairWorkspace()
        trace_left=Dict{String,Any}();trace_right=Dict{String,Any}()
        bank_left=R.destroy!(left,P,D,rng_left,mode,2;workspace=ws_left,trace=trace_left)
        bank_right=R.destroy!(right,P,D,rng_right,mode,2;workspace=ws_right,trace=trace_right)
        deadline=typemax(UInt64)
        actual=R.repair!(left,bank_left,P,D,rng_left,deadline;regret,blinks,max_routes=3,workspace=ws_left,trace=trace_left)
        reference=R.repair!(right,bank_right,P,D,rng_right,deadline;regret,blinks,max_routes=3,
            workspace=ws_right,trace=trace_right,difficulty=ones(Int,length(P.data.pairs)))
        @test actual==reference
        @test left==right && bank_left==bank_right
        @test trace_left==trace_right
        @test rand(rng_left,UInt64)==rand(rng_right,UInt64)
        actual && @test validate_solution(P,left).valid
    end
end

@testset "Additive configurations and colleague resource matrix" begin
    @test length(ResourceExperiment.StrategyPanel.CATALOG)==496
    @test allunique(collect(values(PANEL.CATALOG)))
    @test length(PANEL.methods(:meta))==16
    @test CampaignCatalog.select_methods(1,"routing-panel")==PANEL.methods()
    @test isempty(intersect(CampaignCatalog.select_methods(1,"panel"),PANEL.methods()))
    plan=PANEL.CONFIG["planned_campaign"]
    @test plan["worker_widths"]==[1,2,4] && plan["seeds"]==[41,42]
    @test plan["trials_per_configuration_and_instance"]==6
    @test sum(plan["possible_wave"])<=plan["max_concurrent_cpu_slots"]==4
    @test plan["exclusive_wave"]==[4]
    @test sum(plan["local_possible_wave"])<=plan["local_max_concurrent_cpu_slots"]==8
    for id in PANEL.methods(),width in (1,2,4)
        @test length(ResourceExperiment.allocation(id,width))==width
        @test length(PANEL.allocation(id,width))==width
    end
    allmethods=vcat(ResourceExperiment.StrategyPanel.methods(),PANEL.methods())
    styles=PanelPlotStyles.styles(allmethods,allmethods)
    @test allunique([(s.color,s.marker,s.linestyle) for s in values(styles)])
end

@testset "Exact sequence monoid versus independent original time/load scans" begin
    rng=Xoshiro(22)
    for _ in 1:80
        early=rand(rng,7).*3;late=early.+rand(rng,7).*15;early[1]=0.;late[1]=40.
        d=PickupDeliveryProblem(4,2,DATA.coordinates,DATA.demand,early,late,rand(rng,7),DATA.pairs)
        route=shuffle(rng,[2,3,4,5]);c=R.range_cache(d,D,route)
        scan=R.range_cache(d,D,route;max_cells=0)
        for a in 0:4,b in a:4
            sequence=R.insert_pair(route,(6,7),a,b)
            s=R.insertion_summary(c,d,D,(6,7),a,b)
            @test s==R.insertion_summary(scan,d,D,(6,7),a,b)
            @test R.distance(s,D)≈Pilot.route_distance(sequence,D) atol=1e-10
            @test R.sequence_feasible(d,D,s)==Pilot.feasible_route(sequence,d,D)
        end
    end
    @test R.sequence_feasible(DATA,D,R.Segment())
    c=R.range_cache(DATA,D,Int[])
    @test R.sequence_feasible(DATA,D,R.insertion_summary(c,DATA,D,(2,3),0,0))
    # The upper-triangle cache is reusable: scoring an insertion allocates no route.
    function bytes(c)
        R.insertion_summary(c,DATA,D,(6,7),1,2)
        @allocated R.insertion_summary(c,DATA,D,(6,7),1,2)
    end
    @test bytes(R.range_cache(DATA,D,[2,3,4,5]))==0
    cache=R.range_cache(DATA,D,[2,3,4,5]);buffer=cache.cells
    R.range_cache!(cache,DATA,D,[4,5]);@test cache.cells===buffer
    R.range_cache!(cache,DATA,D,[2,3,4,5]);@test cache.cells===buffer
    @test R.sequence_feasible(DATA,D,R.segment(cache,DATA,D,1,4))
    trace=Dict{String,Any}();rng=Xoshiro(41)
    options=R.insertion_options(P,D,[cache.route],3,[cache],typemax(UInt64),rng,trace)
    @test trace["summary_evaluations"]==15
    @test !isempty(options) && isconcretetype(eltype(options))
    @test all(o->Pilot.feasible_route(R.insert_pair(cache.route,DATA.pairs[3],o.a,o.b),DATA,D),options)
    limited=Dict{String,Any}("summary_evaluations"=>1000)
    R.insertion_options(P,D,[cache.route],3,[cache],typemax(UInt64),rng,limited;max_candidates=3)
    @test limited["summary_evaluations"]==1003 && limited["insertion_cap_hits"]==1
    blinked=Dict{String,Any}()
    @test isempty(R.insertion_options(P,D,[cache.route],3,[cache],typemax(UInt64),rng,blinked;blinks=1.))
    @test blinked["summary_evaluations"]==blinked["blinked_insertions"]==15
end

@testset "Owned range-cache capacity and original ordered segment arithmetic" begin
    lengths=(0,1,2,8,4,16,32,64,100,128,256,128,64,32,16,8,4,2,1,0)
    for cap in (0,1,3,4,63,64,65,8192,64.0,UInt(64))
        cache=R.RangeCache(Int[],Matrix{R.Segment}(undef,0,0))
        for n in lengths
            route=[mod1(i,4)+1 for i in 1:n]
            previous=cache.cells;old_capacity=size(previous,1)
            @test R.range_cache!(cache,DATA,D,route;max_cells=cap)===cache
            @test cache.route===route
            if n*n>cap
                @test isempty(cache.cells)
                isempty(previous) && @test cache.cells===previous
            else
                @test size(cache.cells,1)>=n
                old_capacity>=n && @test cache.cells===previous
                if cap isa Int && old_capacity<n
                    @test length(cache.cells)<=cap
                end
            end
            for a in 1:n,b in a:n
                @test R.segment(cache,DATA,D,a,b)==R.summarize(DATA,D,route,a,b)
            end
        end
    end
    left=R.range_cache(DATA,D,[2,3,4,5]);right=R.range_cache(DATA,D,[2,3,4,5])
    @test left.cells!==right.cells
    retained=copy(left.cells)
    R.range_cache!(right,DATA,D,[5,4,3,2])
    # Compare the assigned upper triangle only; lower cells are intentionally undefined.
    @test all(left.cells[a,b]==retained[a,b] for a in 1:4 for b in a:4)
    for n in (1,3,8,17,31)
        initial=R.range_cache(DATA,D,[mod1(i,4)+1 for i in 1:n])
        @test size(initial.cells)==(n,n)
    end
    growing=R.range_cache(DATA,D,[mod1(i,4)+1 for i in 1:16])
    R.range_cache!(growing,DATA,D,[mod1(i,4)+1 for i in 1:18])
    @test size(growing.cells)==(20,20)
    retained_capacity=growing.cells
    R.range_cache!(growing,DATA,D,[mod1(i,4)+1 for i in 1:19])
    @test growing.cells===retained_capacity
    bounded=R.range_cache(DATA,D,[mod1(i,4)+1 for i in 1:16];max_cells=324)
    R.range_cache!(bounded,DATA,D,[mod1(i,4)+1 for i in 1:18];max_cells=324)
    @test size(bounded.cells)==(18,18)
end

@testset "Owned route, request and successor workspaces" begin
    scratch=R.RouteBuffer();copied=R.copy_routes!(scratch,INITIAL)
    @test copied==INITIAL && copied!==INITIAL && all(copied[i]!==INITIAL[i] for i in eachindex(INITIAL))
    retained=scratch.buffers[1];R.copy_routes!(scratch,[[2,3]])
    R.copy_routes!(scratch,INITIAL);@test scratch.buffers[1]===retained
    @test R.copy_routes!(scratch,scratch.routes)===scratch.routes
    values=zeros(Int,6);@test MetaRepair.successors!(values,P,INITIAL)===values
    @test values==MetaRepair.successors(P,INITIAL)
    @test_throws DimensionMismatch MetaRepair.successors!(zeros(Int,5),P,INITIAL)
    @test_throws ArgumentError MetaRepair.successors!(values,P,[[2],[3,4,5,6,7]])
    matched=BitVector()
    @test R.same_routes!(matched,reverse(INITIAL),INITIAL)
    @test !R.same_routes!(matched,[INITIAL[1],INITIAL[1],INITIAL[2]],INITIAL)
    function warm_bytes(scratch,values)
        R.copy_routes!(scratch,INITIAL);MetaRepair._successors!(values,INITIAL)
        copies=@allocated R.copy_routes!(scratch,INITIAL)
        successors=@allocated MetaRepair._successors!(values,INITIAL)
        (copies,successors)
    end
    @test warm_bytes(scratch,values)==(0,0)
    # Many distinct rank values expose boxed comparator arguments that a
    # three-request fixture can hide. Setup and route storage are outside the probe.
    many_pairs=[(2i,2i+1) for i in 1:50]
    many_coords=hcat(Float64.(0:100),zeros(101))
    many_data=PickupDeliveryProblem(50,1,many_coords,vcat(0,repeat([1,-1],50)),zeros(101),fill(1000.,101),zeros(101),many_pairs)
    many_p=BenchmarkInstance("Shaw comparator allocation oracle",many_data);many_D=Pilot.distances(many_data)
    many_routes=[collect(pair) for pair in many_pairs]
    function shaw_bytes(p,D,routes)
        w=R.RepairWorkspace();buffer=R.RouteBuffer();trace=Dict{String,Any}();rng=Xoshiro(41)
        trial=R.copy_routes!(buffer,routes)
        R.destroy!(trial,p,D,rng,:shaw,10;workspace=w,trace)
        trial=R.copy_routes!(buffer,routes)
        @allocated R.destroy!(trial,p,D,rng,:shaw,10;workspace=w,trace)
    end
    @test shaw_bytes(many_p,many_D,many_routes)<=1024
    lane=R.Lane(P,INITIAL);kept=deepcopy(lane.pool.solutions)
    @test !R.admit!(lane,P,reverse(INITIAL),PANEL.DEFAULT)
    @test lane.unchanged_proposals==1 && lane.current==INITIAL
    @test_throws ErrorException R.admit!(lane,P,[INITIAL[1],INITIAL[1],INITIAL[2]],PANEL.DEFAULT)
    for mode in (:random,:shaw,:worst,:route,:sisr),i in 1:8
        routes=R.copy_routes!(lane.trial_workspace,INITIAL)
        bank=R.destroy!(routes,P,D,Xoshiro(i),mode,2;workspace=lane.repair_workspace)
        @test bank===lane.repair_workspace.selected
        @test R.repair!(routes,bank,P,D,Xoshiro(i),typemax(UInt64);max_routes=3,workspace=lane.repair_workspace)
        @test validate_solution(P,routes).valid && lane.current==INITIAL
        @test lane.pool.solutions==kept
    end
    for i in 1:16
        routes=R.copy_routes!(lane.trial_workspace,INITIAL)
        @test R.elimination!(routes,P,D,Xoshiro(i),typemax(UInt64);depth=2,workspace=lane.repair_workspace)
        saved=deepcopy(routes);empty!(lane.repair_workspace.ejection.routes)
        for r in lane.repair_workspace.ejection.buffers;fill!(r,-1);end
        @test routes==saved && validate_solution(P,routes).valid && lane.current==INITIAL
    end
end

@testset "Original validator workspace and RNG-identical request selection" begin
    workspace=R.original_workspace()
    retained=R.original_check(P,[[3,2],[4]],workspace);saved=deepcopy(retained)
    for routes in (INITIAL,reverse(INITIAL),[[2,3,4,5,6,7]],[[2],[3,4,5,6,7]],
            [[2,2,3],[4,5],[6,7]],Vector{Int}[],[[NaN,3],[4,5]],[[2.0,3.0],[4,5],[6,7]])
        @test R.original_check(P,routes,workspace)==validate_solution(P,routes)
    end
    @test retained==saved
    @test R.quality(P,INITIAL;validation_workspace=workspace)==R.quality(P,INITIAL)
    if workspace!==nothing
        first_lane=R.Lane(P,INITIAL);second_lane=R.Lane(P,INITIAL)
        @test first_lane.validation_workspace!==second_lane.validation_workspace
        @test first_lane.validation_workspace.counts!==second_lane.validation_workspace.counts
        function audit_bytes(workspace)
            R.original_check(P,INITIAL,workspace)
            @allocated R.original_check(P,INITIAL,workspace)
        end
        @test audit_bytes(workspace)<=128
        @test R.exchange(P,INITIAL,D,1,2;validation_workspace=workspace)==R.exchange(P,INITIAL,D,1,2)
        pool=R.RoutePool();R.collect!(pool,P,D,INITIAL;validation_workspace=workspace)
        snapshots=deepcopy(pool.solutions)
        R.original_check(P,[[2],[3,4,5,6,7]],workspace)
        @test pool.solutions==snapshots
        @test_throws ArgumentError R.collect!(pool,P,D,[[2],[3,4,5,6,7]];validation_workspace=workspace)
    end
    for n in (0,1,2,3,50,256),count in (0,1,2,8),seed in (41,42,43)
        before=Xoshiro(seed);after=Xoshiro(seed);selection=R.RepairWorkspace()
        for _ in 1:8
            expected=randperm(before,n)[1:min(count,n)]
            actual=R.random_requests!(selection,n,after;count)
            @test actual==expected && allunique(actual)
            @test rand(before,UInt64)==rand(after,UInt64)
            @test actual===selection.selected
        end
    end
    function request_selection_bytes(workspace,rng)
        R.random_requests!(workspace,50,rng)
        @allocated for _ in 1:1024;R.random_requests!(workspace,50,rng);end
    end
    @test request_selection_bytes(R.RepairWorkspace(),Xoshiro(41))==0
    @test_throws ArgumentError R.random_requests!(R.RepairWorkspace(),3,Xoshiro(41);count=-1)
    @test INITIAL==[[2,3],[4,5],[6,7]]
end

@testset "Original-distance exchange rejection preserves the full audit" begin
    rng=Xoshiro(77)
    for _ in 1:80
        early=rand(rng,7).*3;late=early.+rand(rng,7).*25;early[1]=0.;late[1]=40.
        d=PickupDeliveryProblem(3,rand(rng,1:3),DATA.coordinates,DATA.demand,early,late,rand(rng,7),DATA.pairs)
        p=BenchmarkInstance("exchange prefilter oracle",d);dist=Pilot.distances(d)
        w=R.RouteBuffer()
        for a in 1:3,b in 1:3
            a==b && continue
            reference=R.exchange(p,INITIAL,dist,a,b)
            filtered=R.exchange(p,INITIAL,dist,a,b;workspace=w,original_distance_prefilter=true)
            @test filtered==reference
            @test INITIAL==[[2,3],[4,5],[6,7]]
        end
    end
    # The public default retains its original audit even if D is caller supplied.
    @test R.exchange(P,INITIAL,fill(1000.,7,7),1,2)!==nothing
    early=[0.,0.,0.,5.,5.,0.,0.,10.,10.];late=copy(early);late[1]=40.
    d=PickupDeliveryProblem(2,1,zeros(9,2),[0,1,-1,1,-1,1,-1,1,-1],early,late,zeros(9),[(2,3),(4,5),(6,7),(8,9)])
    p=BenchmarkInstance("infeasible exchange allocation oracle",d);dist=Pilot.distances(d)
    routes=[[2,3,4,5],[6,7,8,9]];w=R.RouteBuffer()
    @test validate_solution(p,routes).valid
    @test R.exchange(p,routes,dist,1,4)===nothing
    function rejected_exchange_bytes(p,routes,dist,w)
        R.exchange(p,routes,dist,1,4;workspace=w,original_distance_prefilter=true)
        @allocated R.exchange(p,routes,dist,1,4;workspace=w,original_distance_prefilter=true)
    end
    @test rejected_exchange_bytes(p,routes,dist,w)<=512
    @test routes==[[2,3,4,5],[6,7,8,9]]
end

@testset "Request closure, bounded repair, ejections, diversity and ICN truth" begin
    for mode in (:random,:shaw,:worst,:route,:sisr),regret in (2,3)
        routes=deepcopy(INITIAL);rng=Xoshiro(41);trace=Dict{String,Any}()
        bank=R.destroy!(routes,P,D,rng,mode,2;trace)
        @test all(i->all(v->all(r->!(v in r),routes),DATA.pairs[i]),bank)
        @test R.repair!(routes,bank,P,D,rng,typemax(UInt64);regret,max_routes=3,trace)
        @test isempty(bank) && validate_solution(P,routes).valid
        @test trace["reinserted_requests"]==trace["destroyed_requests"]
    end
    routes=deepcopy(INITIAL);bank=R.destroy!(routes,P,D,Xoshiro(1),:random,1)
    @test !R.repair!(routes,bank,P,D,Xoshiro(1),UInt64(0);max_routes=3)
    @test !isempty(bank) # an incomplete bank is not an original-model solution
    for depth in (1,2)
        routes=deepcopy(INITIAL);trace=Dict{String,Any}()
        @test R.elimination!(routes,P,D,Xoshiro(41),typemax(UInt64);depth,trace)
        @test validate_solution(P,routes).valid && length(routes)==2
    end
    # Two overlapping units must be ejected to fit the blocked two-unit request.
    # The distant route can absorb both ejections but cannot serve that blocked request.
    coords=zeros(11,2);coords[10:11,1].=1.
    early=[0.,0.,2.,0.,2.,0.,2.,1.,1.5,1.,1.5]
    late=[40.,0.,3.,0.,3.,0.,3.,1.,1.5,1.,1.5]
    d=PickupDeliveryProblem(3,3,coords,[0,1,-1,1,-1,1,-1,2,-2,1,-1],early,late,zeros(11),
        [(2,3),(4,5),(6,7),(8,9),(10,11)])
    p=BenchmarkInstance("two-request ejection oracle",d);D2=Pilot.distances(d)
    start=[[8,9],[2,4,6,3,5,7],[10,11]]
    @test validate_solution(p,start).valid
    order=sortperm(start;by=r->(length(r),Pilot.route_distance(r,D2)))
    seed=first(s for s in 1:100 if rand(Xoshiro(s),order[1:3])==1)
    difficulty=[1,1,1,2,100]
    @test !R.elimination!(deepcopy(start),p,D2,Xoshiro(seed),typemax(UInt64);depth=1,candidate_limit=3,difficulty=copy(difficulty))
    trial=deepcopy(start);trace=Dict{String,Any}()
    @test R.elimination!(trial,p,D2,Xoshiro(seed),typemax(UInt64);depth=2,candidate_limit=3,difficulty=copy(difficulty),trace)
    @test trace["ejected_requests"]==2
    @test validate_solution(p,trial).valid && length(trial)==2
    @test validate_solution(P,R.exchange(P,INITIAL,D,1,2)).valid
    for id in PANEL.methods(:search)
        settings=only(PANEL.CATALOG[id].lanes);kind=settings.backend==:icn_fused_all ? :icn : settings.backend
        backend=ICNScoring.clone_backend(BANKS[kind],settings.backend)
        lane=Base.invokelatest(R.Lane,P,INITIAL;scorer=backend,guidance=settings.guidance)
        Base.invokelatest(R.episode!,lane,P,settings,typemax(UInt64);max_steps=4)
        @test validate_solution(P,lane.best).valid
        @test all(v->v["vehicles"]==validate_solution(P,v["routes"]).objective.vehicles,lane.trace["trajectory"])
        @test R.quality(P,lane.best)<=R.quality(P,INITIAL)
        @test LSvalues(lane)==MetaRepair.successors(P,lane.current)
        settings.algorithm==:sisr && @test get(lane.trace,"sisr_fleet_attempts",0)>0
    end
    for fraction in (0.25,1.)
        settings=merge(PANEL.DEFAULT,(;algorithm=:vnd,reset_fraction=fraction))
        lane=R.Lane(P,INITIAL);lane.steps=32
        R.episode!(lane,P,settings,typemax(UInt64);max_steps=1)
        @test get(lane.trace,"completed_resets",0)==1
        @test get(lane.trace,"destroyed_requests",0)==ceil(Int,fraction*3)
        @test validate_solution(P,lane.current).valid
    end
    # An original-feasible but incorrect error-backend candidate cannot bypass its score.
    scorer=(p,D,values)->begin
        s=Hybrid.routing_score(p,D,values)
        merge(s,(;error=s.vehicles<3 ? 1. : s.error))
    end
    lane=R.Lane(P,INITIAL;scorer)
    @test_throws ErrorException R.admit!(lane,P,[[2,3,4,5,6,7]],PANEL.DEFAULT;force=true)
    @test lane.current==INITIAL
    lane=R.Lane(P,INITIAL);tabu=merge(PANEL.DEFAULT,(;acceptance=:tabu))
    @test R.admit!(lane,P,[[2,3,4,5,6,7]],tabu)
    @test !R.admit!(lane,P,INITIAL,tabu)
    @test lane.trace["tabu_hits"]==1
    before=copy(lane.history);steps=lane.steps
    @test !R.admit!(lane,P,deepcopy(lane.current),tabu)
    @test lane.steps==steps && lane.history==before
    @test validate_solution(P,lane.current).valid
end

@testset "Certified incompatibilities, protected pools and native LP/MIP algorithms" begin
    evidence=R.incompatibilities(P,D)
    @test evidence.tested==3 && !any(evidence.graph)
    @test R.clique_bound(evidence.graph).bound==1
    nonmetric=copy(D);nonmetric[2,4]+=1
    @test R.incompatibilities(P,nonmetric).scope=="disabled_non_euclidean_input"
    g=trues(4,4);g[diagind(g)].=false
    @test R.clique_bound(g).bound==4
    tight=PickupDeliveryProblem(4,1,DATA.coordinates,DATA.demand,zeros(7),[40.,1.,2.,1.,2.,1.,2.],zeros(7),DATA.pairs)
    q=BenchmarkInstance("certified separate fleet",tight);cert=R.incompatibilities(q,D)
    @test all(cert.graph[i,j] for i in 1:3 for j in i+1:3)
    @test R.clique_bound(cert.graph).bound==3
    pool=R.RoutePool(;max_routes=8,max_solutions=4)
    R.collect!(pool,P,D,INITIAL);R.collect!(pool,P,D,[[2,3,4,5,6,7]])
    columns=pool.routes;solutions=pool.solutions;retained=deepcopy(solutions)
    R.collect!(pool,P,D,[[2,3,4,5,6,7]])
    @test pool.routes===columns && pool.solutions===solutions
    @test pool.solutions==retained
    input=[[2,3,4,5,6,7]];R.collect!(pool,P,D,input);empty!(input[1])
    @test pool.solutions==retained && all(r->R.route_valid(P,D,r),pool.routes)
    @test_throws ArgumentError R.collect!(pool,P,D,[[2],[3,4,5,6,7]])
    for mode in ("simplex","ipx","hipo")
        trace=Dict{String,Any}();deadline=time_ns()+UInt64(20_000_000_000)
        candidate=R.recombine(pool,P,D,deadline;lp_solver=mode,trace)
        @test candidate!==nothing && validate_solution(P,candidate).valid
        @test length(candidate)==1
        @test trace["master_native_threads"]==1
        @test trace["master_lp_calls"]==trace["master_mip_calls"]==1
        @test haskey(trace,"master_last_dual_prices")
        @test trace["master_bound_scope"]=="restricted_route_pool_not_global_original_bound"
    end
    @test R.recombine(pool,P,D,UInt64(0))===nothing
    snapshot=(;instance=P,pool=deepcopy(pool),routes=deepcopy(INITIAL),distances=D,values=MetaRepair.successors(P,INITIAL))
    request=Hybrid.LS.MetaVariableRequest(Hybrid.LS.MetaVariable(:route_pool,1:6),snapshot,20.,Xoshiro(41))
    outcome=Hybrid.LS.resolve_meta_variable(R.RoutePoolResolver("ipx"),request)
    @test outcome.status==:improved && outcome.move!==nothing
    values=copy(snapshot.values);values[outcome.move.variables]=outcome.move.replacements
    @test validate_solution(P,MetaRepair.routes_from_successors(P,values)).valid
    narrow=Hybrid.LS.MetaVariableRequest(Hybrid.LS.MetaVariable(:invalid_partial_pool,1:2),snapshot,20.,Xoshiro(41))
    @test Hybrid.LS.resolve_meta_variable(R.RoutePoolResolver("ipx"),narrow).status==:invalid_fragment
end

@testset "Real typed MetaStrategist cooperative phases and owned CBLS states" begin
    # Fixed episode count on a tiny original model; no comparative timing result.
    width=min(2,Threads.nthreads());method="rp_meta_adaptive_late"
    strategy=ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(method,width))
    executor=(;clone_backend=ICNScoring.clone_backend,
        run=(plan,call,rows)->ResourceExperiment.MS.execute!(plan.prepared.kernel,ResourceExperiment.ExecutionContext(call,rows)))
    result=Base.invokelatest(R.run_portfolio,P,INITIAL,method,120.,41,BANKS,strategy,executor;
        max_episodes=8,cpu_clock=()->ResourceExperiment.cpu_seconds(3))
    @test result.coordination["episodes"]==8
    @test sum(result.coordination["role_episode_counts"])==8width
    @test all(>(0),result.coordination["role_episode_counts"])
    @test all(w->validate_solution(P,w["routes"]).valid,result.workers)
    @test all(w->w["trace"] isa Dict{String,Any},result.workers)
    @test all(pair->first(pair)["trace"]!==last(pair).trace,zip(result.workers,result.lanes))
    @test all(l->validate_solution(P,l.current).valid,result.lanes)
    @test INITIAL==[[2,3],[4,5],[6,7]]
    @test result.coordination["fill_episode"]
    @test all(l->l.steps>8R.LIMITS.episode_steps,result.lanes)
    capped=Base.invokelatest(R.run_portfolio,P,INITIAL,method,30.,41,BANKS,strategy,executor;
        max_episodes=2,episode_steps=1,episode_seconds=30.,fill_episode=false)
    @test [l.steps for l in capped.lanes]==fill(2,width)
    filled=Base.invokelatest(R.run_portfolio,P,INITIAL,method,30.,41,BANKS,strategy,executor;
        max_episodes=2,episode_steps=1,episode_seconds=0.25)
    @test minimum(l.steps for l in filled.lanes)>2
    if width==2
        @test result.lanes[1].parent.solver!==result.lanes[2].parent.solver
        @test result.lanes[1].guide_workspace!==result.lanes[2].guide_workspace
        @test result.lanes[1].history!==result.lanes[2].history
        @test result.lanes[1].repair_workspace!==result.lanes[2].repair_workspace
        @test result.lanes[1].new_arcs!==result.lanes[2].new_arcs
        @test result.lanes[1].old_arcs!==result.lanes[2].old_arcs
        @test result.lanes[1].trial_workspace.buffers!==result.lanes[2].trial_workspace.buffers
        @test result.lanes[1].repair_workspace.options!==result.lanes[2].repair_workspace.options
        @test result.lanes[1].repair_workspace.ejection.buffers!==result.lanes[2].repair_workspace.ejection.buffers
        @test result.lanes[1].successor_values!==result.lanes[2].successor_values
    end
    mktemp() do path,io
        write(io,"3 2 1\n0 0 0 0 0 40 0 0 0\n1 1 0 1 0 40 0 0 2\n2 2 0 -1 0 40 0 1 0\n3 -1 0 1 0 40 0 0 4\n4 -2 0 -1 0 40 0 3 0\n5 0 1 1 0 40 0 0 6\n6 0 2 -1 0 40 0 5 0\n");close(io)
        policy=Dict("insertion_starts"=>1,"insertion_seed"=>41)
        record=Base.invokelatest(ResourceExperiment.run_case,path,"rp_meta_pool_ipx_late",20.,41,policy,BANKS;
            threads=width,max_episodes=4)
        @test record["original_validation"] && record["metastrategist_executed"]
        @test record["routing_coordination"]["episodes"]==4
        @test record["routing_coordination"]["master_resolver_calls"]==1
        @test record["routing_coordination"]["master_lp_calls"]==1
        @test all(w->haskey(w["trace"],"master_priority_requests"),record["workers"])
        @test all(e->e["seconds"]<=20. && validate_solution(read_benchmark(path,:li_lim),e["routes"]).valid,record["trajectory"])
        buffer=IOBuffer();TOML.print(buffer,record)
        parsed=TOML.parse(String(take!(buffer)))
        @test parsed["routes"]==record["routes"] && parsed["routing_panel"]["id"]=="rp_meta_pool_ipx_late"
    end
end
