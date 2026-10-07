module ReproductionSolvers
using ..ReproductionProblems, ..ReproductionScoring
using JuMP,Random
import CBLS, LocalSearchSolvers as LS, MathOptInterface as MOI, MetaStrategist as MS, HiGHS
include("../../LiLim/src/SearchPolicies.jl")
include("../../LiLim/src/PlatformResources.jl")
export prepare_cbls,search!,portfolio,mip_model,solve_mip,solve_ghost,POLICIES
const POLICIES=sort!(collect(keys(SearchPolicies.CONFIG["profiles"])))

function prepare_cbls(p;kind=:direct,policy="greedy_guided",seed=41,hybrid=false)
    hybrid && !(p.family in (:bpp,:bppc,:vbp,:salbp,:rcpsp,:jssp,:fjsp,:aircraft_landing)) && throw(ArgumentError("No qualified MIP repair for $(p.family)"))
    Random.seed!(seed)
    b=prepare_backend(kind);opt=CBLS.Optimizer();model=direct_model(opt);ds=domains(p);n=length(ds)
    @variable(model,first(ds[i])<=x[i=1:n]<=last(ds[i]),Int)
    err=(v;X=nothing)->error_value(b,p,v)
    @constraint(model,x in CBLS.Error(err))
    obj=v->ReproductionScoring.objective_value(p,v)
    @objective(model,Min,CBLS.ScalarFunction(obj,x))
    material=SearchPolicies.materialize(opt.backend_model,policy)
    options=LS.Options(dynamic=false,process_threads_map=Dict(1=>1),print_level=:silent,
        log_mode=:silent,log_to_file=false,progress_mode=:none,use_progress_meter=false)
    solver=LS.solver(opt.backend_model;options,strategies=material.strategy)
    # ICN decoders were generated after this function's world age. Enter once before the hot loop.
    Base.invokelatest(LS._init!,solver)
    start=initial(p)
    for i in eachindex(start);LS._value!(solver,i,start[i]);end
    Base.invokelatest(LS._compute!,solver);SearchPolicies.synchronize!(solver)
    (;p,model,solver,backend=b,policy=material.description,seed,start,hybrid)
end

function search!(lane;seconds=1.,max_steps=typemax(Int))
    seconds>0 && isfinite(seconds) || throw(ArgumentError("Positive finite solve budget"))
    start=time_ns();cpu=PlatformResources.cpu_seconds(3);steps=0;infeasible=0;tabu_peak=0;repairs=0;repair_seconds=0.
    gc_start=Base.gc_num().total_time
    incumbent=validate(lane.p,lane.start).valid ? copy(lane.start) : nothing
    trajectory=Dict{String,Any}[]
    if incumbent!==nothing
        push!(trajectory,Dict("seconds"=>0.,"values"=>copy(incumbent),"objective"=>collect(validate(lane.p,incumbent).objective)))
    end
    function consider(candidate)
        (time_ns()-start)/1e9<=seconds || return
        checked=validate(lane.p,candidate)
        if checked.valid && (incumbent===nothing || checked.objective<validate(lane.p,incumbent).objective)
            incumbent=Int.(candidate)
            push!(trajectory,Dict("seconds"=>(time_ns()-start)/1e9,"values"=>copy(incumbent),"objective"=>collect(checked.objective)))
        end
    end
    while steps<max_steps && (time_ns()-start)/1e9<seconds
        if lane.hybrid && steps%32==0 && repair_seconds<.25seconds
            snapshot=(p=lane.p,values=Int.(collect(LS.get_values(lane.solver))))
            ids=sort!(randperm(length(snapshot.values))[1:min(16,length(snapshot.values))])
            group=LS.MetaVariable(:integer_fragment,ids)
            budget=min(.5,max(0.,seconds-(time_ns()-start)/1e9),.25seconds-repair_seconds)
            outcome=LS.resolve_meta_variable(MIPResolver(),LS.MetaVariableRequest(group,snapshot,budget,Random.default_rng()))
            repair_seconds+=outcome.elapsed
            if outcome.move!==nothing && (time_ns()-start)/1e9<seconds
                LS._commit!(lane.solver,outcome.move);LS._compute!(lane.solver);SearchPolicies.synchronize!(lane.solver);repairs+=1
                consider(collect(LS.get_values(lane.solver)))
            end
        end
        (time_ns()-start)/1e9<seconds || break
        LS._step!(lane.solver);steps+=1;tabu_peak=max(tabu_peak,LS.length_tabu(lane.solver))
        LS.get_error(lane.solver)>0 && (infeasible+=1)
        consider(collect(LS.best_values(lane.solver)))
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
function portfolio(p;workers=[(;kind=:icn_fused,policy="late_400")],seconds=1.,seed=41,max_steps=typemax(Int))
    length(workers)<=Threads.nthreads() || throw(ArgumentError("Start Julia with at least one thread per lane"))
    lanes=Tuple(prepare_cbls(p;w...,seed=seed+i-1) for (i,w) in enumerate(workers))
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
function mip_model(p;max_cells=250_000,symmetry=true)
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
        return (;model=m,decode=()->vcat(round.(Int,value.(s)),[argmax(value.(a)) for a in assignments]))
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

struct MIPResolver <: LS.AbstractMetaVariableResolver end
function LS.resolve_meta_variable(::MIPResolver,request::LS.MetaVariableRequest)
    started=time_ns();p=request.snapshot.p;current=request.snapshot.values;ids=Set(LS.scope(request.variable))
    remaining()=max(0.,Float64(request.budget)-(time_ns()-started)/1e9)
    finish(move=nothing)=(;move,elapsed=(time_ns()-started)/1e9)
    remaining()>0 || return finish()
    # Bin/station symmetry is valid for a free model, but not after fixing original labels.
    built=mip_model(p;symmetry=false);m=built.model;n=length(current)
    if p.family in (:bpp,:bppc,:vbp,:salbp)
        a=m[:a]
        for i in 1:n;i in ids || fix(a[i,current[i]],1;force=true);end
    elseif p.family==:fjsp
        # The alternatives are model auxiliaries; currently the whole FJSP is repaired.
        # Do not advertise a partial move when machine choices cannot be fixed independently.
        ids==Set(eachindex(current)) || return finish()
    else
        starts=p.family==:aircraft_landing ? m[:t] : m[:s]
        for i in 1:n;i in ids || fix(starts[i],current[i];force=true);end
    end
    remaining()>0 || return finish()
    set_optimizer(m,HiGHS.Optimizer);set_silent(m);set_attribute(m,MOI.NumberOfThreads(),1);set_time_limit_sec(m,remaining())
    optimize!(m);has_values(m) || return finish()
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
