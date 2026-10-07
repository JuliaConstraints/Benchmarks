"Original semantics for normalized classical instances, independent of any search score."
module ReproductionProblems
using TOML, LinearAlgebra
export Problem, problem, validate, domains, initial, FAMILY_IDS
const FAMILY_IDS = (:tsp,:cvrp,:cvrptw,:top,:qap,:bpp,:bppc,:vbp,:mssc,
    :rcpsp,:jssp,:fjsp,:salbp,:aircraft_landing,:car_sequencing,:maintenance)
struct Problem
    id::String
    family::Symbol
    data::Dict{String,Any}
end
matrix(rows) = permutedims(reduce(hcat,rows))
function problem(family,data;id=string(family))
    family in FAMILY_IDS || throw(ArgumentError("Unsupported original semantics: $family"))
    d=Dict{String,Any}(deepcopy(data))
    for key in ("distance","flow","weights","coordinates","resource_use","separation","options")
        haskey(d,key) && !(d[key] isa AbstractMatrix) && (d[key]=matrix(d[key]))
    end
    p=Problem(String(id),family,d)
    check_data(p)
    ds=domains(p)
    !isempty(ds) && all(!isempty,ds) || throw(ArgumentError("Empty decision domain"))
    all(r->isfinite(first(r)) && isfinite(last(r)),ds) || throw(ArgumentError("Nonfinite domain"))
    # Input readers reject variants before construction; do not silently apply a different metric.
    p
end

function check_data(p)
    d=p.data;f=p.family
    positive(x)=x isa Real && isfinite(x) && x>0
    nonnegative(x)=x isa Real && isfinite(x) && x>=0
    require(c,message)=c || throw(ArgumentError(message))
    if f in (:tsp,:qap,:cvrp,:cvrptw,:top)
        D=d["distance"];n=size(D,1)
        require(n>=2 && size(D,2)==n,"Square distance matrix of order >=2 required")
        # Coordinate matrices are deliberately lazy for the 30,000-customer corpus.
        if hasproperty(D,:coordinates)
            require(all(isfinite,D.coordinates),"Nonfinite coordinates")
        else
            require(all(nonnegative,D),"Negative or nonfinite distances")
        end
        f==:qap && require(size(d["flow"])==(n,n) && all(nonnegative,d["flow"]),"Invalid QAP flow")
        if f in (:cvrp,:cvrptw,:top)
            require(d["vehicles"] isa Integer && d["vehicles"]>0,"Positive fleet required")
            if f==:top
                require(length(d["prize"])==n && all(nonnegative,d["prize"]) && positive(d["max_distance"]),"Invalid TOP data")
            else
                require(length(d["demand"])==n && all(nonnegative,d["demand"]) && positive(d["capacity"]),"Invalid capacity/demand")
            end
            if f==:cvrptw
                require(all(k->length(d[k])==n,("earliest","latest","service")),"Window dimensions")
                require(all(isfinite,vcat(d["earliest"],d["latest"])) && all(nonnegative,d["service"]) && all(d["earliest"].<=d["latest"]),"Invalid windows/service")
            end
        end
    elseif f in (:bpp,:bppc,:vbp)
        W=d["weights"];require(size(W,1)>0 && size(W,2)==length(d["capacity"]),"Packing dimensions")
        require(all(nonnegative,W) && all(positive,d["capacity"]),"Invalid packing weights/capacity")
        f==:bppc && require(all(e->length(e)==2 && all(i->1<=i<=size(W,1),e) && e[1]!=e[2],d["conflicts"]),"Invalid conflict edge")
    elseif f==:mssc
        require(all(isfinite,d["coordinates"]) && size(d["coordinates"],2)>0,"Invalid MSSC points")
        require(d["clusters"] isa Integer && 1<=d["clusters"]<=size(d["coordinates"],1),"Invalid cluster count")
    elseif f in (:rcpsp,:jssp,:fjsp,:salbp)
        n=length(d["duration"]);require(n>0 && all(t->t isa Integer && t>=0,d["duration"]),"Invalid durations")
        require(all(e->length(e)==2 && all(i->1<=i<=n,e) && e[1]!=e[2],d["precedence"]),"Invalid precedence")
        # Check acyclicity without a quadratic topological scan.
        indegree=zeros(Int,n);successors=[Int[] for _ in 1:n]
        for (a,b) in d["precedence"];indegree[b]+=1;push!(successors[a],b);end
        queue=findall(iszero,indegree);position=1
        while position<=length(queue)
            a=queue[position];position+=1
            for b in successors[a];indegree[b]-=1;indegree[b]==0 && push!(queue,b);end
        end
        require(length(queue)==n,"Cyclic precedence")
        d["topological_order"]=queue
        if f==:salbp
            require(positive(d["cycle"]),"Invalid cycle time")
        else
            require(d["horizon"] isa Integer && d["horizon"]>=sum(d["duration"]),"Invalid scheduling horizon")
        end
        if f==:rcpsp
            require(size(d["resource_use"])==(n,length(d["capacity"])) && all(nonnegative,d["resource_use"]) && all(nonnegative,d["capacity"]),"Invalid renewable resources")
        elseif f==:jssp
            require(length(d["machine"])==n && all(m->m isa Integer && m>0,d["machine"]),"Invalid machines")
        elseif f==:fjsp
            require(length(d["alternatives"])==n && all(c->!isempty(c) && all(a->length(a)==2 && a[1] isa Integer && a[1]>0 && a[2] isa Integer && a[2]>=0,c),d["alternatives"]),"Invalid alternative machines")
        end
    elseif f==:aircraft_landing
        n=length(d["earliest"])
        require(all(k->length(d[k])==n,("target","latest","early_cost","late_cost")) && size(d["separation"])==(n,n),"Aircraft dimensions")
        require(all(isinteger,vcat(d["earliest"],d["target"],d["latest"])) && all(d["earliest"].<=d["latest"]) && all(nonnegative,d["separation"]) && all(nonnegative,vcat(d["early_cost"],d["late_cost"])),"Invalid aircraft windows/costs")
    elseif f==:car_sequencing
        n=d["today_count"];N=length(d["colors"]);q=size(d["options"],2)
        require(0<n<=N && size(d["options"],1)==N && all(v->v in (0,1),d["options"]),"Car dimensions/options")
        require(all(k->length(d[k])==q,("window","limit","priority")) && all(positive,d["window"]) && all(nonnegative,d["limit"]) && all(v->v in (0,1),d["priority"]),"Invalid ratio limits")
        require(all(i->n<i<=N,d["history"]) && positive(d["max_paint_batch"]) && all(i->i in 1:3,d["objective_order"]),"Invalid car prefix/objective")
    elseif f==:maintenance
        H=d["horizon"];n=length(d["latest_start"])
        require(H>0 && 0<=d["alpha"]<=1 && 0<d["quantile"]<=1,"Invalid risk aggregation")
        require(length(d["scenario_count"])==H && all(positive,d["scenario_count"]),"Invalid scenario count")
        require(length(d["capacity_lower"])==length(d["capacity_upper"])==H,"Resource periods")
        R=length(first(d["capacity_upper"]))
        require(all(t->length(d["capacity_lower"][t])==length(d["capacity_upper"][t])==R && all(isfinite,vcat(d["capacity_lower"][t],d["capacity_upper"][t])) && all(d["capacity_lower"][t].<=d["capacity_upper"][t]),1:H),"Resource bounds")
        for i in 1:n
            S=d["latest_start"][i];require(1<=S<=H && length(d["duration"][i])==S,"Intervention starts")
            for s in 1:S
                len=d["duration"][i][s];require(len>0,"Invalid intervention duration")
                require(length(d["risk_by_start"][i][s])==length(d["resource_use_by_start"][i][s])==min(len,H-s+1),"Intervention period data")
                for offset in 1:min(len,H-s+1)
                    require(length(d["risk_by_start"][i][s][offset])==d["scenario_count"][s+offset-1] && all(isfinite,d["risk_by_start"][i][s][offset]),"Risk scenarios")
                    require(length(d["resource_use_by_start"][i][s][offset])==R && all(nonnegative,d["resource_use_by_start"][i][s][offset]),"Intervention resource load")
                end
            end
        end
    end
    nothing
end

function domains(p::Problem)
    d=p.data; f=p.family
    if f in (:tsp,:qap)
        n=size(d["distance"],1); return fill(1:n,n)
    elseif f in (:cvrp,:cvrptw,:top)
        n=size(d["distance"],1)-(f==:top ? 2 : 1)
        return vcat(fill(1:n,n),fill((f==:top ? 0 : 1):d["vehicles"],n))
    elseif f in (:bpp,:bppc,:vbp)
        n=size(d["weights"],1); return fill(1:get(d,"max_bins",n),n)
    elseif f==:mssc
        return fill(1:d["clusters"],size(d["coordinates"],1))
    elseif f in (:rcpsp,:jssp,:fjsp)
        n=length(d["duration"]); starts=fill(0:d["horizon"],n)
        return f==:fjsp ? vcat(starts,[1:length(choices) for choices in d["alternatives"]]) : starts
    elseif f==:salbp
        return fill(1:length(d["duration"]),length(d["duration"]))
    elseif f==:aircraft_landing
        return [a:b for (a,b) in zip(d["earliest"],d["latest"])]
    elseif f==:car_sequencing
        n=d["today_count"]; return fill(1:n,n)
    elseif f==:maintenance
        return [1:t for t in d["latest_start"]]
    end
    error("Unimplemented family")
end

function initial(p::Problem)
    d=p.data; f=p.family
    haskey(d,"initial") && return Int.(d["initial"])
    if f in (:tsp,:qap,:car_sequencing); return collect(1:length(domains(p)))
    elseif f in (:cvrp,:cvrptw,:top)
        n=length(domains(p))÷2
        labels=f==:top ? zeros(Int,n) : collect(1:n)
        if f!=:top
            loads=zeros(Float64,d["vehicles"]); fill!(labels,1)
            for i in 1:n
                r=findfirst(x->x+d["demand"][i+1]<=d["capacity"],loads)
                r===nothing && return vcat(collect(1:n),ones(Int,n))
                labels[i]=r;loads[r]+=d["demand"][i+1]
            end
        end
        return vcat(collect(1:n),labels)
    elseif f in (:bpp,:bppc,:vbp)
        n=size(d["weights"],1);B=last(first(domains(p)));labels=zeros(Int,n)
        loads=zeros(Float64,B,size(d["weights"],2));conflicts=get(d,"conflicts",Vector{Int}[])
        for i in 1:n
            b=findfirst(1:B) do bin
                all(r->loads[bin,r]+d["weights"][i,r]<=d["capacity"][r],axes(loads,2)) &&
                    all(edge-> !(i in edge) || labels[only(filter(!=(i),edge))]!=bin,conflicts)
            end
            b===nothing && (b=1) # An infeasible start still respects every decision domain.
            labels[i]=b;loads[b,:].+=d["weights"][i,:]
        end
        return labels
    elseif f==:mssc; return [mod1(i,d["clusters"]) for i in 1:size(d["coordinates"],1)]
    elseif f==:salbp
        # Precedence labels follow a topological ordering, not the source numbering.
        n=length(d["duration"]); result=zeros(Int,n)
        for (station,task) in enumerate(d["topological_order"])
            result[task]=station
        end
        return result
    elseif f in (:rcpsp,:jssp,:fjsp)
        n=length(d["duration"]); result=zeros(Int,n);clock=0
        for task in d["topological_order"]
            result[task]=clock;clock+=d["duration"][task]
        end
        return f==:fjsp ? vcat(result,ones(Int,n)) : result
    elseif f==:aircraft_landing; return Int.(d["target"])
    else; return [first(r) for r in domains(p)]
    end
end

function validate(p::Problem,values;atol=p.family==:maintenance ? 1e-5 : 1e-8)
    ds=domains(p)
    length(values)==length(ds) || return (;valid=false,objective=(Inf,),errors=[:dimension])
    all(i->values[i] isa Real && isfinite(values[i]) && isinteger(values[i]) && values[i] in ds[i],eachindex(ds)) ||
        return (;valid=false,objective=(Inf,),errors=[:domain])
    x=Int.(values); d=p.data; f=p.family; errors=Symbol[]; objective=(Inf,)
    if f==:tsp
        sort(x)==collect(1:length(x)) || push!(errors,:permutation)
        objective=(sum(d["distance"][x[i],x[mod1(i+1,length(x))]] for i in eachindex(x)),)
    elseif f==:qap
        sort(x)==collect(1:length(x)) || push!(errors,:permutation)
        objective=(sum(BigInt(d["flow"][i,j])*d["distance"][x[i],x[j]] for i in eachindex(x),j in eachindex(x)),)
    elseif f in (:cvrp,:cvrptw,:top)
        n=length(x)÷2; order=x[1:n];labels=x[n+1:end]
        sort(order)==collect(1:n) || push!(errors,:permutation)
        traveled=0.;fleet=0;profit=0.
        for vehicle in 1:d["vehicles"]
            route=[i+1 for i in order if labels[i]==vehicle]
            isempty(route) && continue
            fleet+=1;previous=1;clock=get(d,"earliest",zeros(n+2))[1];load=0.;length_route=0.
            for node in route
                length_route+=d["distance"][previous,node]
                if f==:cvrptw
                    clock=max(d["earliest"][node],clock+d["service"][previous]+d["distance"][previous,node])
                    clock<=d["latest"][node]+atol || push!(errors,:time_window)
                end
                f!=:top && (load+=d["demand"][node])
                f==:top && (profit+=d["prize"][node])
                previous=node
            end
            finish=f==:top ? n+2 : 1
            length_route+=d["distance"][previous,finish];traveled+=length_route
            f==:top && length_route>d["max_distance"]+atol && push!(errors,:route_length)
            f!=:top && load>d["capacity"]+atol && push!(errors,:capacity)
            if f==:cvrptw
                clock+d["service"][previous]+d["distance"][previous,1]<=d["latest"][1]+atol || push!(errors,:depot_return)
            end
        end
        objective=f==:top ? (-profit,) : f==:cvrptw ? (fleet,traveled) : (traveled,)
    elseif f in (:bpp,:bppc,:vbp)
        for bin in unique(x), dim in axes(d["weights"],2)
            sum(d["weights"][i,dim] for i in eachindex(x) if x[i]==bin)<=d["capacity"][dim]+atol || push!(errors,:capacity)
        end
        if f==:bppc
            for (a,b) in d["conflicts"]; x[a]!=x[b] || push!(errors,:conflict); end
        end
        objective=(length(unique(x)),)
    elseif f==:mssc
        !get(d,"require_nonempty",false) || all(k->k in x,1:d["clusters"]) || push!(errors,:empty_cluster)
        total=0.
        for k in 1:d["clusters"]
            ids=findall(==(k),x);isempty(ids) && continue
            center=vec(sum(d["coordinates"][ids,:];dims=1))./length(ids)
            total+=sum((d["coordinates"][i,j]-center[j])^2 for i in ids,j in axes(d["coordinates"],2))
        end
        objective=(total,)
    elseif f in (:rcpsp,:jssp,:fjsp)
        n=length(d["duration"]);start=x[1:n]
        duration=f==:fjsp ? [d["alternatives"][i][x[n+i]][2] for i in 1:n] : d["duration"]
        machine=f==:fjsp ? [d["alternatives"][i][x[n+i]][1] for i in 1:n] : get(d,"machine",Int[])
        all(start.+duration .<=d["horizon"]) || push!(errors,:horizon)
        for (a,b) in d["precedence"];start[a]+duration[a]<=start[b] || push!(errors,:precedence);end
        if f==:rcpsp
            for t in sort!(unique(vcat(start,start.+duration))),r in axes(d["resource_use"],2)
                sum((d["resource_use"][i,r] for i in 1:n if start[i]<=t<start[i]+duration[i]);init=0.)<=d["capacity"][r] ||
                    push!(errors,:resource)
            end
        else
            by_machine=Dict{Int,Vector{Int}}()
            for i in 1:n
                duration[i]>0 && push!(get!(by_machine,machine[i],Int[]),i)
            end
            for tasks in Base.values(by_machine)
                sort!(tasks;by=i->start[i]);previous_end=-1
                for i in tasks
                    previous_end<=start[i] || push!(errors,:overlap)
                    previous_end=max(previous_end,start[i]+duration[i])
                end
            end
        end
        objective=(maximum(start.+duration),)
    elseif f==:salbp
        for (a,b) in d["precedence"];x[a]<=x[b] || push!(errors,:precedence);end
        for station in unique(x)
            sum(d["duration"][i] for i in eachindex(x) if x[i]==station)<=d["cycle"] || push!(errors,:cycle_time)
        end
        objective=(length(unique(x)),)
    elseif f==:aircraft_landing
        for i in eachindex(x),j in i+1:length(x)
            x[j]>=x[i]+d["separation"][i,j] || x[i]>=x[j]+d["separation"][j,i] || push!(errors,:separation)
        end
        objective=(sum(d["early_cost"][i]*max(0,d["target"][i]-x[i])+d["late_cost"][i]*max(0,x[i]-d["target"][i]) for i in eachindex(x)),)
    elseif f==:car_sequencing
        sort(x)==collect(1:length(x)) || push!(errors,:permutation)
        sequence=vcat(d["history"],x);history=length(d["history"]);high=0;low=0;changes=0;run=0;last=-1
        # The fixed prefix affects ratio windows and the first color change.
        # Paint batch constraints apply to the day's movable suffix.
        for position in history+1:length(sequence)
            car=sequence[position];color=d["colors"][car]
            run=color==last ? run+1 : 1
            run<=d["max_paint_batch"] || push!(errors,:paint_batch)
            position>1 && d["colors"][sequence[position-1]]!=color && (changes+=1)
            last=color
        end
        for j in axes(d["options"],2),start in history-d["window"][j]+2:length(sequence)
            lo=max(1,start);hi=min(length(sequence),start+d["window"][j]-1)
            violation=max(0,sum((d["options"][sequence[t],j] for t in lo:hi);init=0)-d["limit"][j])
            d["priority"][j]==1 ? (high+=violation) : (low+=violation)
        end
        scores=(high,changes,low);objective=Tuple(scores[i] for i in d["objective_order"])
    elseif f==:maintenance
        # Canonical ROADEF-2020 arrays retain time-dependent durations and scenario risks.
        horizon=d["horizon"];risk=[zeros(Float64,n) for n in d["scenario_count"]]
        used=zeros(Float64,horizon,length(d["capacity_upper"][1]))
        for i in eachindex(x)
            start=x[i];duration=d["duration"][i][start]
            start+duration-1<=horizon || push!(errors,:horizon)
            for t in start:min(horizon,start+duration-1)
                used[t,:].+=d["resource_use_by_start"][i][start][t-start+1]
                risk[t].+=d["risk_by_start"][i][start][t-start+1]
            end
        end
        for t in 1:horizon,r in axes(used,2)
            d["capacity_lower"][t][r]-atol<=used[t,r]<=d["capacity_upper"][t][r]+atol || push!(errors,:resource)
        end
        for (a,b,season) in d["exclusions"]
            any(t->x[a]<=t<x[a]+d["duration"][a][x[a]] && x[b]<=t<x[b]+d["duration"][b][x[b]],season) && push!(errors,:exclusion)
        end
        means=[sum(r)/length(r) for r in risk]
        excess=[max(0,sort(risk[t])[clamp(ceil(Int,d["quantile"]*length(risk[t])),1,length(risk[t]))]-means[t]) for t in 1:horizon]
        objective=(d["alpha"]*sum(means)/horizon+(1-d["alpha"])*sum(excess)/horizon,)
    end
    all(isfinite,objective) || push!(errors,:nonfinite_objective)
    (;valid=isempty(errors),objective,errors=unique(errors))
end
end
