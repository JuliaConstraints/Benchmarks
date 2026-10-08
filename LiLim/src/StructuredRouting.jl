"Bounded paired-route search and cooperative pools, admitted as real CBLS MetaMoves."
module StructuredRouting
using Random, JuMP
import MathOptInterface as MOI
import LocalSearchSolvers as LS
using ..Benchmarks, ..Pilot, ..MetaRepair, ..Hybrid
include("RoutingPanel.jl")
const BOUNDS = RoutingPanel.CONFIG["bounds"]
const LIMITS = (; (Symbol(k)=>v for (k,v) in BOUNDS)...)
const TOL = 1e-8
export Segment, concatenate, range_cache, insertion_summary, sequence_feasible,
    repair!, destroy!, elimination!, exchange, Lane, episode!, share!, admit!, RoutePool,
    collect!, recombine, incompatibilities, clique_bound, run_portfolio, RepairWorkspace, range_cache!, RoutePoolResolver

"Exact time/load/distance summary for a fixed sequence, excluding depot arcs."
struct Segment
    first::Int
    last::Int
    travel::Float64
    shift::Float64
    floor::Float64
    latest::Float64
    load::Int
    low::Int
    high::Int
    valid::Bool
end
Segment() = Segment(0,0,0.,0.,-Inf,Inf,0,0,0,true)
function Segment(d,i::Int)
    q=d.demand[i]
    Segment(i,i,0.,d.service[i],d.earliest[i]+d.service[i],d.latest[i],q,min(0,q),max(0,q),
        d.earliest[i]<=d.latest[i]+TOL)
end
@inline function concatenate(a::Segment,b::Segment,D)
    a.first==0 && return b
    b.first==0 && return a
    t=D[a.last,b.first]
    Segment(a.first,b.last,a.travel+t+b.travel,a.shift+t+b.shift,
        max(a.floor+t+b.shift,b.floor),min(a.latest,b.latest-t-a.shift),
        a.load+b.load,min(a.low,a.load+b.low),max(a.high,a.load+b.high),
        a.valid && b.valid && a.floor+t<=b.latest+TOL)
end
function summarize(d,D,route,lo=1,hi=length(route))
    s=Segment()
    for i in lo:hi; s=concatenate(s,Segment(d,route[i]),D); end
    s
end
function sequence_feasible(d,D,s::Segment)
    s.first==0 && return true
    arrival=d.earliest[1]+d.service[1]+D[1,s.first]
    s.valid && arrival<=s.latest+TOL && s.load==0 && s.low>=0 && s.high<=d.capacity &&
        max(arrival+s.shift,s.floor)+D[s.last,1]<=d.latest[1]+TOL
end
distance(s::Segment,D)=s.first==0 ? 0. : D[1,s.first]+s.travel+D[s.last,1]
mutable struct RangeCache
    route::Vector{Int}
    cells::Matrix{Segment}
end
"Owned upper-triangular cache; long routes fall back to bounded scans."
function range_cache(d,D,route;max_cells=LIMITS.summary_cells)
    c=RangeCache(route,Matrix{Segment}(undef,0,0))
    range_cache!(c,d,D,route;max_cells)
end
function range_cache!(c,d,D,route;max_cells=LIMITS.summary_cells)
    n=length(route);c.route=route
    if n*n>max_cells
        c.cells=Matrix{Segment}(undef,0,0)
    elseif size(c.cells,1)<n
        c.cells=Matrix{Segment}(undef,n,n)
    end
    if n*n<=max_cells
        for i in 1:n
            s=Segment()
            for j in i:n; s=concatenate(s,Segment(d,route[j]),D);c.cells[i,j]=s;end
        end
    end
    c
end
"Borrowed route storage; its next copy invalidates only this workspace's previous view."
struct RouteBuffer
    buffers::Vector{Vector{Int}}
    routes::Vector{Vector{Int}}
end
RouteBuffer()=RouteBuffer(Vector{Int}[],Vector{Int}[])
function copy_routes!(w::RouteBuffer,source)
    source===w.routes && return w.routes
    while length(w.buffers)<length(source);push!(w.buffers,Int[]);end
    resize!(w.routes,length(source))
    for i in eachindex(source)
        buffer=w.buffers[i];resize!(buffer,length(source[i]));copyto!(buffer,source[i]);w.routes[i]=buffer
    end
    w.routes
end
const InsertionOption=NamedTuple{(:route,:a,:b,:delta,:rank),Tuple{Int,Int,Int,Float64,Float64}}
struct RepairWorkspace
    caches::Vector{RangeCache}
    options::Vector{InsertionOption}
    ejection::RouteBuffer
    bank::Vector{Int}
    pending::Vector{Int}
    candidates::Vector{Int}
    choices::Vector{Int}
    ejections::Vector{NTuple{2,Int}}
    seen::Set{NTuple{3,Int}}
    removed::BitVector
    all_ids::Vector{Int}
    selected::Vector{Int}
    selected_mask::BitVector
    savings::Vector{Float64}
end
RepairWorkspace()=RepairWorkspace(RangeCache[],InsertionOption[],RouteBuffer(),Int[],Int[],Int[],Int[],
    NTuple{2,Int}[],Set{NTuple{3,Int}}(),BitVector(),Int[],Int[],BitVector(),Float64[])
@inline function segment(c::RangeCache,d,D,a,b)
    a>b && return Segment()
    isempty(c.cells) ? summarize(d,D,c.route,a,b) : c.cells[a,b]
end
"Cuts a<=b insert a pickup and its delivery, with arbitrary intervening visits."
@inline function insertion_summary(c,d,D,pair,a,b)
    s=concatenate(segment(c,d,D,1,a),Segment(d,pair[1]),D)
    s=concatenate(s,segment(c,d,D,a+1,b),D)
    s=concatenate(s,Segment(d,pair[2]),D)
    concatenate(s,segment(c,d,D,b+1,length(c.route)),D)
end
function insert_pair(route,pair,a,b)
    v=Vector{Int}(undef,length(route)+2);i=1
    for j in 1:a;v[i]=route[j];i+=1;end
    v[i]=pair[1];i+=1
    for j in a+1:b;v[i]=route[j];i+=1;end
    v[i]=pair[2];i+=1
    for j in b+1:length(route);v[i]=route[j];i+=1;end
    v
end
request_ids(p,route)=[i for (i,(a,_)) in enumerate(p.data.pairs) if a in route]
function request_ids!(out,p,route;append=false)
    append || empty!(out)
    for (i,(a,_)) in enumerate(p.data.pairs);a in route && push!(out,i);end
    out
end
"Borrowed request selection; preserve the allocating randperm path's exact RNG consumption."
function random_requests!(workspace::RepairWorkspace,n,rng;count=2)
    count>=0 || throw(ArgumentError("nonnegative request count required"))
    resize!(workspace.choices,n);randperm!(rng,workspace.choices)
    selected=workspace.selected;resize!(selected,min(count,n))
    copyto!(selected,1,workspace.choices,1,length(selected))
    selected
end
original_workspace()=isdefined(Benchmarks,:PDPTWValidationWorkspace) ? Benchmarks.PDPTWValidationWorkspace() : nothing
original_check(p,routes,workspace)=workspace===nothing ? validate_solution(p,routes) : validate_solution(p,routes,workspace)
quality(p,routes;validation_workspace=nothing) = let q=original_check(p,routes,validation_workspace)
    q.valid || throw(ArgumentError("invalid full original solution"))
    (q.objective.vehicles,q.objective.distance)
end
function counter!(trace,key,amount=1)
    trace[key]=get(trace,key,0)+amount
end
function remove_requests!(routes,p,ids;workspace=nothing)
    removed=workspace===nothing ? falses(length(p.data.demand)) : workspace.removed
    resize!(removed,length(p.data.demand));fill!(removed,false)
    for i in ids
        i==0 && continue # fixed-width ejection tuples use zero for the absent second request
        a,b=p.data.pairs[i];removed[a]=true;removed[b]=true
    end
    for route in routes;filter!(v->!removed[v],route);end
    filter!(!isempty,routes)
    routes
end
"Destroy always removes complete requests, including partners outside a SISR string."
function destroy!(routes,p,D,rng,mode,count;string_requests=4,trace=Dict{String,Any}(),guide_ids=Int[],workspace=RepairWorkspace())
    allids=workspace.all_ids;empty!(allids)
    for r in routes;request_ids!(allids,p,r;append=true);end
    selected=workspace.selected;empty!(selected)
    isempty(allids) && return selected
    count=clamp(count,1,length(allids));pivot=rand(rng,allids)
    if !isempty(guide_ids)
        mask=workspace.selected_mask;resize!(mask,length(p.data.pairs));fill!(mask,false)
        for i in guide_ids
            i in allids && !mask[i] && (push!(selected,i);mask[i]=true)
            length(selected)>=count && break
        end
        shuffle!(rng,allids)
        for i in allids
            length(selected)>=count && break
            !mask[i] && (push!(selected,i);mask[i]=true)
        end
    elseif mode==:route
        request_ids!(selected,p,rand(rng,routes))
    elseif mode==:sisr
        route=rand(rng,routes);a=rand(rng,eachindex(route));len=min(length(route),2string_requests)
        nodes=workspace.removed;resize!(nodes,length(p.data.demand));fill!(nodes,false)
        for j in a:min(length(route),a+len-1);nodes[route[j]]=true;end
        for (i,(u,v)) in enumerate(p.data.pairs);(nodes[u] || nodes[v]) && push!(selected,i);end
    elseif mode==:shaw
        a,b=p.data.pairs[pivot]
        scores=workspace.savings;resize!(scores,length(p.data.pairs))
        for i in allids
            u,v=p.data.pairs[i]
            scores[i]=D[a,u]+D[b,v]+0.2abs(p.data.earliest[a]-p.data.earliest[u])
        end
        # Capture one immutable binding; a/b are reassigned in other destruction
        # branches and capturing them directly boxes every comparator evaluation.
        sort!(allids;alg=QuickSort,by=let rank=scores; i->rank[i];end)
        append!(selected,@view allids[1:count])
    elseif mode==:worst
        savings=workspace.savings;resize!(savings,length(p.data.pairs))
        for i in allids
            a,b=p.data.pairs[i]
            r=routes[findfirst(let pickup=a; r->pickup in r;end,routes)];kept_distance=0.;prev=1
            for v in r
                (v==a || v==b) && continue
                kept_distance+=D[prev,v];prev=v
            end
            kept_distance+=D[prev,1]
            savings[i]=Pilot.route_distance(r,D)-kept_distance
        end
        sort!(allids;by=i->(-savings[i],i),alg=QuickSort);append!(selected,@view allids[1:count])
    elseif mode==:random
        shuffle!(rng,allids);append!(selected,@view allids[1:count])
    else
        throw(ArgumentError("unknown destruction $mode"))
    end
    remove_requests!(routes,p,selected;workspace);counter!(trace,"destroyed_requests",length(selected))
    selected
end

"Best insertion in each route is a distinct regret alternative; all cuts preserve precedence."
function insertion_options(p,D,routes,request,caches,deadline,rng,trace;
        blinks=0.,max_candidates=LIMITS.insertion_candidates,pheromone=nothing,options=InsertionOption[])
    opts=options;empty!(opts);pair=p.data.pairs[request];examined=0;blinked=0
    # Keep high-frequency counters as machine integers; publish once on every exit.
    try
    for (r,cache) in enumerate(caches)
        best=nothing;n=length(cache.route);old=distance(segment(cache,p.data,D,1,n),D)
        for a in 0:n,b in a:n
            time_ns()>=deadline && return opts
            examined>=max_candidates && (counter!(trace,"insertion_cap_hits");return opts)
            examined+=1
            blinks>0 && rand(rng)<blinks && (blinked+=1;continue)
            s=insertion_summary(cache,p.data,D,pair,a,b)
            sequence_feasible(p.data,D,s) || continue
            delta=distance(s,D)-old
            guidance=if pheromone===nothing;0.
            else
                prev=a==0 ? 1 : cache.route[a];nxt=b==n ? 1 : cache.route[b+1]
                -0.2(log(max(pheromone[prev,pair[1]],1e-6))+log(max(pheromone[pair[2],nxt],1e-6)))
            end
            option=(;route=r,a,b,delta,rank=delta+guidance)
            (best===nothing || option.rank<best.rank) && (best=option)
        end
        best===nothing || push!(opts,best)
    end
    sort!(opts;by=x->(x.rank,x.route,x.a,x.b),alg=QuickSort)
    finally
        examined>0 && counter!(trace,"summary_evaluations",examined)
        blinked>0 && counter!(trace,"blinked_insertions",blinked)
    end
end
function build_caches!(workspace,p,D,routes,trace)
    caches=workspace.caches
    while length(caches)<length(routes);push!(caches,RangeCache(Int[],Matrix{Segment}(undef,0,0)));end
    for i in eachindex(routes);range_cache!(caches[i],p.data,D,routes[i]);end
    counter!(trace,"cache_builds",length(routes))
    counter!(trace,"scan_fallback_routes",count(i->!isempty(caches[i].route) && isempty(caches[i].cells),eachindex(routes)))
    @view caches[1:length(routes)]
end
"Repair an owned partial state. A nonempty bank is never admitted to the original CBLS model."
function repair!(routes,bank,p,D,rng,deadline;regret=2,blinks=0.,max_routes=length(routes),
        trace=Dict{String,Any}(),difficulty=ones(Int,length(p.data.pairs)),pheromone=nothing,workspace=RepairWorkspace())
    regret in (1,2,3) || throw(ArgumentError("repair regret must be 1/2/3"))
    caches=build_caches!(workspace,p,D,routes,trace)
    while !isempty(bank) && time_ns()<deadline
        chosen=nothing;priority=(-Inf,-Inf)
        for request in bank
            opts=insertion_options(p,D,routes,request,caches,deadline,rng,trace;blinks,pheromone,options=workspace.options)
            if isempty(opts) && length(routes)<max_routes
                c=range_cache(p.data,D,Int[])
                s=insertion_summary(c,p.data,D,p.data.pairs[request],0,0)
                sequence_feasible(p.data,D,s) && push!(opts,(route=length(routes)+1,a=0,b=0,delta=distance(s,D),rank=distance(s,D)))
            end
            isempty(opts) && continue
            # Scarce alternatives are repaired first; no fictitious finite alternative is added.
            scarcity=max(0,regret-length(opts));gap=sum(opts[min(j,end)].rank-opts[1].rank for j in 2:regret;init=0.)
            key=(Float64(scarcity)*1e12+gap+0.01difficulty[request],-opts[1].rank)
            if chosen===nothing || key>priority;chosen=(;request,option=opts[1]);priority=key;end
        end
        chosen===nothing && return false
        time_ns()>=deadline && return false
        r=chosen.option.route; o=chosen.option
        if r>length(routes)
            push!(routes,Int[])
            length(workspace.caches)<r && push!(workspace.caches,RangeCache(Int[],Matrix{Segment}(undef,0,0)))
            caches=@view workspace.caches[1:length(routes)]
            range_cache!(caches[r],p.data,D,Int[])
        end
        pair=p.data.pairs[chosen.request]
        insert!(routes[r],o.b+1,pair[2]);insert!(routes[r],o.a+1,pair[1])
        range_cache!(caches[r],p.data,D,routes[r]);counter!(trace,"cache_builds")
        filter!(!=(chosen.request),bank);counter!(trace,"reinserted_requests")
    end
    isempty(bank)
end

"Bounded GES adaptation: eliminate one route, repair the bank, eject one or two requests when blocked."
function elimination!(routes,p,D,rng,deadline;depth=1,difficulty=ones(Int,length(p.data.pairs)),
        regret=2,trace=Dict{String,Any}(),candidate_limit=LIMITS.ejection_candidates,workspace=RepairWorkspace())
    depth in (1,2) || throw(ArgumentError("ejection depth must be 1 or 2"))
    candidate_limit>0 || throw(ArgumentError("positive ejection candidate limit required"))
    length(routes)<=1 && return false
    choices=workspace.choices;resize!(choices,length(routes));choices.=eachindex(routes)
    sort!(choices;by=i->(length(routes[i]),Pilot.route_distance(routes[i],D),i),alg=QuickSort)
    chosen=rand(rng,@view choices[1:min(3,end)]);bank=request_ids!(workspace.bank,p,routes[chosen]);deleteat!(routes,chosen)
    max_routes=length(routes);attempts=0;seen=workspace.seen;empty!(seen)
    effort=clamp(8maximum(difficulty[bank]),8,LIMITS.ejection_attempts)
    trace["last_ejection_effort_budget"]=effort
    while !isempty(bank) && time_ns()<deadline && attempts<effort
        repair!(routes,bank,p,D,rng,deadline;regret,max_routes,trace,difficulty,workspace) && return true
        time_ns()>=deadline && break
        blocked=first(bank)
        for i in bank;(-difficulty[i],i)<(-difficulty[blocked],blocked) && (blocked=i);end
        difficulty[blocked]+=1
        candidates=workspace.candidates;empty!(candidates)
        for r in routes;request_ids!(candidates,p,r;append=true);end
        sort!(candidates;by=i->(difficulty[i],i),alg=QuickSort)
        resize!(candidates,min(length(candidates),candidate_limit))
        sets=workspace.ejections;empty!(sets)
        for i in candidates;push!(sets,(i,0));end
        if depth==2
            for a in eachindex(candidates),b in a+1:length(candidates);push!(sets,(candidates[a],candidates[b]));end
        end
        progressed=false
        for ejected in sets
            time_ns()>=deadline && break
            attempts+=1;counter!(trace,"ejection_attempts")
            attempts>effort && break
            key=(blocked,ejected[1],ejected[2]);key in seen && continue;push!(seen,key)
            trial=copy_routes!(workspace.ejection,routes);remove_requests!(trial,p,ejected;workspace)
            pending=workspace.pending;empty!(pending);push!(pending,blocked)
            if repair!(trial,pending,p,D,rng,deadline;regret,max_routes,trace,difficulty,workspace)
                # Retain caller-owned routes: the next ejection must not overwrite an admitted repair state.
                for i in eachindex(trial)
                    if i>length(routes);push!(routes,copy(trial[i]));else;resize!(routes[i],length(trial[i]));copyto!(routes[i],trial[i]);end
                end
                resize!(routes,length(trial));filter!(!=(blocked),bank)
                push!(bank,ejected[1]);ejected[2]!=0 && push!(bank,ejected[2])
                counter!(trace,"ejected_requests",ejected[2]==0 ? 1 : 2);progressed=true;break
            end
        end
        progressed || break
    end
    counter!(trace,"failed_eliminations");false
end

"Exchange two complete requests between distinct routes; validate all original constraints."
function exchange(p,routes,D,first_id,second_id;workspace=nothing,original_distance_prefilter=false,validation_workspace=nothing)
    a,b=p.data.pairs[first_id];c,d=p.data.pairs[second_id]
    ra=findfirst(r->a in r,routes);rb=findfirst(r->c in r,routes)
    (ra===nothing || rb===nothing || ra==rb) && return nothing
    trial=workspace===nothing ? deepcopy(routes) : copy_routes!(workspace,routes)
    for i in eachindex(trial[ra]);v=trial[ra][i];trial[ra][i]=v==a ? c : v==b ? d : v;end
    for i in eachindex(trial[rb]);v=trial[rb][i];trial[rb][i]=v==c ? a : v==d ? b : v;end
    # Only the owned controller opts in: its D is the original Euclidean matrix.
    # Reject an infeasible modified route before allocating the full audit. Every
    # surviving candidate still passes the independent original validator below.
    if original_distance_prefilter
        Pilot.feasible_route(trial[ra],p.data,D) && Pilot.feasible_route(trial[rb],p.data,D) || return nothing
    end
    original_check(p,trial,validation_workspace).valid ? trial : nothing
end

"A graph edge is certified only after checking all six paired interleavings."
function incompatibilities(p,D;max_requests=LIMITS.incompatibility_requests,deadline=typemax(UInt64))
    n=length(p.data.pairs);g=falses(n,n);tested=0
    # Removing other requests preserves feasibility only with nonnegative service and Euclidean metric.
    all(>=(0),p.data.service) || return (;graph=g,tested,scope="disabled_negative_service")
    all(pair->p.data.demand[pair[1]]>=0 && p.data.demand[pair[2]]==-p.data.demand[pair[1]],p.data.pairs) ||
        return (;graph=g,tested,scope="disabled_nonstandard_pair_demands")
    nodes=unique(vcat([1],reduce(vcat,([a,b] for (a,b) in p.data.pairs[1:min(n,max_requests)]);init=Int[])))
    all(D[i,j]==hypot(p.data.coordinates[i,1]-p.data.coordinates[j,1],p.data.coordinates[i,2]-p.data.coordinates[j,2])
        for i in nodes for j in nodes) || return (;graph=g,tested,scope="disabled_non_euclidean_input")
    for i in 1:min(n,max_requests),j in i+1:min(n,max_requests)
        time_ns()>=deadline && return (;graph=g,tested,scope="bounded_certified_edges_only")
        a,b=p.data.pairs[i];c,d=p.data.pairs[j]
        feasible=any(r->Pilot.feasible_route(r,p.data,D),([a,b,c,d],[a,c,b,d],[a,c,d,b],[c,d,a,b],[c,a,d,b],[c,a,b,d]))
        g[i,j]=g[j,i]=!feasible;tested+=1
    end
    (;graph=g,tested,scope="bounded_certified_edges_only")
end
function clique_bound(g)
    clique=Int[]
    for i in sortperm(vec(sum(g;dims=2));rev=true)
        all(j->g[i,j],clique) && push!(clique,i)
    end
    (;bound=isempty(g) ? 0 : max(1,length(clique)),requests=clique,scope="certified_greedy_clique_not_maximum_clique")
end

mutable struct RoutePool
    routes::Vector{Vector{Int}}
    solutions::Vector{Vector{Vector{Int}}}
    max_routes::Int
    max_solutions::Int
end
RoutePool(;max_routes=LIMITS.pool_routes,max_solutions=LIMITS.pool_solutions)=RoutePool(Vector{Int}[],Vector{Vector{Int}}[],max_routes,max_solutions)
function route_valid(p,D,route)
    allunique(route) && all(v->2<=v<=length(p.data.demand),route) || return false
    seen=Set(route)
    for (a,b) in p.data.pairs
        (a in seen)==(b in seen) || return false
        a in seen && findfirst(==(a),route)>=findfirst(==(b),route) && return false
    end
    !isempty(route) && Pilot.feasible_route(route,p.data,D)
end
"Keep incumbent cover protected even when the route pool cap is smaller than its fleet."
function collect!(pool,p,D,routes;validation_workspace=nothing)
    original_check(p,routes,validation_workspace).valid || throw(ArgumentError("only original-feasible solutions may enter the pool"))
    # Already owned, validated snapshots need no duplicate copy or column rebuild.
    routes in pool.solutions && all(r->r in pool.routes,routes) && return pool
    candidate=deepcopy(routes)
    candidate in pool.solutions || push!(pool.solutions,candidate)
    sort!(pool.solutions;by=r->quality(p,r;validation_workspace));resize!(pool.solutions,min(length(pool.solutions),pool.max_solutions))
    protected=first(pool.solutions)
    columns=deepcopy(protected)
    for route in vcat(routes,pool.routes)
        route_valid(p,D,route) || throw(ArgumentError("invalid pool route"))
        length(columns)>=max(pool.max_routes,length(protected)) && break
        route in columns || push!(columns,copy(route))
    end
    pool.routes=columns
    pool
end

"Periodic restricted set partitioning: expose LP prices; MIP exports integral original tours."
function recombine(pool,p,D,deadline;lp_solver="simplex",trace=Dict{String,Any}(),validation_workspace=original_workspace())
    isempty(pool.solutions) && return nothing
    lp_solver in ("simplex","ipx","hipo") || throw(ArgumentError("unknown master LP solver"))
    time_ns()>=deadline && return nothing
    started=time_ns();columns=pool.routes;n=length(columns);cover=[request_ids(p,r) for r in columns]
    all(r->route_valid(p,D,r),columns) || throw(ArgumentError("invalid column"))
    m=Model(Pilot.HiGHS.Optimizer);set_silent(m)
    set_optimizer_attribute(m,"threads",1);set_optimizer_attribute(m,"parallel","off")
    @variable(m,0<=x[1:n]<=1)
    rows=@constraint(m,[i=1:length(p.data.pairs)],sum(x[j] for j in 1:n if i in cover[j])==1)
    @constraint(m,sum(x)<=p.data.vehicles)
    w=2(length(p.data.demand)-1)*maximum(D)+1
    costs=[w+Pilot.route_distance(r,D) for r in columns]
    @objective(m,Min,sum(costs[j]*x[j] for j in 1:n))
    trace["master_bound_scope"]="restricted_route_pool_not_global_original_bound"
    trace["master_lp_solver"]=lp_solver;trace["master_native_threads"]=1
    trace["master_build_seconds"]=get(trace,"master_build_seconds",0.)+(time_ns()-started)/1e9
    remaining()=max(0.,Float64(Int128(deadline)-Int128(time_ns()))/1e9)
    time_ns()>=deadline && return nothing
    set_optimizer_attribute(m,"solver",lp_solver);set_time_limit_sec(m,remaining());optimize!(m)
    counter!(trace,"master_lp_calls")
    if termination_status(m)==MOI.OPTIMAL && has_duals(m)
        trace["master_last_dual_prices"]=dual.(rows)
        trace["master_last_restricted_lp_objective"]=objective_value(m)
    end
    time_ns()>=deadline && return nothing
    set_optimizer_attribute(m,"solver","choose")
    for j in 1:n;set_binary(x[j]);set_start_value(x[j],columns[j] in first(pool.solutions) ? 1. : 0.);end
    set_time_limit_sec(m,remaining());optimize!(m);counter!(trace,"master_mip_calls")
    has_values(m) || return nothing
    vals=value.(x);all(v->abs(v-round(v))<=1e-6,vals) || error("fractional master solution cannot be exported")
    candidate=[copy(columns[j]) for j in 1:n if vals[j]>0.5]
    original_check(p,candidate,validation_workspace).valid || error("restricted master failed original validator")
    time_ns()>=deadline ? nothing : candidate
end

struct RoutePoolResolver <: LS.AbstractMetaVariableResolver
    lp_solver::String
end
"Resolve an owned route pool through LocalSearchSolvers' public semantic meta-variable API."
function LS.resolve_meta_variable(resolver::RoutePoolResolver,request::LS.MetaVariableRequest)
    started=time_ns();budget=Float64(request.budget)
    isfinite(budget) && budget>=0 || throw(ArgumentError("finite nonnegative master budget required"))
    trace=Dict{String,Any}("representation"=>"customer-successor/1","fragment"=>"validated route pool",
        "budget_seconds"=>budget,"threads"=>1)
    finish(status,move=nothing)=(;status,move,elapsed_seconds=(time_ns()-started)/1e9,trace)
    budget==0 && return finish(:budget_exhausted)
    snapshot=request.snapshot;p=snapshot.instance;current=MetaRepair.successors(p,snapshot.routes)
    current==snapshot.values || throw(ArgumentError("mutated master snapshot"))
    ids=LS.scope(request.variable)
    sort(ids)==collect(eachindex(current)) || return finish(:invalid_fragment)
    deadline=started+UInt64(round(Int,budget*1e9))
    validation_workspace=original_workspace()
    candidate=recombine(snapshot.pool,p,snapshot.distances,deadline;lp_solver=resolver.lp_solver,trace,validation_workspace)
    candidate===nothing && return finish(time_ns()>=deadline ? :budget_exhausted : :no_improvement)
    quality(p,candidate;validation_workspace)<quality(p,snapshot.routes;validation_workspace) || return finish(:no_improvement)
    next=MetaRepair.successors(p,candidate)
    time_ns()>=deadline && return finish(:budget_exhausted)
    move=LS.MetaMove(request.variable,next[ids];provenance=(source=:highs_route_pool,lp_solver=resolver.lp_solver))
    finish(:improved,move)
end

mutable struct Lane{P,G,W,V}
    parent::P
    guide::G
    guide_workspace::W
    rng::Xoshiro
    current::Vector{Vector{Int}}
    best::Vector{Vector{Int}}
    q::Tuple{Int,Float64}
    best_q::Tuple{Int,Float64}
    difficulty::Vector{Int}
    weights::Vector{Float64}
    pheromone::Matrix{Float64}
    history::Vector{Float64}
    tabu::Dict{Tuple{Int,Int},Int}
    new_arcs::Set{Tuple{Int,Int}}
    old_arcs::Set{Tuple{Int,Int}}
    graph::BitMatrix
    repair_workspace::RepairWorkspace
    trial_workspace::RouteBuffer
    exchange_workspace::RouteBuffer
    successor_values::Vector{Int}
    changed_variables::Vector{Int}
    matched_routes::BitVector
    inherited_requests::BitVector
    inheritance_order::Vector{Int}
    validation_workspace::V
    pair_workspace::Hybrid.PairRelocationWorkspace
    pool::RoutePool
    steps::Int
    unchanged_proposals::Int
    origin::UInt64
    deadline::UInt64
    trace::Dict{String,Any}
end
function Lane(p,initial;seed=41,scorer=nothing,origin=time_ns(),deadline=typemax(UInt64),guidance=:none,instance_sha256=nothing)
    parent=Hybrid.prepare_parent(p,initial;seed,scorer)
    D=parent.distances;n=length(p.data.demand)
    relations=[(a-1,b-1,1/(1+D[a,b])) for (a,b) in p.data.pairs]
    g=Hybrid.QUBOGuidance.configured_guide(fill(1:n,n-1),relations;id=p.id,instance_sha256)
    # Structural fallback is explicitly unlearned; externally configured learned matrices retain their provenance.
    workspace=Hybrid.QUBOGuidance.Workspace(g)
    validation_workspace=original_workspace()
    q=quality(p,initial;validation_workspace);trace=Dict{String,Any}("trajectory"=>Any[],"controller"=>"structured original-route CBLS MetaMove controller/1",
        "guidance_authority"=>"guidance_only","guide_provenance"=>g.provenance,
        "reset_counter_scope"=>"actual paired-request ruin/recreate resets",
        "incremental_scope"=>"fixed-sequence feasibility summaries; full ICN score remains acceptance authority")
    for key in ("accepted_meta_moves","completed_resets","failed_resets","ejected_requests","tabu_hits","max_tabu_entries","infeasible_steps")
        trace[key]=0
    end
    graph=falses(length(p.data.pairs),length(p.data.pairs))
    if guidance==:incompatibility
        evidence=incompatibilities(p,D;deadline);graph=evidence.graph;c=clique_bound(graph)
        trace["incompatibility_pairs_tested"]=evidence.tested;trace["clique_fleet_lower_bound"]=c.bound
        trace["clique_scope"]=c.scope
    end
    pool=RoutePool();collect!(pool,p,D,initial;validation_workspace)
    Lane(parent,g,workspace,Xoshiro(seed),deepcopy(initial),deepcopy(initial),q,q,
        ones(Int,length(p.data.pairs)),ones(5),ones(size(D)),fill(parent.fleet_weight*q[1]+q[2],LIMITS.late_history),
        Dict{Tuple{Int,Int},Int}(),Set{Tuple{Int,Int}}(),Set{Tuple{Int,Int}}(),graph,
        RepairWorkspace(),RouteBuffer(),RouteBuffer(),ones(Int,n-1),Int[],BitVector(),BitVector(),Int[],
        validation_workspace,Hybrid.PairRelocationWorkspace(),pool,0,0,origin,deadline,trace)
end
function arcs!(out,routes)
    empty!(out)
    for r in routes
        prev=1
        for v in r;push!(out,(prev,v));prev=v;end
        push!(out,(prev,1))
    end
    out
end
arcs(routes)=arcs!(Set{Tuple{Int,Int}}(),routes)
"Exact multiset equality, including duplicate protection; route ordering is not a decision."
function same_routes!(matched,candidate,current)
    length(candidate)==length(current) || return false
    resize!(matched,length(current));fill!(matched,false)
    for route in candidate
        i=findfirst(j->!matched[j] && route==current[j],eachindex(current))
        i===nothing && return false
        matched[i]=true
    end
    true
end
"Original validation, actual error backend and atomic original-variable replacement are all required."
function admit!(lane,p,candidate,settings;source="structured",force=false)
    candidate===nothing && return false
    if same_routes!(lane.matched_routes,candidate,lane.current)
        time_ns()>=lane.deadline && return false
        # The incumbent was already audited; an identical proposal changes no variable.
        lane.history[mod1(lane.steps+1,length(lane.history))]=lane.parent.fleet_weight*lane.q[1]+lane.q[2]
        lane.unchanged_proposals+=1
        !force && settings.acceptance==:greedy && counter!(lane.trace,"rejected_moves")
        return false
    end
    checked=original_check(p,candidate,lane.validation_workspace);checked.valid || error("structured candidate failed original validator")
    q=(checked.objective.vehicles,checked.objective.distance)
    time_ns()>=lane.deadline && return false
    w=lane.parent.fleet_weight;cost=w*q[1]+q[2];old=w*lane.q[1]+lane.q[2]
    index=mod1(lane.steps+1,length(lane.history));tabu_active=settings.acceptance==:tabu
    newarcs=tabu_active ? arcs!(lane.new_arcs,candidate) : nothing
    oldarcs=tabu_active ? arcs!(lane.old_arcs,lane.current) : nothing
    forbidden=tabu_active && any(a->!(a in oldarcs) && get(lane.tabu,a,0)>lane.steps,newarcs)
    aspiration=q<lane.best_q
    accept=force || (settings.acceptance==:greedy ? q<lane.q :
        settings.acceptance==:tabu ? (!forbidden || aspiration) : cost<=old+TOL || cost<=lane.history[index]+TOL)
    lane.history[index]=old
    forbidden && counter!(lane.trace,"tabu_hits")
    accept || (counter!(lane.trace,"rejected_moves");return false)
    values=MetaRepair._successors!(lane.successor_values,candidate);solver=lane.parent.solver
    old_values=LS.get_values(solver)
    ids=lane.changed_variables;empty!(ids)
    for i in eachindex(values);values[i]!=old_values[i] && push!(ids,i);end
    isempty(ids) && (lane.unchanged_proposals+=1;return false)
    move=LS.MetaMove(LS.MetaVariable(:structured_routes,ids),values[ids];provenance=(;source=Symbol(source)))
    iszero(LS._candidate_cost(solver,move)) || error("structured MetaMove rejected by actual error backend")
    time_ns()>=lane.deadline && return false
    LS._commit!(solver,move);LS._compute!(solver);Hybrid.SearchPolicies.synchronize!(solver)
    lane.current=deepcopy(candidate);lane.q=q;counter!(lane.trace,"accepted_meta_moves")
    if tabu_active
        for a in oldarcs
            a in newarcs || (lane.tabu[a]=lane.steps+LIMITS.tabu_tenure)
        end
    end
    filter!(kv->last(kv)>lane.steps,lane.tabu)
    lane.trace["max_tabu_entries"]=max(get(lane.trace,"max_tabu_entries",0),length(lane.tabu))
    collect!(lane.pool,p,lane.parent.distances,candidate;validation_workspace=lane.validation_workspace)
    if q<lane.best_q && time_ns()<lane.deadline
        lane.best=deepcopy(candidate);lane.best_q=q
        t=(time_ns()-lane.origin)/1e9
        time_ns()<lane.deadline && push!(lane.trace["trajectory"],Dict("seconds"=>t,"vehicles"=>q[1],
            "distance"=>q[2],"routes"=>deepcopy(candidate),"source"=>source))
    end
    true
end
function guidance_ids(lane,p,settings)
    ids=collect(eachindex(p.data.pairs));D=lane.parent.distances
    if settings.guidance==:critical
        # Direct slack explanation, not a newly trained ICN explanation network.
        sort!(ids;by=i->let; a,b=p.data.pairs[i]
            p.data.latest[b]-max(p.data.earliest[b],p.data.earliest[a]+p.data.service[a]+D[a,b])
        end)
    elseif settings.guidance==:incompatibility
        sort!(ids;by=i->-sum(@view lane.graph[i,:]))
    elseif settings.guidance==:qubo
        values=MetaRepair._successors!(lane.successor_values,lane.current)
        scope=Hybrid.QUBOGuidance.scope!(lane.guide_workspace,lane.guide,values,min(8,length(values)),lane.rng;mode="conditional")
        nodes=Set(i+1 for i in scope)
        sort!(ids;by=i->let; a,b=p.data.pairs[i];(a in nodes || b in nodes) ? 0 : 1;end)
        counter!(lane.trace,"qubo_scopes")
    else
        return get(lane.trace,"master_priority_requests",Int[])
    end
    ids
end
function weighted_index(rng,weights)
    t=rand(rng)*sum(weights);s=0.
    for i in eachindex(weights);s+=weights[i];t<s && return i;end
    lastindex(weights)
end
function reinforce!(pheromone,routes)
    # Independent cells permit SIMD; resource/time propagation deliberately does not.
    @inbounds @simd for i in eachindex(pheromone);pheromone[i]=max(1e-5,0.98pheromone[i]);end
    for (a,b) in arcs(routes);pheromone[a,b]=min(100.,pheromone[a,b]+1.);end
end
function inherited(lane,p,D,deadline,regret)
    parent=rand(lane.rng,lane.pool.solutions);trial=lane.trial_workspace.routes;empty!(trial)
    seen=lane.inherited_requests;resize!(seen,length(p.data.pairs));fill!(seen,false)
    for source in (lane.best,parent)
    order=lane.inheritance_order;resize!(order,length(source));order.=eachindex(source);shuffle!(lane.rng,order)
    for index in order
        r=source[index]
        length(trial)>=length(lane.best) && continue
        any(i->seen[i] && first(p.data.pairs[i]) in r,eachindex(seen)) && continue
        slot=length(trial)+1
        while length(lane.trial_workspace.buffers)<slot;push!(lane.trial_workspace.buffers,Int[]);end
        buffer=lane.trial_workspace.buffers[slot];resize!(buffer,length(r));copyto!(buffer,r)
        push!(trial,buffer)
        for (i,(a,_)) in enumerate(p.data.pairs);a in r && (seen[i]=true);end
        length(trial)>=length(lane.best) && break
    end
    end
    missing=lane.repair_workspace.bank;empty!(missing)
    for i in eachindex(seen);!seen[i] && push!(missing,i);end
    repair!(trial,missing,p,D,lane.rng,deadline;regret,max_routes=length(lane.best),trace=lane.trace,difficulty=lane.difficulty,
        workspace=lane.repair_workspace) ? trial : nothing
end
function step!(lane,p,settings,deadline)
    D=lane.parent.distances;trial=copy_routes!(lane.trial_workspace,lane.current);before=lane.best_q
    algorithm=settings.algorithm;source=string(algorithm)
    # Reset topology by paired requests rather than corrupting raw successor assignments.
    reset=settings.reset_fraction>0 && lane.steps>0 && lane.steps%LIMITS.reset_every==0
    if reset
        count=max(1,ceil(Int,settings.reset_fraction*length(p.data.pairs)))
        bank=destroy!(trial,p,D,lane.rng,:random,count;trace=lane.trace,workspace=lane.repair_workspace)
        ok=repair!(trial,bank,p,D,lane.rng,deadline;regret=3,max_routes=length(lane.best),trace=lane.trace,workspace=lane.repair_workspace)
        if ok
            counter!(lane.trace,"completed_resets");admit!(lane,p,trial,settings;source="paired_reset",force=true)
        else;counter!(lane.trace,"failed_resets");end
        return
    end
    op=0
    if algorithm==:sisr && lane.steps%4==0 && length(trial)>1
        counter!(lane.trace,"sisr_fleet_attempts")
        if elimination!(trial,p,D,lane.rng,deadline;depth=settings.ejection_depth,difficulty=lane.difficulty,
                regret=settings.regret,trace=lane.trace,workspace=lane.repair_workspace)
            admit!(lane,p,trial,settings;source="sisr_fleet_reduction")
            return
        end
        trial=copy_routes!(lane.trial_workspace,lane.current)
    end
    if algorithm==:ges
        ok=elimination!(trial,p,D,lane.rng,deadline;depth=settings.ejection_depth,difficulty=lane.difficulty,
            regret=settings.regret,trace=lane.trace,workspace=lane.repair_workspace)
        counter!(lane.trace,"elimination_calls")
        ok || return
    elseif algorithm==:vnd
        # Relocation, exchange and a two-request repair chain cycle; improvement restarts at relocation.
        which=mod1(get(lane.trace,"vnd_neighborhood",1),3);pairs=p.data.pairs
        if which==1
            candidate=Hybrid.pair_relocation(p,trial,D,rand(lane.rng,pairs);deadline_ns=deadline,selection=:best,workspace=lane.pair_workspace)
            trial=candidate.routes;counter!(lane.trace,"relocation_evaluations",candidate.examined)
        elseif which==2
            ids=random_requests!(lane.repair_workspace,length(pairs),lane.rng)
            trial=length(ids)==2 ? exchange(p,trial,D,ids...;workspace=lane.exchange_workspace,original_distance_prefilter=true,
                validation_workspace=lane.validation_workspace) : nothing;counter!(lane.trace,"exchange_calls")
        else
            ids=random_requests!(lane.repair_workspace,length(pairs),lane.rng);remove_requests!(trial,p,ids;workspace=lane.repair_workspace)
            repair!(trial,ids,p,D,lane.rng,deadline;regret=3,max_routes=length(lane.current),trace=lane.trace,workspace=lane.repair_workspace) || (trial=nothing)
            counter!(lane.trace,"two_request_chains")
        end
        lane.trace["vnd_neighborhood"]=which+1
    elseif algorithm==:memetic
        trial=inherited(lane,p,D,deadline,settings.regret);counter!(lane.trace,"route_inheritance_calls")
    else
        modes=(:random,:shaw,:worst,:route,:sisr)
        mode=algorithm==:sisr ? :sisr : settings.destroy
        if mode==:adaptive;op=weighted_index(lane.rng,lane.weights);mode=modes[op];end
        count=max(1,ceil(Int,LIMITS.destroy_fraction*length(p.data.pairs)))
        ids=guidance_ids(lane,p,settings)
        bank=destroy!(trial,p,D,lane.rng,mode,count;trace=lane.trace,guide_ids=ids,
            string_requests=LIMITS.string_requests,workspace=lane.repair_workspace)
        counter!(lane.trace,"destroy_$(mode)_calls")
        repair!(trial,bank,p,D,lane.rng,deadline;regret=settings.regret,blinks=settings.blinks,
            max_routes=length(lane.current),trace=lane.trace,difficulty=lane.difficulty,
            pheromone=algorithm==:aco ? lane.pheromone : nothing,workspace=lane.repair_workspace) || return
    end
    trial===nothing && return
    accepted=admit!(lane,p,trial,settings;source)
    improved=lane.best_q<before
    op>0 && (lane.weights[op]=0.9lane.weights[op]+0.1(improved ? 8. : accepted ? 2. : 0.5))
    improved && algorithm==:vnd && (lane.trace["vnd_neighborhood"]=1)
    algorithm==:aco && (reinforce!(lane.pheromone,lane.best);counter!(lane.trace,"pheromone_updates"))
end
function episode!(lane,p,settings,deadline;max_steps=LIMITS.episode_steps)
    deadline=min(deadline,lane.deadline)
    for _ in 1:max_steps
        (time_ns()>=deadline || lane.steps>=LIMITS.max_steps) && break
        step!(lane,p,settings,deadline);lane.steps+=1
    end
    lane.trace["steps"]=lane.steps;lane.trace["unchanged_proposals"]=lane.unchanged_proposals
    lane.trace["operator_weights"]=copy(lane.weights)
    lane.best
end
function share!(lane,p,pool,settings)
    isempty(pool.solutions) && return
    for routes in pool.solutions;collect!(lane.pool,p,lane.parent.distances,routes;validation_workspace=lane.validation_workspace);end
    candidate=first(pool.solutions)
    if quality(p,candidate;validation_workspace=lane.validation_workspace)<lane.q
        admit!(lane,p,candidate,settings;source="episode_exchange",force=true) && counter!(lane.trace,"received_incumbents")
    end
end

"Execute each cooperative episode through the prepared typed MetaStrategist kernel."
function run_portfolio(p,initial,id,seconds,seed,banks,strategy,execute;
        origin=time_ns(),initial_seconds=0.,max_episodes=typemax(Int),cpu_clock=()->0.,instance_sha256=nothing,
        episode_steps=LIMITS.episode_steps,episode_seconds=LIMITS.episode_seconds,fill_episode=true)
    width=length(strategy.workers);roles=RoutingPanel.CATALOG[id].lanes
    deadline=origin+UInt64(round(Int,seconds*1e9));lanes=Any[];backends=Any[]
    for i in 1:width
        r=roles[mod1(i,length(roles))];kind=r.backend in (:icn_fused_all,:icn_fused_scalar) ? :icn : r.backend
        backend=execute.clone_backend(banks[kind],r.backend)
        push!(backends,backend)
        push!(lanes,Base.invokelatest(Lane,p,initial;seed=seed+10000(i-1),scorer=backend,origin,deadline,guidance=r.guidance,instance_sha256))
    end
    # Any rotating role may need the graph, even when its initial lane does not.
    if any(r->r.guidance==:incompatibility,roles)
        evidence=incompatibilities(p,first(lanes).parent.distances;deadline)
        for lane in lanes;lane.graph=copy(evidence.graph);end
    end
    validation_workspace=original_workspace() # Coordinator-owned; used only after all lanes join.
    pool=RoutePool();D=first(lanes).parent.distances;collect!(pool,p,D,initial;validation_workspace)
    records=Vector{Any}(undef,width);episodes=0;role_scores=ones(length(roles));role_counts=zeros(Int,length(roles))
    chosen=[mod1(i,length(roles)) for i in 1:width];master_seconds=0.;coord=Dict{String,Any}()
    while time_ns()<deadline && episodes<max_episodes
        episodes+=1
        # Mandatory round-robin exploration makes all roles observable at widths 1/2.
        adaptive=any(r->r.adaptive_roles,roles)
        for i in 1:width
            chosen[i]=adaptive && episodes>length(roles) && episodes%4!=0 ?
                weighted_index(lanes[i].rng,role_scores) : mod1(i+episodes-1,length(roles))
            Base.invokelatest(share!,lanes[i],p,pool,roles[chosen[i]])
        end
        stop=min(deadline,time_ns()+UInt64(round(Int,episode_seconds*1e9)))
        before=[l.best_q for l in lanes]
        invoke=(i,_)->begin
            settings=roles[chosen[i]];cpu=cpu_clock()
            lanes[i].trace["julia_thread_id"]=Threads.threadid()
            # Continue bounded chunks until the shared barrier time. A fast lane must
            # not wait after 64 cheap steps while another lane consumes its whole slice.
            while time_ns()<stop
                previous_steps=lanes[i].steps
                Base.invokelatest(episode!,lanes[i],p,settings,stop;max_steps=episode_steps)
                (!fill_episode || lanes[i].steps==previous_steps || lanes[i].steps>=LIMITS.max_steps) && break
            end
            counter!(lanes[i].trace,"episodes");counter!(lanes[i].trace,"role_$(settings.algorithm)_episodes")
            counter!(lanes[i].trace,"thread_cpu_seconds",cpu_clock()-cpu)
            nothing
        end
        execute.run(strategy,invoke,records)
        for i in 1:width
            role_counts[chosen[i]]+=1
            reward=lanes[i].best_q<before[i] ? 8. : 1.
            role_scores[chosen[i]]=0.9role_scores[chosen[i]]+0.1reward
            Base.invokelatest(collect!,pool,p,D,lanes[i].best;validation_workspace)
            # Accepted diverse solutions also supply alternative route columns.
            Base.invokelatest(collect!,pool,p,D,lanes[i].current;validation_workspace)
        end
        if any(r->r.master,roles) && episodes%LIMITS.master_every==0 && time_ns()<deadline &&
                master_seconds<LIMITS.master_fraction*seconds
            start=time_ns();allow=min(LIMITS.master_seconds,LIMITS.master_fraction*seconds-master_seconds)
            stop=min(deadline,start+UInt64(round(Int,allow*1e9)))
            mode=first(roles).master_lp
            snapshot=(;instance=p,pool=deepcopy(pool),routes=deepcopy(lanes[1].current),distances=D,
                values=MetaRepair.successors(p,lanes[1].current))
            remaining=max(0.,Float64(Int128(stop)-Int128(time_ns()))/1e9)
            request=LS.MetaVariableRequest(LS.MetaVariable(:route_pool,eachindex(snapshot.values)),snapshot,remaining,lanes[1].rng)
            outcome=Base.invokelatest(LS.resolve_meta_variable,RoutePoolResolver(mode),request)
            for (k,v) in outcome.trace
                if v isa Number && k in ("master_lp_calls","master_mip_calls","master_build_seconds")
                    coord[k]=get(coord,k,0)+v
                else;coord[k]=v;end
            end
            counter!(coord,"master_resolver_calls");coord["master_last_status"]=string(outcome.status)
            candidate=if outcome.move===nothing;nothing
            else
                values=copy(snapshot.values);values[outcome.move.variables]=outcome.move.replacements
                MetaRepair.routes_from_successors(p,values)
            end
            prices=get(outcome.trace,"master_last_dual_prices",Float64[])
            if length(prices)==length(p.data.pairs)
                for lane in lanes
                    lane.trace["master_priority_requests"]=sortperm(prices;rev=true)
                    lane.trace["master_guidance_scope"]="restricted_pool_LP_duals_guidance_only"
                end
            end
            if candidate!==nothing
                # No column-only result bypasses the original validator / actual error backend.
                Base.invokelatest(admit!,lanes[1],p,candidate,roles[chosen[1]];source="highs_route_pool",force=true)
                Base.invokelatest(collect!,pool,p,D,candidate;validation_workspace)
            end
            master_seconds+=(time_ns()-start)/1e9
        end
        all(l->l.steps>=LIMITS.max_steps,lanes) && break
    end
    workers=Any[]
    for i in 1:width
        l=lanes[i];l.trace["pool_routes"]=length(l.pool.routes)
        push!(workers,Dict{String,Any}("worker"=>i,"method"=>id,"seed"=>seed+10000(i-1),
            "routes"=>l.best,"vehicles"=>l.best_q[1],"distance"=>l.best_q[2],"trace"=>l.trace,
            "thread_cpu_seconds"=>get(l.trace,"thread_cpu_seconds",0.),
            "error_backend"=>haskey(execute,:metadata) ? execute.metadata(backends[i]) : Dict{String,Any}()))
    end
    coord["episodes"]=episodes;coord["fill_episode"]=fill_episode;coord["role_episode_counts"]=role_counts;coord["role_scores"]=role_scores
    coord["master_seconds"]=master_seconds;coord["pool_routes"]=length(pool.routes)
    (;workers,coordination=coord,lanes)
end
end
