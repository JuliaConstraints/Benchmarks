module PermutationRoutes
export RouteData, read_common, decode, evaluate
struct RouteData
    fleet::Int
    capacity::Int
    nodes::Matrix{Float64}
    distances::Matrix{Float64}
    big_m::Float64
    initial::Vector{Int}
end
function read_common(path)
    lines=readlines(path);header=split(lines[1]);header[1]=="lilim-common-start/1" || error("wrong schema")
    n,capacity,fleet=parse.(Int,header[2:4])
    nodes=reduce(vcat,[permutedims(parse.(Float64,split(line))) for line in lines[2:n+1]])
    values=Int[]
    for k in 1:fleet
        row=parse.(Int,split(lines[n+1+k]));row[1]==length(row)-1 || error("route size mismatch")
        append!(values,row[2:end]);k<fleet && push!(values,n+k)
    end
    D=[hypot(nodes[i,2]-nodes[j,2],nodes[i,3]-nodes[j,3]) for i in 1:n,j in 1:n]
    RouteData(fleet,capacity,nodes,D,2(n-1)*maximum(D)+1,values)
end
function decode(d,values)
    n=size(d.nodes,1);routes=[Int[]]
    for i in values
        if i>n;push!(routes,Int[]);else;push!(last(routes),Int(i));end
    end
    filter!(!isempty,routes)
end
function evaluate(d,values)
    n=size(d.nodes,1);N=n+d.fleet-2
    length(values)==N && all(i->2<=i<=N+1,values) || return (error=Inf,vehicles=0,distance=Inf)
    error=Float64(N-length(unique(values)));distance=0.;used=0
    for route in decode(d,values)
        used+=1;clock=d.nodes[1,5];load=0.;previous=1;seen=Set{Int}()
        for i in route
            travel=d.distances[previous,i];distance+=travel
            clock=max(d.nodes[i,5],clock+d.nodes[previous,7]+travel)
            error+=max(0.,clock-d.nodes[i,6]-1e-8);load+=d.nodes[i,4]
            error+=max(0.,-load)+max(0.,load-d.capacity)
            pickup=Int(d.nodes[i,8]);pickup>0 && !(pickup in seen) && (error+=1)
            push!(seen,i);previous=i
        end
        distance+=d.distances[previous,1]
        error+=max(0.,clock+d.nodes[previous,7]+d.distances[previous,1]-d.nodes[1,6]-1e-8)+abs(load)
    end
    error+=max(0,used-d.fleet)
    (;error,vehicles=used,distance)
end
end
