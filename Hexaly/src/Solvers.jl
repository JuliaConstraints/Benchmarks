module ReproductionSolvers
using ..ReproductionProblems, ..ReproductionScoring
using JuMP,Random
import CBLS, LocalSearchSolvers as LS, MathOptInterface as MOI, MetaStrategist as MS, HiGHS
include("../../LiLim/src/SearchPolicies.jl")
include("../../LiLim/src/PlatformResources.jl")
include("../../LiLim/src/StrategyPanel.jl")
include("../../LiLim/src/QUBOGuidance.jl")
include("../../LiLim/src/ROFragments.jl")
export prepare_cbls,search!,portfolio,mip_model,solve_mip,solve_ghost,POLICIES
const POLICIES=sort!(collect(keys(SearchPolicies.CONFIG["profiles"])))

function prepare_cbls(p;kind=:direct,policy="greedy_guided",seed=41,hybrid=false,max_cells=250_000,
        overrides=(;),max_visits=16,repair_every=32,fragment_seconds=.5,repair_fraction=.25,
        repair_mode="mip",lp_solver="simplex",mip_lp_solver="choose",radius=4,
        fragment_selection="random",guide_mode="none",guide_depth=4,guide_every=32,
        guide_exploration=.1,guide_fraction=.1,guide=nothing,id="",instance_sha256=nothing,warm_start=false)
    hybrid && !(p.family in (:bpp,:bppc,:vbp,:salbp,:rcpsp,:jssp,:fjsp,:aircraft_landing)) && throw(ArgumentError("No qualified MIP repair for $(p.family)"))
    hybrid && check_mip_size(p,max_cells)
    Random.seed!(seed)
    b=prepare_backend(kind);opt=CBLS.Optimizer();model=direct_model(opt);ds=domains(p);n=length(ds)
    @variable(model,first(ds[i])<=x[i=1:n]<=last(ds[i]),Int)
    err=(v;X=nothing)->error_value(b,p,v)
    @constraint(model,x in CBLS.Error(err))
    obj=v->ReproductionScoring.search_objective_value(b,p,v)
    @objective(model,Min,CBLS.ScalarFunction(obj,x))
    material=SearchPolicies.materialize(opt.backend_model,policy;overrides)
    options=LS.Options(dynamic=false,process_threads_map=Dict(1=>1),print_level=:silent,
        log_mode=:silent,log_to_file=false,progress_mode=:none,use_progress_meter=false)
    solver=LS.solver(opt.backend_model;options,strategies=material.strategy)
    # ICN decoders were generated after this function's world age. Enter once before the hot loop.
    Base.invokelatest(LS._init!,solver)
    start=initial(p)
    for i in eachindex(start);LS._value!(solver,i,start[i]);end
    Base.invokelatest(LS._compute!,solver);SearchPolicies.synchronize!(solver)
    repair_every>0 && fragment_seconds>0 && 0<=repair_fraction<=1 && max_visits>0 || throw(ArgumentError("invalid fragment limits"))
    guide_mode in ("none","absolute","conditional") && guide_every>0 && guide_depth>0 &&
        0<=guide_fraction<=1 && 0<=guide_exploration<=1 || throw(ArgumentError("invalid guide limits"))
    fragment_selection in ("random","bottleneck","qubo") || throw(ArgumentError("invalid fragment selection"))
    guide_started=time_ns()
    if guide_mode!="none" && guide===nothing
        relations=Tuple{Int,Int,Float64}[(i,i+1,1.) for i in 1:n-1]
        for key in ("precedence","conflicts"),(i,j) in get(p.data,key,Tuple{Int,Int}[])
            push!(relations,(i,j,2.))
        end
        guide=QUBOGuidance.configured_guide(ds,relations;id,instance_sha256)
    end
    workspace=guide===nothing ? nothing : QUBOGuidance.Workspace(guide)
    controls=(;max_visits,repair_every,fragment_seconds,repair_fraction,repair_mode,lp_solver,mip_lp_solver,
        radius,fragment_selection,guide_mode,guide_depth,guide_every,guide_exploration,guide_fraction,warm_start)
    (;p,model,solver,backend=b,policy=material.description,seed,start,hybrid,max_cells,controls,
        guide,workspace,candidate=copy(start),current=copy(start),validation_buffer=copy(start),
        guide_build_seconds=guide_mode=="none" ? 0. : (time_ns()-guide_started)/1e9)
end

function decision_values!(buffer,source)
    for i in eachindex(buffer);buffer[i]=Int(source[i]);end
    buffer
end

"RO scopes preserve complete bins or selected original scheduling decisions."
function fragment_scope(lane,values,rng;guided=true)
    c=lane.controls;n=length(values)
    if guided && c.fragment_selection=="qubo" && lane.guide!==nothing
        ids=QUBOGuidance.scope!(lane.workspace,lane.guide,values,c.guide_depth,rng;
            mode=c.guide_mode=="none" ? "absolute" : c.guide_mode,exploration=c.guide_exploration)
    elseif c.fragment_selection=="bottleneck"
        ids=sortperm(values;rev=true)[1:min(c.max_visits,n)]
    else
        ids=randperm(rng,n)[1:min(c.max_visits,n)]
    end
    if lane.p.family in (:bpp,:bppc,:vbp,:salbp)
        # Extend to entire selected bins/stations; reject oversized fragments.
        labels=Set(values[i] for i in ids)
        ids=findall(v->v in labels,values)
        length(ids)>c.max_visits && return Int[]
    end
    sort!(collect(ids))
end

function search!(lane;seconds=1.,max_steps=typemax(Int))
    seconds>0 && isfinite(seconds) || throw(ArgumentError("Positive finite solve budget"))
    start=time_ns();cpu=PlatformResources.cpu_seconds(3);steps=0;infeasible=0;tabu_peak=0;repairs=0;repair_seconds=0.
    gc_start=Base.gc_num().total_time;c=lane.controls
    guide_seconds=lane.guide_build_seconds;guide_candidates=0;guide_moves=0;repair_traces=Any[]
    incumbent=validate(lane.p,lane.start).valid ? copy(lane.start) : nothing
    trajectory=Dict{String,Any}[]
    if incumbent!==nothing
        push!(trajectory,Dict("seconds"=>0.,"values"=>copy(incumbent),"objective"=>collect(validate(lane.p,incumbent).objective)))
    end
    best_objective=incumbent===nothing ? nothing : validate(lane.p,incumbent).objective
    last_native_best=Ref(Inf)
    function consider(candidate)
        (time_ns()-start)/1e9<=seconds || return
        candidate isa AbstractVector || (candidate=decision_values!(lane.validation_buffer,candidate))
        checked=validate(lane.p,candidate)
        observed=(time_ns()-start)/1e9
        if checked.valid && observed<=seconds && (incumbent===nothing || checked.objective<best_objective)
            incumbent=Int.(candidate)
            best_objective=checked.objective
            push!(trajectory,Dict("seconds"=>observed,"values"=>copy(incumbent),"objective"=>collect(checked.objective)))
        end
    end
    while steps<max_steps && (time_ns()-start)/1e9<seconds
        if lane.hybrid && steps%c.repair_every==0 && repair_seconds<c.repair_fraction*seconds
            snapshot=(p=lane.p,values=Int.(collect(LS.get_values(lane.solver))))
            select_started=time_ns();ids=fragment_scope(lane,snapshot.values,Random.default_rng();guided=guide_seconds<c.guide_fraction*seconds)
            c.fragment_selection=="qubo" && (guide_seconds+=(time_ns()-select_started)/1e9)
            budget=min(c.fragment_seconds,max(0.,seconds-(time_ns()-start)/1e9),c.repair_fraction*seconds-repair_seconds)
            if !isempty(ids) && budget>0
                group=LS.MetaVariable(:integer_fragment,ids)
                outcome=LS.resolve_meta_variable(MIPResolver(lane.max_cells;mode=c.repair_mode,lp_solver=c.lp_solver,
                    mip_lp_solver=c.mip_lp_solver,radius=c.radius,warm_start=c.warm_start),
                    LS.MetaVariableRequest(group,snapshot,budget,Random.default_rng()))
                repair_seconds+=outcome.elapsed;push!(repair_traces,outcome.trace)
                if outcome.move!==nothing && (time_ns()-start)/1e9<seconds
                    iszero(LS._candidate_cost(lane.solver,outcome.move)) || error("RO repair fails the qualified error backend")
                    if (time_ns()-start)/1e9<seconds
                        LS._commit!(lane.solver,outcome.move);LS._compute!(lane.solver);SearchPolicies.synchronize!(lane.solver);repairs+=1
                        consider(LS.get_values(lane.solver))
                    end
                end
            end
        end
        if c.guide_mode!="none" && lane.guide!==nothing && steps%c.guide_every==0 && guide_seconds<c.guide_fraction*seconds
            guide_started=time_ns();values=decision_values!(lane.current,LS.get_values(lane.solver))
            proposal=QUBOGuidance.proposal!(lane.workspace,lane.guide,values,c.guide_depth,Random.default_rng();
                mode=c.guide_mode,exploration=c.guide_exploration)
            guide_candidates+=proposal.examined;copyto!(lane.candidate,values)
            for (i,v) in zip(proposal.ids,proposal.values);lane.candidate[i]=v;end
            checked=validate(lane.p,lane.candidate)
            current=validate(lane.p,values)
            if checked.valid && (!current.valid || checked.objective<current.objective) && (time_ns()-start)/1e9<seconds
                move=LS.MetaMove(LS.MetaVariable(:qubo_depth,proposal.ids),proposal.values;provenance=(source=:qubo_guidance,))
                iszero(LS._candidate_cost(lane.solver,move)) || error("Guide proposal fails the qualified error backend")
                LS._commit!(lane.solver,move);LS._compute!(lane.solver);SearchPolicies.synchronize!(lane.solver)
                guide_moves+=1;consider(lane.candidate)
            end
            guide_seconds+=(time_ns()-guide_started)/1e9
        end
        (time_ns()-start)/1e9<seconds || break
        LS._step!(lane.solver);steps+=1;tabu_peak=max(tabu_peak,LS.length_tabu(lane.solver))
        LS.get_error(lane.solver)>0 && (infeasible+=1)
        # Validate/copy only a changed native incumbent, rather than every step.
        if LS.best_value(lane.solver)<last_native_best[]
            consider(LS.best_values(lane.solver));last_native_best[]=LS.best_value(lane.solver)
        end
    end
    # Every trajectory assignment is checked in the original model again on delivery.
    all(row->validate(lane.p,row["values"]).valid,trajectory) || error("Invalid exported trajectory")
    Dict{String,Any}("status"=>incumbent===nothing ? "no_feasible_solution" : "feasible",
        "values"=>incumbent===nothing ? Int[] : incumbent,"trajectory"=>trajectory,
        "objective"=>incumbent===nothing ? Float64[] : collect(validate(lane.p,incumbent).objective),
        "seconds"=>(time_ns()-start)/1e9,"cpu_seconds"=>PlatformResources.cpu_seconds(3)-cpu,
        "budget_overrun_seconds"=>max(0.,(time_ns()-start)/1e9-seconds),
        "steps"=>steps,"infeasible_steps"=>infeasible,"tabu_peak"=>tabu_peak,
        "observable_resets"=>SearchPolicies.sequence_resets(lane.solver.strategies.restart),
        "repair_moves"=>repairs,"repair_seconds"=>repair_seconds,
        "repair_traces"=>repair_traces,"guide_seconds"=>guide_seconds,"guide_candidates"=>guide_candidates,
        "guide_moves"=>guide_moves,"guide"=>lane.guide===nothing ? Dict("authority"=>"disabled") : QUBOGuidance.metadata(lane.guide),
        "process_gc_seconds"=>(Base.gc_num().total_time-gc_start)/1e9,
        "policy"=>lane.policy,"error_backend"=>string(lane.backend.kind),"seed"=>lane.seed,
        "icn_calls"=>lane.backend.calls,"score_evaluations"=>lane.backend.evaluations,
        "icn_bank_sha256"=>lane.backend.bank_sha256)
end

struct ParallelPhase
    workers::Tuple
end
mutable struct PortfolioContext
    lanes::Tuple
    seconds::Float64
    max_steps::Int
    results::Vector{Any}
end
function (phase::ParallelPhase)(ctx::PortfolioContext)
    Threads.@threads :static for i in eachindex(phase.workers)
        Random.seed!(ctx.lanes[i].seed)
        ctx.results[i]=Base.invokelatest(search!,ctx.lanes[i];seconds=ctx.seconds,max_steps=ctx.max_steps)
    end
    nothing
end
function portfolio(p;workers=[(;kind=:icn_fused,policy="late_400")],seconds=1.,seed=41,max_steps=typemax(Int),prepared_lanes=nothing)
    length(workers)<=Threads.nthreads() || throw(ArgumentError("Start Julia with at least one thread per lane"))
    lanes=prepared_lanes===nothing ? Tuple(prepare_cbls(p;w...,seed=seed+i-1) for (i,w) in enumerate(workers)) : Tuple(prepared_lanes)
    length(lanes)==length(workers) || throw(DimensionMismatch("prepared portfolio lanes"))
    catalog=MS.PhaseCatalog()
    MS.register_phase!(catalog,MS.PhaseDefinition(:search,:classical_portfolio,
        (parameters,context)->ParallelPhase(parameters.workers);version="1",reads=(:instance,),writes=(:incumbents,),requires=(:threads,)))
    profile=MS.StrategyProfile(:classical_strategy_panel,"1",Dict(:search=>MS.PhaseChoice(:classical_portfolio,"1";workers=Tuple(workers))))
    ir=MS.resolve_strategy(catalog,profile;roots=(:search,),inputs=(:instance,),capabilities=(:threads,))
    prepared=MS.prepare_strategy(ir;mode=:typed);context=PortfolioContext(lanes,seconds,max_steps,Any[nothing for _ in lanes])
    MS.execute!(prepared.kernel,context)
    context.results
end

"Exact integer formulations for optional MIP/CP comparators; size caps reject unsuitable expansions."
function check_mip_size(p,limit)
    d=p.data;f=p.family;n=length(domains(p))
    cells=if f in (:bpp,:bppc,:vbp,:salbp);n*last(first(domains(p)))
    elseif f==:rcpsp;n*(d["horizon"]+1)
    elseif f==:fjsp;(n÷2)^2
    elseif f==:jssp
        counts=Dict{Int,Int}()
        for i in eachindex(d["duration"]);d["duration"][i]>0 && (counts[d["machine"][i]]=get(counts,d["machine"][i],0)+1);end
        sum(c*(c-1)÷2 for c in values(counts))
    elseif f==:aircraft_landing;n*n
    else;throw(ArgumentError("No qualified integer fragment for $f"));end
    cells<=limit || throw(ArgumentError("Integer formulation exceeds model-size cap"))
    nothing
end
function mip_model(p;max_cells=250_000,symmetry=true)
    check_mip_size(p,max_cells)
    d=p.data;f=p.family;m=Model();ds=domains(p)
    if f in (:bpp,:bppc,:vbp,:salbp)
        n=length(ds);B=last(first(ds));n*B<=max_cells || throw(ArgumentError("Assignment formulation exceeds model-size cap"))
        @variable(m,a[1:n,1:B],Bin);@variable(m,used[1:B],Bin)
        @constraint(m,[i=1:n],sum(a[i,b] for b in 1:B)==1)
        @constraint(m,[i=1:n,b=1:B],a[i,b]<=used[b])
        symmetry && @constraint(m,[b=1:B-1],used[b]>=used[b+1])
        if f==:salbp
            @constraint(m,[b=1:B],sum(d["duration"][i]*a[i,b] for i in 1:n)<=d["cycle"]*used[b])
            for(i,j)in d["precedence"];@constraint(m,sum(b*a[i,b] for b in 1:B)<=sum(b*a[j,b] for b in 1:B));end
        else
            for b in 1:B,r in axes(d["weights"],2)
                @constraint(m,sum(d["weights"][i,r]*a[i,b] for i in 1:n)<=d["capacity"][r]*used[b])
            end
            if f==:bppc;for(i,j)in d["conflicts"],b in 1:B;@constraint(m,a[i,b]+a[j,b]<=1);end;end
        end
        @objective(m,Min,sum(used))
        decode=()->[argmax(value.(a[i,:])) for i in 1:n]
        return (;model=m,decode)
    elseif f==:fjsp
        n=length(d["duration"]);H=d["horizon"];n*n<=max_cells || throw(ArgumentError("Alternative disjunctions exceed model-size cap"))
        @variable(m,0<=s[1:n]<=H,Int);@variable(m,0<=makespan<=H,Int)
        assignments=[[@variable(m,binary=true) for _ in choices] for choices in d["alternatives"]]
        duration=[sum(d["alternatives"][i][k][2]*assignments[i][k] for k in eachindex(assignments[i])) for i in 1:n]
        for i in 1:n;@constraint(m,sum(assignments[i])==1);@constraint(m,s[i]+duration[i]<=makespan);end
        for(i,j)in d["precedence"];@constraint(m,s[i]+duration[i]<=s[j]);end
        for i in 1:n,j in i+1:n
            shared=intersect(first.(d["alternatives"][i]),first.(d["alternatives"][j]))
            for machine in shared
                ai=sum(assignments[i][k] for k in eachindex(assignments[i]) if d["alternatives"][i][k][1]==machine)
                aj=sum(assignments[j][k] for k in eachindex(assignments[j]) if d["alternatives"][j][k][1]==machine)
                z=@variable(m,binary=true)
                @constraint(m,s[i]+duration[i]<=s[j]+H*z+H*(2-ai-aj))
                @constraint(m,s[j]+duration[j]<=s[i]+H*(1-z)+H*(2-ai-aj))
            end
        end
        @objective(m,Min,makespan)
        return (;model=m,assignments,decode=()->vcat(round.(Int,value.(s)),[argmax(value.(a)) for a in assignments]))
    elseif f in (:rcpsp,:jssp)
        n=length(d["duration"]);H=d["horizon"]
        if f==:rcpsp
            n*(H+1)<=max_cells || throw(ArgumentError("Time-indexed formulation exceeds model-size cap"))
        else
            counts=Dict{Int,Int}()
            for i in 1:n;d["duration"][i]>0 && (counts[d["machine"][i]]=get(counts,d["machine"][i],0)+1);end
            sum(c*(c-1)÷2 for c in values(counts))<=max_cells || throw(ArgumentError("Disjunctive formulation exceeds model-size cap"))
        end
        @variable(m,0<=s[1:n]<=H,Int);@variable(m,0<=makespan<=H,Int)
        @constraint(m,[i=1:n],s[i]+d["duration"][i]<=makespan)
        for(i,j)in d["precedence"];@constraint(m,s[i]+d["duration"][i]<=s[j]);end
        if f==:jssp
            pairs=[(i,j) for i in 1:n for j in i+1:n if d["machine"][i]==d["machine"][j] && d["duration"][i]>0 && d["duration"][j]>0]
            length(pairs)<=max_cells || throw(ArgumentError("Disjunctive formulation exceeds model-size cap"))
            for(i,j)in pairs
                z=@variable(m,binary=true)
                @constraint(m,s[i]+d["duration"][i]<=s[j]+H*z)
                @constraint(m,s[j]+d["duration"][j]<=s[i]+H*(1-z))
            end
        else
            n*(H+1)<=max_cells || throw(ArgumentError("Time-indexed formulation exceeds model-size cap"))
            @variable(m,a[1:n,0:H],Bin)
            @constraint(m,[i=1:n],sum(a[i,t] for t in 0:H)==1)
            @constraint(m,[i=1:n],s[i]==sum(t*a[i,t] for t in 0:H))
            for t in 0:H-1,r in axes(d["resource_use"],2)
                @constraint(m,sum(d["resource_use"][i,r]*a[i,u] for i in 1:n for u in max(0,t-d["duration"][i]+1):t)<=d["capacity"][r])
            end
        end
        @objective(m,Min,makespan);return (;model=m,decode=()->round.(Int,value.(s)))
    elseif f==:aircraft_landing
        n=length(ds);n*n<=max_cells || throw(ArgumentError("Aircraft disjunctions exceed model-size cap"))
        @variable(m,d["earliest"][i]<=t[i=1:n]<=d["latest"][i],Int)
        @variable(m,0<=early[i=1:n]<=max(0,d["target"][i]-d["earliest"][i]),Int)
        @variable(m,0<=late[i=1:n]<=max(0,d["latest"][i]-d["target"][i]),Int)
        @constraint(m,[i=1:n],early[i]>=d["target"][i]-t[i]);@constraint(m,[i=1:n],late[i]>=t[i]-d["target"][i])
        for i in 1:n,j in i+1:n
            z=@variable(m,binary=true)
            Mij=max(0,d["latest"][i]+d["separation"][i,j]-d["earliest"][j])
            Mji=max(0,d["latest"][j]+d["separation"][j,i]-d["earliest"][i])
            @constraint(m,t[i]+d["separation"][i,j]<=t[j]+Mij*z)
            @constraint(m,t[j]+d["separation"][j,i]<=t[i]+Mji*(1-z))
        end
        @objective(m,Min,sum(d["early_cost"][i]*early[i]+d["late_cost"][i]*late[i] for i in 1:n))
        return (;model=m,decode=()->round.(Int,value.(t)))
    end
    throw(ArgumentError("No qualified linear comparator formulation for $f"))
end
function solve_mip(p,factory;seconds=1.,threads=1,max_cells=250_000)
    prepared=mip_model(p;max_cells);set_optimizer(prepared.model,factory);set_silent(prepared.model)
    set_time_limit_sec(prepared.model,seconds);set_attribute(prepared.model,MOI.NumberOfThreads(),threads)
    optimize!(prepared.model)
    values=has_values(prepared.model) ? prepared.decode() : Int[]
    isempty(values) || validate(p,values).valid || error("MIP incumbent fails original validator")
    (;values,status=termination_status(prepared.model),bound=objective_bound(prepared.model))
end

struct MIPResolver <: LS.AbstractMetaVariableResolver
    max_cells::Int
    mode::String
    lp_solver::String
    mip_lp_solver::String
    radius::Int
    warm_start::Bool
end
MIPResolver(max_cells=250_000;mode="mip",lp_solver="simplex",mip_lp_solver="choose",radius=4,warm_start=false)=
    MIPResolver(max_cells,mode,lp_solver,mip_lp_solver,radius,warm_start)
function LS.resolve_meta_variable(resolver::MIPResolver,request::LS.MetaVariableRequest)
    started=time_ns();p=request.snapshot.p;current=request.snapshot.values;ids=Set(LS.scope(request.variable))
    remaining()=max(0.,Float64(request.budget)-(time_ns()-started)/1e9)
    trace=Dict{String,Any}("mode"=>resolver.mode,"warm_start"=>resolver.warm_start)
    finish(move=nothing)=(;move,trace,elapsed=(time_ns()-started)/1e9)
    remaining()>0 || return finish()
    # Bin/station symmetry is valid for a free model, but not after fixing original labels.
    build_started=time_ns()
    built=mip_model(p;symmetry=false,max_cells=resolver.max_cells);m=built.model;n=length(current)
    trace["build_seconds"]=(time_ns()-build_started)/1e9
    assignment=Dict{VariableRef,Float64}()
    if p.family in (:bpp,:bppc,:vbp,:salbp)
        a=m[:a]
        for i in 1:n,b in axes(a,2);assignment[a[i,b]]=Float64(current[i]==b);end
        for b in eachindex(m[:used]);assignment[m[:used][b]]=Float64(b in current);end
        for i in 1:n;i in ids || fix(a[i,current[i]],1;force=true);end
    elseif p.family==:fjsp
        tasks=n÷2
        for i in 1:tasks
            assignment[m[:s][i]]=Float64(current[i])
            i in ids || fix(m[:s][i],current[i];force=true)
            for k in eachindex(built.assignments[i])
                v=built.assignments[i][k];assignment[v]=Float64(current[tasks+i]==k)
                tasks+i in ids || fix(v,assignment[v];force=true)
            end
        end
    else
        starts=p.family==:aircraft_landing ? m[:t] : m[:s]
        for i in 1:n;assignment[starts[i]]=Float64(current[i]);end
        for i in 1:n;i in ids || fix(starts[i],current[i];force=true);end
    end
    remaining()>0 || return finish()
    if resolver.warm_start || resolver.mode!="mip" || resolver.mip_lp_solver!="choose"
        ROFragments.optimize_fragment!(m;remaining,assignment,mode=resolver.mode,lp_solver=resolver.lp_solver,
            mip_lp_solver=resolver.mip_lp_solver,radius=resolver.radius,trace) || return finish()
    else
        set_optimizer(m,HiGHS.Optimizer);set_silent(m);set_attribute(m,MOI.NumberOfThreads(),1);set_time_limit_sec(m,remaining())
        optimize!(m);has_values(m) || return finish()
    end
    candidate=built.decode();validate(p,candidate).valid || error("RO fragment failed original validator")
    all(i->i in ids || candidate[i]==current[i],eachindex(current)) || error("RO fragment changed a fixed parent decision")
    objective_value=ReproductionScoring.objective_value
    validate(p,current).valid && objective_value(p,candidate)>=objective_value(p,current) && return finish()
    remaining()>0 || return finish()
    LS.MetaMove(request.variable,candidate[LS.scope(request.variable)];provenance=(source=:highs_integer_fragment,)) |> finish
end
function solve_ghost(p;seconds=1.,seed=41,kind=:direct)
    # GHOST is used exclusively through its Julia JuMP/MOI wrapper.
    ghost=Base.require(Base.PkgId(Base.UUID("11b06263-fdad-4e56-a327-8fd38a91e0b8"),"GHOST"))
    Base.invokelatest(_ghost,ghost,p;seconds,seed,kind)
end
function _ghost(ghost,p;seconds,seed,kind)
    b=prepare_backend(kind);ds=domains(p);m=direct_model(ghost.Optimizer())
    @variable(m,first(ds[i])<=x[i=1:length(ds)]<=last(ds[i]),Int)
    @constraint(m,x in ghost.Error(v->error_value(b,p,v)))
    ghost.set_callback_objective(m,MOI.MIN_SENSE,x,v->ReproductionScoring.objective_value(p,v))
    set_silent(m);set_time_limit_sec(m,seconds);set_attribute(m,MOI.NumberOfThreads(),1)
    for(i,v)in enumerate(initial(p));set_start_value(x[i],v);end
    optimize!(m)
    values=has_values(m) ? round.(Int,value.(x)) : Int[]
    isempty(values) || validate(p,values).valid || error("GHOST incumbent fails original validator")
    (;values,status=termination_status(m),seed_policy="GHOST wrapper does not expose a seed setter; requested seed recorded separately",requested_seed=seed)
end
end
