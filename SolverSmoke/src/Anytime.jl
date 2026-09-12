module Anytime
using TOML
export Trace, observe!, save_trace, RouteData, read_routes, decode, evaluate, write_input

"Monotonic, synchronized incumbent observations; observers must be detached after solve."
mutable struct Trace
    origin::UInt64
    solve_origin::UInt64
    best::Float64
    events::Vector{Dict{String,Any}}
    mutex::ReentrantLock
end
Trace() = Trace(time_ns(), UInt64(0), Inf, Dict{String,Any}[], ReentrantLock())
function observe!(t::Trace, objective, values)
    lock(t.mutex) do
        objective < t.best || return
        # Timestamp inside the lock gives a total order across search threads.
        stamp=time_ns()
        t.best=objective
        push!(t.events,Dict("elapsed_seconds"=>(stamp-t.origin)/1e9,
            "solve_seconds"=>t.solve_origin==0 ? 0. : (stamp-t.solve_origin)/1e9,
            "objective"=>Float64(objective), "values"=>Int.(values),
            "phase"=>t.solve_origin==0 ? "initialization" : "search"))
    end
    nothing
end
save_trace(path,t;kwargs...) = open(path,"w") do io
    metadata=Dict{String,Any}("schema"=>"incumbent-trace/1", "clock"=>"monotonic",
        "events"=>t.events, "found"=>!isempty(t.events),
        "timing_available"=>true, "proof_time_available"=>false)
    merge!(metadata,Dict(String(k)=>v for (k,v) in kwargs))
    TOML.print(io,metadata;sorted=true)
end

"Versioned native interchange. Node indices are one-based, depot is 1."
struct RouteData
    fleet::Int
    capacity::Int
    nodes::Matrix{Float64} # id,x,y,demand,early,late,service,pickup
    distances::Matrix{Float64}
    big_m::Float64
end
function RouteData(fleet,capacity,nodes)
    n=size(nodes,1)
    D=[hypot(nodes[i,2]-nodes[j,2],nodes[i,3]-nodes[j,3]) for i in 1:n,j in 1:n]
    # At most 2*(n-1) edges in any complete collection of nonempty routes.
    M=2*(n-1)*maximum(D)+1
    RouteData(fleet,capacity,nodes,D,M)
end
function read_routes(path)
    lines=readlines(path);header=split(lines[1])
    header[1]=="pdptw/1" || error("Expected versioned PDPTW input")
    n,capacity,fleet=parse.(Int,header[2:4])
    nodes=reduce(vcat,[permutedims(parse.(Float64,split(line))) for line in lines[2:end]])
    size(nodes)==(n,8) || error("Invalid nodes")
    RouteData(fleet,capacity,nodes)
end
function write_input(path,p)
    d=p.data;n=length(d.demand)
    pickup=Dict(b=>a for (a,b) in d.pairs)
    open(path,"w") do io
        println(io,"pdptw/1 $n $(d.capacity) $(d.vehicles)")
        for i in 1:n
            println(io,join((i,d.coordinates[i,1],d.coordinates[i,2],d.demand[i],
                d.earliest[i],d.latest[i],d.service[i],get(pickup,i,0))," "))
        end
    end
end
"A permutation of customers 2:n and distinct separators n+1:n+fleet-1."
function decode(d,values)
    n=size(d.nodes,1);routes=[Int[]]
    for i in values
        if i>n;push!(routes,Int[]);else;push!(last(routes),Int(i));end
    end
    filter!(!isempty,routes)
end
function evaluate(d,values)
    n=size(d.nodes,1);N=n+d.fleet-2
    length(values)==N && all(i->2<=i<=N+1,values) || return (Inf,Inf)
    error=Float64(N-length(unique(values)));distance=0.;used=0
    for route in decode(d,values)
        used+=1;clock=d.nodes[1,5];load=0.;previous=1;seen=Set{Int}()
        for i in route
            travel=d.distances[previous,i];distance+=travel
            clock=max(d.nodes[i,5],clock+d.nodes[previous,7]+travel)
            error+=max(0.,clock-d.nodes[i,6]);load+=d.nodes[i,4]
            error+=max(0.,-load)+max(0.,load-d.capacity)
            pickup=Int(d.nodes[i,8]);pickup>0 && !(pickup in seen) && (error+=1)
            push!(seen,i);previous=i
        end
        distance+=d.distances[previous,1]
        error+=max(0.,clock+d.nodes[previous,7]+d.distances[previous,1]-d.nodes[1,6])+abs(load)
    end
    error+=max(0,used-d.fleet)
    (error,used*d.big_m+distance)
end
end
