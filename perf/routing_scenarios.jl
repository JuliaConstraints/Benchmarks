# PerfChecker original-model workloads for the additive Li-Lim route controller.
using ConstraintModels, Random
using ConstraintModels.Benchmarks
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/Pilot.jl"))
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/MetaRepair.jl"))
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/ICNScoring.jl"))
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/Hybrid.jl"))
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/ResourceExperiment.jl"))
const StructuredRouting=ResourceExperiment.StructuredRouting
function routing_fixture()
    d=PickupDeliveryProblem(4,2,[0. 0.;1 0;2 0;-1 0;-2 0;0 1;0 2],
        [0,1,-1,1,-1,1,-1],zeros(7),fill(40.,7),zeros(7),[(2,3),(4,5),(6,7)])
    BenchmarkInstance("route-profile-functional",d)
end
function routing_kernel_case(parameters)
    operation=parameters["operation"];repetitions=parameters["repetitions"]
    prepare=()->begin
        p=routing_fixture();D=Pilot.distances(p.data)
        routes=[[2,3],[4,5],[6,7]];pool=StructuredRouting.RoutePool()
        StructuredRouting.collect!(pool,p,D,routes)
        lane=operation=="duplicate_admission" ? StructuredRouting.Lane(p,routes) : nothing
        route_buffer=StructuredRouting.RouteBuffer();StructuredRouting.copy_routes!(route_buffer,routes)
        (;p,D,routes,pool,lane,arc_buffer=Set{Tuple{Int,Int}}(),route_buffer,values=ones(Int,6),expected_values=MetaRepair.successors(p,routes),
            cache=StructuredRouting.range_cache(p.data,D,[2,3,4,5]),workspace=StructuredRouting.RepairWorkspace())
    end
    work=s->begin
        last=true
        if operation=="insertion"
            for _ in 1:repetitions
                a=StructuredRouting.insertion_summary(s.cache,s.p.data,s.D,(6,7),1,2)
                last=StructuredRouting.sequence_feasible(s.p.data,s.D,a)
            end
        elseif operation=="cache"
            for _ in 1:repetitions;StructuredRouting.range_cache(s.p.data,s.D,s.cache.route);end
        elseif operation=="cache_reuse"
            for _ in 1:repetitions;StructuredRouting.range_cache!(s.cache,s.p.data,s.D,s.cache.route);end
        elseif operation=="route_copy"
            for _ in 1:repetitions;StructuredRouting.copy_routes!(s.route_buffer,s.routes);end
            last=s.route_buffer.routes==s.routes && s.route_buffer.routes!==s.routes
        elseif operation=="successor_fill"
            for _ in 1:repetitions;MetaRepair._successors!(s.values,s.routes);end
            last=s.values==s.expected_values
        elseif operation=="insertion_options"
            rng=Xoshiro(41);trace=Dict{String,Any}()
            for _ in 1:repetitions
                opts=StructuredRouting.insertion_options(s.p,s.D,[s.cache.route],3,[s.cache],typemax(UInt64),rng,trace;
                    options=s.workspace.options)
                last &= !isempty(opts)
            end
        elseif operation=="pool_reuse"
            for _ in 1:repetitions;StructuredRouting.collect!(s.pool,s.p,s.D,s.routes);end
            last=all(r->r in s.pool.routes,s.routes) && length(s.pool.solutions)==1
        elseif operation=="duplicate_admission"
            for _ in 1:repetitions
                last &= !StructuredRouting.admit!(s.lane,s.p,s.routes,StructuredRouting.RoutingPanel.DEFAULT)
            end
        elseif operation=="arc_reuse"
            for _ in 1:repetitions;StructuredRouting.arcs!(s.arc_buffer,s.routes);end
            last=length(s.arc_buffer)==9
        elseif operation in ("repair","ejection")
            for i in 1:repetitions
                routes=[[2,3],[4,5],[6,7]];rng=Xoshiro(41+i)
                if operation=="repair"
                    bank=StructuredRouting.destroy!(routes,s.p,s.D,rng,:sisr,2)
                    last=StructuredRouting.repair!(routes,bank,s.p,s.D,rng,typemax(UInt64);max_routes=3,workspace=s.workspace)
                else
                    last=StructuredRouting.elimination!(routes,s.p,s.D,rng,typemax(UInt64);depth=2,workspace=s.workspace)
                end
                last &= validate_solution(s.p,routes).valid
            end
        else;throw(ArgumentError("unknown route kernel"));end
        last
    end
    (;prepare,operation=work,verify=(state,result)->result)
end

function routing_solver_case(parameters)
    method=parameters["method"];width=parameters["width"];steps=parameters["steps"]
    seconds=get(parameters,"seconds",30.)
    roles=StructuredRouting.RoutingPanel.allocation(method,width)
    prepare=()->begin
        p=routing_fixture()
        banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:direct,:icn))
        lanes=map(enumerate(roles)) do (i,r)
            k=r.backend==:icn_fused_all ? :icn : r.backend
            b=ICNScoring.clone_backend(banks[k],r.backend)
            Base.invokelatest(StructuredRouting.Lane,p,[[2,3],[4,5],[6,7]];seed=41+i,guidance=r.guidance,scorer=b)
        end
        (;p,lanes)
    end
    work=s->begin
        deadline=time_ns()+UInt64(round(Int,seconds*1e9))
        Threads.@threads :static for i in eachindex(s.lanes)
            Base.invokelatest(StructuredRouting.episode!,s.lanes[i],s.p,roles[i],deadline;max_steps=steps)
        end
        all(l->validate_solution(s.p,l.best).valid,s.lanes)
    end
    (;prepare,operation=work,verify=(state,result)->result)
end

"Actual typed MetaStrategist cooperation and semantic HiGHS master, with explicit diagnostic caps."
function routing_meta_case(parameters)
    id=parameters["method"];width=parameters["width"]
    episodes=get(parameters,"episodes",4);steps=get(parameters,"steps",4);seconds=get(parameters,"seconds",30.)
    prepare=()->begin
        p=routing_fixture();banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:direct,:icn))
        plan=ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(id,width))
        (;p,banks,plan)
    end
    executor=(;clone_backend=ICNScoring.clone_backend,metadata=ICNScoring.metadata,
        run=(plan,call,rows)->ResourceExperiment.MS.execute!(plan.prepared.kernel,ResourceExperiment.ExecutionContext(call,rows)))
    work=s->Base.invokelatest(StructuredRouting.run_portfolio,s.p,[[2,3],[4,5],[6,7]],id,seconds,41,s.banks,s.plan,executor;
        max_episodes=episodes,episode_steps=steps,episode_seconds=seconds,fill_episode=false)
    verify=(s,r)->r.coordination["episodes"]==episodes && all(w->validate_solution(s.p,w["routes"]).valid,r.workers)
    (;prepare,operation=work,verify)
end

"Bounded complete original-instance pipeline; never exports a comparative trial."
function routing_instance_case(parameters)
    path=parameters["instance"];id=parameters["method"];width=parameters["width"];seconds=parameters["seconds"]
    prepare=()->begin
        p=read_benchmark(path,:li_lim)
        banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:direct,:icn))
        plan=ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(id,width))
        (;p,banks,plan)
    end
    work=s->Base.invokelatest(ResourceExperiment.run_case,path,id,seconds,41,
        Dict("insertion_starts"=>1,"insertion_seed"=>41),s.banks;threads=width,portfolio=s.plan)
    verify=(s,r)->r["original_validation"] && validate_solution(s.p,r["routes"]).valid &&
        all(e->validate_solution(s.p,e["routes"]).valid && 0<=e["seconds"]<=seconds,r["trajectory"])
    (;prepare,operation=work,verify)
end
