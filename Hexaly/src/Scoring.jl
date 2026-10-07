module ReproductionScoring
using ..ReproductionProblems
using TOML,SHA
import CompositionalNetworks as CN
export Backend,prepare_backend,error_value,objective_value,residuals!

mutable struct Backend{F}
    kind::Symbol
    decoder::F
    residuals::Vector{Float64}
    input::Vector{Float64}
    calls::Int
    evaluations::Int
    bank_sha256::String
end
function prepare_backend(kind;bank=joinpath(@__DIR__,"../../LiLim/resources/icn-pdptw-witnesses.toml"))
    kind in (:naive,:direct,:icn,:icn_fused) || throw(ArgumentError("Unknown error backend"))
    decoder=nothing;hash=""
    if kind in (:icn,:icn_fused)
        witness=TOML.parsefile(bank)["witnesses"][4]
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
        decoder=CN.composition(network);hash=bytes2hex(sha256(read(bank)))
    end
    Backend(kind,decoder,Float64[],[0.],0,0,hash)
end

"Lane-owned error terms; independent original validator decides which solutions may be exported."
function residuals!(terms,p::Problem,values;atol=p.family==:maintenance ? 1e-5 : 1e-8)
    empty!(terms);ds=domains(p)
    if length(values)!=length(ds) || !all(i->values[i] isa Real && isfinite(values[i]) && isinteger(values[i]) && values[i] in ds[i],eachindex(ds))
        push!(terms,1.);return terms
    end
    x=Int.(values);d=p.data;f=p.family
    add(v)=push!(terms,Float64(max(0,v)))
    perm(v)=add(length(v)-length(unique(v)))
    f in (:tsp,:qap,:car_sequencing) && perm(x)
    if f in (:cvrp,:cvrptw,:top)
        n=length(x)÷2;order=view(x,1:n);labels=view(x,n+1:2n);perm(order)
        for r in 1:d["vehicles"]
            previous=1;load=0.;clock=f==:cvrptw ? d["earliest"][1] : 0.;travel=0.;used=false
            for i in order
                labels[i]==r || continue
                used=true;j=i+1;distance=d["distance"][previous,j];travel+=distance
                f!=:top && (load+=d["demand"][j])
                if f==:cvrptw
                    clock=max(d["earliest"][j],clock+d["service"][previous]+distance)
                    add(clock-d["latest"][j]-atol)
                end
                previous=j
            end
            used || continue
            travel+=d["distance"][previous,f==:top ? n+2 : 1]
            if f==:top;add(travel-d["max_distance"]-atol)
            else;add(load-d["capacity"]-atol);end
            f==:cvrptw && add(clock+d["service"][previous]+d["distance"][previous,1]-d["latest"][1]-atol)
        end
    elseif f in (:bpp,:bppc,:vbp,:salbp)
        for label in unique(x)
            if f==:salbp
                add(sum(d["duration"][i] for i in eachindex(x) if x[i]==label)-d["cycle"])
            else
                for r in axes(d["weights"],2)
                    add(sum(d["weights"][i,r] for i in eachindex(x) if x[i]==label)-d["capacity"][r]-atol)
                end
            end
        end
        if f==:bppc;for(a,b)in d["conflicts"];add(x[a]==x[b]);end
        elseif f==:salbp;for(a,b)in d["precedence"];add(x[a]-x[b]);end;end
    elseif f==:mssc
        get(d,"require_nonempty",false) && add(d["clusters"]-length(unique(x)))
    elseif f in (:rcpsp,:jssp,:fjsp)
        n=length(d["duration"]);s=view(x,1:n)
        duration=f==:fjsp ? [d["alternatives"][i][x[n+i]][2] for i in 1:n] : d["duration"]
        for i in 1:n;add(s[i]+duration[i]-d["horizon"]);end
        for(a,b)in d["precedence"];add(s[a]+duration[a]-s[b]);end
        if f==:rcpsp
            events=sort!(unique(vcat(s,s.+duration)))
            for t in events,r in axes(d["resource_use"],2)
                add(sum((d["resource_use"][i,r] for i in 1:n if s[i]<=t<s[i]+duration[i]);init=0.)-d["capacity"][r])
            end
        else
            machine=f==:fjsp ? [d["alternatives"][i][x[n+i]][1] for i in 1:n] : d["machine"]
            groups=Dict{Int,Vector{Int}}()
            for i in 1:n;duration[i]>0 && push!(get!(groups,machine[i],Int[]),i);end
            for tasks in Base.values(groups)
                sort!(tasks;by=i->s[i]);finish=-1
                for i in tasks;add(finish-s[i]);finish=max(finish,s[i]+duration[i]);end
            end
        end
    elseif f==:aircraft_landing
        for i in eachindex(x),j in i+1:length(x)
            add(min(x[i]+d["separation"][i,j]-x[j],x[j]+d["separation"][j,i]-x[i]))
        end
    elseif f==:car_sequencing
        run=0;previous=-1
        for i in x
            color=d["colors"][i];run=color==previous ? run+1 : 1;add(run-d["max_paint_batch"]);previous=color
        end
    elseif f==:maintenance
        H=d["horizon"];R=length(d["capacity_upper"][1]);used=zeros(H,R)
        for i in eachindex(x)
            s=x[i];len=d["duration"][i][s];add(s+len-1-H)
            for t in s:min(H,s+len-1);used[t,:].+=d["resource_use_by_start"][i][s][t-s+1];end
        end
        for t in 1:H,r in 1:R
            add(d["capacity_lower"][t][r]-used[t,r]-atol);add(used[t,r]-d["capacity_upper"][t][r]-atol)
        end
        for(a,b,season)in d["exclusions"]
            add(count(t->x[a]<=t<x[a]+d["duration"][a][x[a]] && x[b]<=t<x[b]+d["duration"][b][x[b]],season))
        end
    end
    terms
end
function error_value(b,p,x)
    b.evaluations+=1;residuals!(b.residuals,p,x)
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

function objective_value(p,x)
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
