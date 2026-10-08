module ReproductionScoring
using ..ReproductionProblems
using TOML,SHA
import CompositionalNetworks as CN
include("ObjectiveKernels.jl")
export Backend,prepare_backend,error_value,objective_value,residuals!,search_objective_value

mutable struct ScoreWorkspace
    problem::Problem
    domains::Vector{UnitRange{Int}}
    integers::Vector{Int}
    labels::Vector{Int}
    seen::Set{Int}
    events::Vector{Int}
    durations::Vector{Int}
    machines::Vector{Int}
    task_buffers::Vector{Vector{Int}}
    machine_groups::Dict{Int,Vector{Int}}
    machine_keys::Vector{Int}
    machine_cache::Vector{Tuple{Vector{Int},Dict{Int,Vector{Int}}}}
    machine_cache_next::Int
    resource_load::Matrix{Float64}
    tolerance::Float64
    objective_workspace::Union{Nothing,ReproductionObjectives.Workspace}
end
function ScoreWorkspace(p)
    ds=UnitRange{Int}[Int(first(r)):Int(last(r)) for r in domains(p)]
    labels=Int[];seen=Set{Int}();sizehint!(labels,length(ds));sizehint!(seen,length(ds))
    ScoreWorkspace(p,ds,zeros(Int,length(ds)),labels,seen,Int[],Int[],Int[],Vector{Int}[],
        Dict{Int,Vector{Int}}(),Int[],Tuple{Vector{Int},Dict{Int,Vector{Int}}}[],1,zeros(0,0),0.,nothing)
end
packing_terms!(terms,x,labels,weights,capacity,w::ScoreWorkspace)=
    packing_terms!(terms,x,labels,weights,capacity,w.tolerance)

mutable struct Backend{F}
    kind::Symbol
    decoder::F
    residuals::Vector{Float64}
    input::Vector{Float64}
    calls::Int
    evaluations::Int
    bank_sha256::String
    workspace::Union{Nothing,ScoreWorkspace}
end
const DECODER_LOCK=ReentrantLock()
const DECODERS=Dict{String,Function}()

"Compile each exact bank once; only its pure function is shared between owned lanes."
function bank_decoder(bank)
    bytes=read(bank);hash=bytes2hex(sha256(bytes))
    decoder=lock(DECODER_LOCK) do
        get!(DECODERS,hash) do
            witness=TOML.parse(String(bytes))["witnesses"][4]
            witness["family"]=="sum" && witness["variant"]=="scalar condition" || error("Wrong scalar witness")
            network=CN.learnable_composition((;op=(==),val=2);max_depth=1)
            available=parentindices(network.weights)[1];offset=0;parts=String[]
            for layer in network.layers
                ops=[name for (j,name) in enumerate(keys(layer.fn)) if offset+j in available]
                push!(parts,repr((layer.name,layer.mutex,ops)));offset+=length(layer.fn)
            end
            bytes2hex(sha256("ICN:"*join(parts,";")))==witness["schema_sha256"] || error("ICN schema changed")
            weights=BitVector(witness["weights"])
            CN.check_weights_validity(network,weights) && CN.apply!(network,weights) || error("Invalid ICN weights")
            CN.composition(network).f
        end
    end
    (;decoder,hash)
end
function prepare_backend(kind;bank=joinpath(@__DIR__,"../../LiLim/resources/icn-pdptw-witnesses.toml"))
    kind in (:naive,:direct,:icn,:icn_fused) || throw(ArgumentError("Unknown error backend"))
    decoder,hash=kind in (:icn,:icn_fused) ? bank_decoder(bank) : (nothing,"")
    Backend(kind,decoder,Float64[],[0.],0,0,hash,nothing)
end

function workspace!(b,p)
    if b.workspace===nothing || b.workspace.problem!==p;b.workspace=ScoreWorkspace(p);end
    b.workspace::ScoreWorkspace
end
function integer_values!(w,values)
    length(values)==length(w.domains) || return false
    for i in eachindex(w.domains)
        v=values[i]
        v isa Real && isfinite(v) && isinteger(v) && v in w.domains[i] || return false
        w.integers[i]=Int(v)
    end
    true
end
function distinct_labels!(w,values)
    empty!(w.labels);empty!(w.seen)
    for v in values
        if !(v in w.seen);push!(w.seen,v);push!(w.labels,v);end
    end
    w.labels
end
function packing_terms!(terms,x,labels,weights,capacity,atol)
    for label in labels,r in axes(weights,2)
        load=0.0
        for i in eachindex(x);x[i]==label && (load+=weights[i,r]);end
        push!(terms,max(0.,load-capacity[r]-atol))
    end
end
function station_terms!(terms,x,labels,duration,cycle)
    for label in labels
        load=0
        for i in eachindex(x);x[i]==label && (load+=duration[i]);end
        push!(terms,Float64(max(0,load-cycle)))
    end
end
function precedence_terms!(terms,x,precedence)
    for(a,b)in precedence;push!(terms,Float64(max(0,x[a]-x[b])));end
end
function aircraft_terms!(terms,x,separation)
    for i in eachindex(x),j in i+1:length(x)
        push!(terms,Float64(max(0,min(x[i]+separation[i,j]-x[j],x[j]+separation[j,i]-x[i]))))
    end
end
function routing_permutation_term!(terms,x,workspace)
    n=length(x)÷2
    push!(terms,Float64(max(0,n-length(distinct_labels!(workspace,view(x,1:n))))))
end
function routing_terms!(terms,x,vehicles,distance,demand,capacity,earliest,latest,service,
        max_distance,::Val{F},atol) where F
    n=length(x)÷2
    for r in 1:vehicles
        previous=1;load=0.;clock=F==:cvrptw ? earliest[1] : 0.;travel=0.;used=false
        for position in 1:n
            i=x[position];x[n+i]==r || continue
            used=true;j=i+1;edge=distance[previous,j];travel+=edge
            F!=:top && (load+=demand[j])
            if F==:cvrptw
                clock=max(earliest[j],clock+service[previous]+edge)
                push!(terms,Float64(max(0,clock-latest[j]-atol)))
            end
            previous=j
        end
        used || continue
        travel+=distance[previous,F==:top ? n+2 : 1]
        if F==:top
            push!(terms,Float64(max(0,travel-max_distance-atol)))
        else
            push!(terms,Float64(max(0,load-capacity-atol)))
        end
        F==:cvrptw && push!(terms,Float64(max(0,clock+service[previous]+distance[previous,1]-latest[1]-atol)))
    end
end
routing_terms!(terms,x,vehicles,distance,demand,capacity,earliest,latest,service,max_distance,f::Val{F},w::ScoreWorkspace) where F =
    routing_terms!(terms,x,vehicles,distance,demand,capacity,earliest,latest,service,max_distance,f,w.tolerance)

function schedule_events!(events,starts,duration::AbstractVector{Int})
    n=length(duration);resize!(events,2n)
    for i in 1:n;events[i]=starts[i];events[n+i]=starts[i]+duration[i];end
    sort!(events;alg=QuickSort)
    count=0
    for i in eachindex(events)
        value=events[i]
        if count==0 || value!=events[count];count+=1;events[count]=value;end
    end
    resize!(events,count)
end
# Wider or custom integer durations retain the original promoted event arithmetic.
schedule_events!(events,starts,duration)=sort!(unique(vcat(starts,starts.+duration)))

function renewable_terms!(terms,starts,duration,precedence,horizon,use,capacity,events)
    for i in eachindex(duration);push!(terms,Float64(max(0,starts[i]+duration[i]-horizon)));end
    for(a,b)in precedence;push!(terms,Float64(max(0,starts[a]+duration[a]-starts[b])));end
    for t in events,r in axes(use,2)
        load=sum((use[i,r] for i in eachindex(duration) if starts[i]<=t<starts[i]+duration[i]);init=0.)
        push!(terms,Float64(max(0,load-capacity[r])))
    end
end

function machine_map!(workspace,keys)
    for (order,groups) in workspace.machine_cache
        order==keys && return groups
    end
    groups=Dict{Int,Vector{Int}}();buffers=workspace.task_buffers
    for (i,key) in enumerate(keys)
        i>length(buffers) && push!(buffers,Int[])
        groups[key]=buffers[i]
    end
    entry=(copy(keys),groups)
    # A bounded cache covers recurring assignment patterns. Every map has the
    # original fresh-map layout, and all borrowed task vectors are private.
    if length(workspace.machine_cache)<8
        push!(workspace.machine_cache,entry)
    else
        workspace.machine_cache[workspace.machine_cache_next]=entry
        workspace.machine_cache_next=mod1(workspace.machine_cache_next+1,8)
    end
    groups
end
function machine_terms!(terms,starts,duration,machine,precedence,horizon,workspace)
    for i in eachindex(duration);push!(terms,Float64(max(0,starts[i]+duration[i]-horizon)));end
    for(a,b)in precedence;push!(terms,Float64(max(0,starts[a]+duration[a]-starts[b])));end
    # Reuse the map only when its original insertion sequence is unchanged.
    # Rebuilding after a key change preserves the historical Dict term order.
    keys=workspace.labels;seen=workspace.seen;empty!(keys);empty!(seen)
    for i in eachindex(duration)
        duration[i]>0 || continue
        key=Int(machine[i])
        if !(key in seen);push!(seen,key);push!(keys,key);end
    end
    if keys!=workspace.machine_keys
        workspace.machine_groups=machine_map!(workspace,keys)
        empty!(workspace.machine_keys);append!(workspace.machine_keys,keys)
    end
    groups=workspace.machine_groups
    for tasks in Base.values(groups);empty!(tasks);end
    for i in eachindex(duration)
        duration[i]>0 && push!(groups[Int(machine[i])],i)
    end
    for tasks in Base.values(groups)
        # Original insertion order is increasing job index; this tie breaker
        # preserves stable sorting while allowing allocation-free QuickSort.
        sort!(tasks;by=i->(starts[i],i),alg=QuickSort);finish=-1
        for i in tasks
            push!(terms,Float64(max(0,finish-starts[i])))
            finish=max(finish,starts[i]+duration[i])
        end
    end
end

function flexible_assignments!(workspace,x,alternatives::Vector{Vector{Vector{Int}}})
    n=length(alternatives);resize!(workspace.durations,n);resize!(workspace.machines,n)
    for i in 1:n
        choice=alternatives[i][x[n+i]]
        workspace.machines[i]=choice[1];workspace.durations[i]=choice[2]
    end
    workspace.durations,workspace.machines
end
flexible_assignments!(workspace,x,alternatives)=
    ([alternatives[i][x[length(alternatives)+i]][2] for i in eachindex(alternatives)],
     [alternatives[i][x[length(alternatives)+i]][1] for i in eachindex(alternatives)])
function flexible_machine_terms!(terms,x,alternatives,precedence,horizon,workspace)
    duration,machine=flexible_assignments!(workspace,x,alternatives)
    machine_terms!(terms,x,duration,machine,precedence,horizon,workspace)
end

function maintenance_exclusion!(terms,x,duration,a,b,season)
    overlap=count(t->x[a]<=t<x[a]+duration[a][x[a]] && x[b]<=t<x[b]+duration[b][x[b]],season)
    push!(terms,Float64(max(0,overlap)))
end
function maintenance_terms!(terms,x,duration,horizon,use,lower,upper,exclusions,workspace,atol)
    resources=length(upper[1])
    if size(workspace.resource_load)!=(horizon,resources)
        workspace.resource_load=zeros(horizon,resources)
    end
    used=workspace.resource_load;fill!(used,0.)
    for i in eachindex(x)
        start=x[i];len=duration[i][start]
        push!(terms,Float64(max(0,start+len-1-horizon)))
        for t in start:min(horizon,start+len-1)
            row=use[i][start][t-start+1]
            for r in 1:resources;used[t,r]+=row[r];end
        end
    end
    for t in 1:horizon,r in 1:resources
        push!(terms,Float64(max(0,lower[t][r]-used[t,r]-atol)))
        push!(terms,Float64(max(0,used[t,r]-upper[t][r]-atol)))
    end
    for(a,b,season)in exclusions
        maintenance_exclusion!(terms,x,duration,a,b,season)
    end
end
maintenance_terms!(terms,x,duration,horizon,use,lower,upper,exclusions,w::ScoreWorkspace)=
    maintenance_terms!(terms,x,duration,horizon,use,lower,upper,exclusions,w,w.tolerance)

"Lane-owned error terms; independent original validator decides which solutions may be exported."
function residuals!(terms,p::Problem,values;atol=p.family==:maintenance ? 1e-5 : 1e-8,workspace=ScoreWorkspace(p))
    empty!(terms)
    if !integer_values!(workspace,values)
        push!(terms,1.);return terms
    end
    x=workspace.integers;d=p.data;f=p.family
    atol isa Float64 && (workspace.tolerance=atol)
    add(v)=push!(terms,Float64(max(0,v)))
    perm(v)=add(length(v)-length(distinct_labels!(workspace,v)))
    f in (:tsp,:qap,:car_sequencing) && perm(x)
    if f in (:cvrp,:cvrptw,:top)
        routing_permutation_term!(terms,x,workspace)
        tolerance=atol isa Float64 ? workspace : atol
        if f==:cvrptw
            routing_terms!(terms,x,d["vehicles"],d["distance"],d["demand"],d["capacity"],
                d["earliest"],d["latest"],d["service"],nothing,Val(:cvrptw),tolerance)
        elseif f==:cvrp
            routing_terms!(terms,x,d["vehicles"],d["distance"],d["demand"],d["capacity"],
                nothing,nothing,nothing,nothing,Val(:cvrp),tolerance)
        else
            routing_terms!(terms,x,d["vehicles"],d["distance"],nothing,nothing,
                nothing,nothing,nothing,d["max_distance"],Val(:top),tolerance)
        end
    elseif f in (:bpp,:bppc,:vbp,:salbp)
        labels=distinct_labels!(workspace,x)
        if f==:salbp
            station_terms!(terms,x,labels,d["duration"],d["cycle"])
        else
            packing_terms!(terms,x,labels,d["weights"],d["capacity"],atol isa Float64 ? workspace : atol)
        end
        if f==:bppc;for(a,b)in d["conflicts"];add(x[a]==x[b]);end
        elseif f==:salbp;precedence_terms!(terms,x,d["precedence"]);end
    elseif f==:mssc
        get(d,"require_nonempty",false) && add(d["clusters"]-length(distinct_labels!(workspace,x)))
    elseif f in (:rcpsp,:jssp,:fjsp)
        # Typed helpers limit their traversal to the job durations. FJSP's
        # trailing assignment variables never enter scheduling arithmetic.
        starts=x
        if f==:rcpsp
            duration=d["duration"];events=schedule_events!(workspace.events,starts,duration)
            renewable_terms!(terms,starts,duration,d["precedence"],d["horizon"],d["resource_use"],d["capacity"],events)
        elseif f==:fjsp
            flexible_machine_terms!(terms,x,d["alternatives"],d["precedence"],d["horizon"],workspace)
        else
            machine_terms!(terms,starts,d["duration"],d["machine"],d["precedence"],d["horizon"],workspace)
        end
    elseif f==:aircraft_landing
        aircraft_terms!(terms,x,d["separation"])
    elseif f==:car_sequencing
        run=0;previous=-1
        for i in x
            color=d["colors"][i];run=color==previous ? run+1 : 1;add(run-d["max_paint_batch"]);previous=color
        end
    elseif f==:maintenance
        if atol isa Float64
            maintenance_terms!(terms,x,d["duration"],d["horizon"],d["resource_use_by_start"],
                d["capacity_lower"],d["capacity_upper"],d["exclusions"],workspace)
        else
            maintenance_terms!(terms,x,d["duration"],d["horizon"],d["resource_use_by_start"],
                d["capacity_lower"],d["capacity_upper"],d["exclusions"],workspace,atol)
        end
    end
    terms
end
function error_value(b,p,x)::Float64
    b.evaluations+=1;residuals!(b.residuals,p,x;workspace=workspace!(b,p))
    if b.kind==:naive;return Float64(count(>(0),b.residuals))
    elseif b.kind==:direct;return sum(b.residuals)
    elseif b.kind==:icn_fused
        b.input[1]=sum(b.residuals);b.calls+=1;return b.decoder(b.input;op=(==),val=0)
    end
    total=0.
    for term in b.residuals
        b.input[1]=term;b.calls+=1;total+=b.decoder(b.input;op=(==),val=0)
    end
    total
end

"Search-only objective kernels; the independent original validator still audits every incumbent."
function search_objective_value(b,p,values)::Float64
    if p.family in (:tsp,:qap,:cvrp,:cvrptw,:top,:mssc,:car_sequencing,:maintenance)
        w=workspace!(b,p)
        objective_domains_current(w,p) && integer_values!(w,values) || return objective_value(p,values)
        d=p.data;x=w.integers;f=p.family;state=objective_workspace!(w)
        stored=if f==:tsp
            ReproductionObjectives.tsp!(state,x,d["distance"])
        elseif f==:qap
            ReproductionObjectives.qap!(state,x,d["flow"],d["distance"])
        elseif f in (:cvrp,:cvrptw,:top)
            ReproductionObjectives.route_value!(state,f,x,d["distance"],d["vehicles"],get(d,"prize",nothing))
        elseif f==:mssc
            ReproductionObjectives.cluster_value!(state,x,d["coordinates"],d["clusters"])
        elseif f==:car_sequencing
            ReproductionObjectives.cars!(state,x,d["history"],d["colors"],d["options"],d["window"],d["limit"],d["priority"],d["objective_order"])
        else
            ReproductionObjectives.maintenance_value!(state,x,d["duration"],d["risk_by_start"],
                d["scenario_count"],d["horizon"],d["quantile"],d["alpha"])
        end
        return stored ? state.value : objective_value(p,values)
    end
    p.family in (:bpp,:bppc,:vbp,:salbp,:rcpsp,:jssp,:fjsp,:aircraft_landing) || return objective_value(p,values)
    w=workspace!(b,p);integer_values!(w,values) || return Inf
    x=w.integers;d=p.data
    if p.family in (:bpp,:bppc,:vbp,:salbp)
        return Float64(length(distinct_labels!(w,x)))
    elseif p.family==:fjsp
        return Float64(flexible_makespan(x,d["alternatives"]))
    elseif p.family in (:rcpsp,:jssp)
        return Float64(makespan(x,d["duration"]))
    else
        return aircraft_cost(x,d["target"],d["early_cost"],d["late_cost"])
    end
end

function objective_workspace!(workspace)
    workspace.objective_workspace===nothing && (workspace.objective_workspace=ReproductionObjectives.Workspace())
    workspace.objective_workspace::ReproductionObjectives.Workspace
end

maintenance_domains_current(domains,latest)=length(domains)==length(latest) &&
    all(i->domains[i]==(1:latest[i]),eachindex(latest))

function matrix_domains_current(domains,matrix)
    n=size(matrix,1)
    n>0 && length(domains)==n && domains[1]==(1:n)
end
function route_domains_current(domains,matrix,vehicles,top)
    n=size(matrix,1)-(top ? 2 : 1)
    n>0 && length(domains)==2n && domains[1]==(1:n) && domains[n+1]==((top ? 0 : 1):vehicles)
end
function cluster_domains_current(domains,coordinates,clusters)
    n=size(coordinates,1)
    n>0 && length(domains)==n && domains[1]==(1:clusters)
end
count_domains_current(domains,n)=n>0 && length(domains)==n && domains[1]==(1:n)

"Data edits that change domains retain the original validator's dimension/domain behavior."
function objective_domains_current(workspace,p)
    f=p.family;d=p.data;ds=workspace.domains
    if f in (:tsp,:qap)
        return matrix_domains_current(ds,d["distance"])
    elseif f in (:cvrp,:cvrptw,:top)
        return route_domains_current(ds,d["distance"],d["vehicles"],f==:top)
    elseif f==:mssc
        return cluster_domains_current(ds,d["coordinates"],d["clusters"])
    elseif f==:car_sequencing
        return count_domains_current(ds,d["today_count"])
    else
        return maintenance_domains_current(ds,d["latest_start"])
    end
end
function makespan(x,duration)
    result=0
    for i in eachindex(duration);result=max(result,x[i]+duration[i]);end
    result
end
function flexible_makespan(x,alternatives)
    n=length(alternatives);result=0
    for i in 1:n;result=max(result,x[i]+alternatives[i][x[n+i]][2]);end
    result
end
function aircraft_cost(x,target,early,late)
    total=0.0
    @inbounds @simd for i in eachindex(x)
        total+=early[i]*max(0,target[i]-x[i])+late[i]*max(0,x[i]-target[i])
    end
    total
end

function objective_value(p,x)::Float64
    # Return the search objective even for infeasible assignments. Feasibility is handled separately.
    q=validate(p,x).objective
    if p.family==:cvrptw
        D=p.data["distance"];n=size(D,1)-1
        maxedge=if hasproperty(D,:coordinates)
            coords=D.coordinates;sqrt(sum((maximum(coords[:,j])-minimum(coords[:,j]))^2 for j in axes(coords,2)))
        else;maximum(D);end
        # Any solution has at most 2n edges. One vehicle always dominates the distance component.
        return Float64(q[1]*(2n*maxedge+1)+q[2])
    elseif p.family==:car_sequencing
        N=length(p.data["colors"]);B=1+N*sum(p.data["window"])
        value=0.
        for term in q;value=value*B+term;end
        value<=2.0^53 || error("Lexicographic encoding exceeds exact Float64 integer range")
        return value
    elseif p.family==:qap
        abs(q[1])<=big(2)^53 || error("QAP objective exceeds exact Float64 integer range")
    end
    Float64(q[1])
end
end
