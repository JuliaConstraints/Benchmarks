"Owned objective scratch; the original validator remains the export authority."
module ReproductionObjectives

const MachineNumber=Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float32,Float64}
const MachineInteger=Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64}
const EXACT_FLOAT_LIMIT=Int128(1)<<53

mutable struct Workspace
    ids::Vector{Int}
    coordinates::Matrix{Float64}
    center::Matrix{Float64}
    coordinate_cache::Vector{Matrix{Float64}}
    coordinate_cache_next::Int
    risk::Vector{Vector{Float64}}
    means::Vector{Float64}
    excess::Vector{Float64}
    sort_scratch::Vector{Float64}
    value::Float64
end
Workspace()=Workspace(Int[],zeros(0,0),zeros(0,0),Matrix{Float64}[],1,Vector{Float64}[],Float64[],Float64[],Float64[],0.)

function coordinate_buffer!(workspace,rows,dimensions)
    size(workspace.coordinates)==(rows,dimensions) && return workspace.coordinates
    for cached in workspace.coordinate_cache
        if size(cached)==(rows,dimensions);workspace.coordinates=cached;return cached;end
    end
    buffer=Matrix{Float64}(undef,rows,dimensions)
    if length(workspace.coordinate_cache)<8
        push!(workspace.coordinate_cache,buffer)
    else
        workspace.coordinate_cache[workspace.coordinate_cache_next]=buffer
        workspace.coordinate_cache_next=mod1(workspace.coordinate_cache_next+1,8)
    end
    workspace.coordinates=buffer
end

tsp(x,distance::AbstractMatrix{<:MachineNumber})=
    Float64(sum(distance[x[i],x[mod1(i+1,length(x))]] for i in eachindex(x)))
tsp(x,distance)=nothing

function route_objective(family,x,distance::AbstractMatrix{<:MachineNumber},vehicles,prize=nothing)
    n=length(x)÷2;traveled=0.;fleet=0;profit=0.
    for vehicle in 1:vehicles
        previous=1;length_route=0.;used=false
        for i in 1:n
            customer=x[i]
            x[n+customer]==vehicle || continue
            used=true;node=customer+1
            length_route+=distance[previous,node]
            family==:top && (profit+=prize[node])
            previous=node
        end
        used || continue
        fleet+=1;finish=family==:top ? n+2 : 1
        length_route+=distance[previous,finish];traveled+=length_route
    end
    family==:top && return -profit
    if family==:cvrptw
        maxedge=if hasproperty(distance,:coordinates)
            coordinates=distance.coordinates
            sqrt(sum((maximum(@view coordinates[:,j])-minimum(@view coordinates[:,j]))^2 for j in axes(coordinates,2)))
        else
            maximum(distance)
        end
        return Float64(fleet*(2n*maxedge+1)+traveled)
    end
    traveled
end
route_objective(family,x,distance,vehicles,prize=nothing)=nothing

"Checked machine arithmetic; unsupported or wide exact arithmetic uses the original path."
function qap(x,flow::AbstractMatrix{<:MachineInteger},distance::AbstractMatrix{<:MachineInteger})
    total=Int128(0)
    try
        for i in eachindex(x),j in eachindex(x)
            term=Base.Checked.checked_mul(Int128(flow[i,j]),Int128(distance[x[i],x[j]]))
            total=Base.Checked.checked_add(total,term)
        end
    catch caught
        caught isa OverflowError || rethrow()
        return nothing
    end
    -EXACT_FLOAT_LIMIT<=total<=EXACT_FLOAT_LIMIT || error("QAP objective exceeds exact Float64 integer range")
    Float64(total)
end
qap(x,flow,distance)=nothing

function clusters!(workspace,x,coordinates::AbstractMatrix{Float64},clusters)
    n,dimensions=size(coordinates)
    if size(workspace.center)!=(1,dimensions)
        workspace.center=Matrix{Float64}(undef,1,dimensions)
    end
    ids=workspace.ids;total=0.
    for cluster in 1:clusters
        empty!(ids)
        for i in eachindex(x);x[i]==cluster && push!(ids,i);end
        isempty(ids) && continue
        selected=coordinate_buffer!(workspace,length(ids),dimensions)
        for j in axes(coordinates,2),row in eachindex(ids)
            selected[row,j]=coordinates[ids[row],j]
        end
        # Match the original dense selected-row reduction and squared-error order.
        sum!(workspace.center,selected)
        for j in axes(coordinates,2);workspace.center[1,j]/=length(ids);end
        total+=sum((coordinates[i,j]-workspace.center[1,j])^2 for i in ids,j in axes(coordinates,2))
    end
    total
end
clusters!(workspace,x,coordinates,clusters)=nothing

@inline sequence_at(history,x,position)=position<=length(history) ? history[position] : x[position-length(history)]
function cars(x,history,colors,options,windows,limits,priorities,objective_order)
    prefix=length(history);last=prefix+length(x);high=0;low=0;changes=0
    for position in prefix+1:last
        if position>1 && colors[sequence_at(history,x,position-1)]!=colors[sequence_at(history,x,position)]
            changes+=1
        end
    end
    for j in axes(options,2),start in prefix-windows[j]+2:last
        lo=max(1,start);hi=min(last,start+windows[j]-1)
        violation=max(0,sum((options[sequence_at(history,x,t),j] for t in lo:hi);init=0)-limits[j])
        priorities[j]==1 ? (high+=violation) : (low+=violation)
    end
    scores=(high,changes,low);base=1+length(colors)*sum(windows);value=0.
    for i in objective_order;value=value*base+scores[i];end
    value<=2.0^53 || error("Lexicographic encoding exceeds exact Float64 integer range")
    value
end

function add_risk!(target,source)
    length(target)==length(source) || throw(DimensionMismatch("Risk scenarios"))
    @inbounds @simd for i in eachindex(target);target[i]+=source[i];end
end
function maintenance!(workspace,x,duration,risk_by_start,scenario_count,horizon,quantile,alpha)
    while length(workspace.risk)<horizon;push!(workspace.risk,Float64[]);end
    resize!(workspace.risk,horizon)
    resize!(workspace.means,horizon);resize!(workspace.excess,horizon)
    for t in 1:horizon;fill!(resize!(workspace.risk[t],scenario_count[t]),0.);end
    for i in eachindex(x)
        start=x[i];span=duration[i][start]
        for t in start:min(horizon,start+span-1)
            add_risk!(workspace.risk[t],risk_by_start[i][start][t-start+1])
        end
    end
    for t in 1:horizon
        risk=workspace.risk[t];workspace.means[t]=sum(risk)/length(risk)
    end
    for t in 1:horizon
        risk=workspace.risk[t]
        index=clamp(ceil(Int,quantile*length(risk)),1,length(risk))
        # Only the selected quantile is consumed. Partial sorting preserves the
        # original order statistic and reuses scratch without radix histograms.
        selected=partialsort!(risk,index;scratch=workspace.sort_scratch)
        workspace.excess[t]=max(0,selected-workspace.means[t])
    end
    alpha*sum(workspace.means)/horizon+(1-alpha)*sum(workspace.excess)/horizon
end

# Return a singleton Bool across the dynamic problem-data boundary. The scalar
# stays in private typed storage, avoiding a boxed Float64 at every call.
function store_value!(workspace,value)
    value===nothing && return false
    workspace.value=Float64(value)
    true
end
tsp!(workspace,x,distance)=store_value!(workspace,tsp(x,distance))
qap!(workspace,x,flow,distance)=store_value!(workspace,qap(x,flow,distance))
route_value!(workspace,family,x,distance,vehicles,prize)=
    store_value!(workspace,route_objective(family,x,distance,vehicles,prize))
cluster_value!(workspace,x,coordinates,clusters)=store_value!(workspace,clusters!(workspace,x,coordinates,clusters))
cars!(workspace,x,history,colors,options,windows,limits,priorities,objective_order)=
    store_value!(workspace,cars(x,history,colors,options,windows,limits,priorities,objective_order))
maintenance_value!(workspace,x,duration,risk_by_start,scenario_count,horizon,quantile,alpha)=
    store_value!(workspace,maintenance!(workspace,x,duration,risk_by_start,scenario_count,horizon,quantile,alpha))
end
