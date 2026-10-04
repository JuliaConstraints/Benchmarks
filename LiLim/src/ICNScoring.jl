"Recovered ICN decoders as the actual route constraint error backend."
module ICNScoring
using TOML, SHA
import CompositionalNetworks as CN
using ..MetaRepair

export ErrorBackend, load_backend, clone_backend, score, metadata
const BANK = joinpath(homedir(), ".julia", "dev", "ConstraintLearningBenchmarks",
    "scripts", "xcsp3_core", "learnable_catalog", "weights.toml")

function schema_hash(network)
    available = parentindices(network.weights)[1]
    offset = 0
    parts = String[]
    for layer in network.layers
        ops = [name for (j,name) in enumerate(keys(layer.fn)) if offset+j in available]
        push!(parts, repr((layer.name, layer.mutex, ops)))
        offset += length(layer.fn)
    end
    bytes2hex(sha256("ICN:" * join(parts,";")))
end

"Mutable buffers belong to one search lane; compiled decoders are read-only."
struct RouteScoreWorkspace
    next::Vector{Int}
    incoming::Vector{Int}
    visited::BitVector
    route_of::Vector{Int}
    position::Vector{Int}
    heads::Vector{Int}
    scalar_integer::Vector{Int}
    scalar_real::Vector{Float64}
    pair::Vector{Int}
end
RouteScoreWorkspace() = RouteScoreWorkspace(Int[],Int[],BitVector(),Int[],Int[],Int[],[0],[0.],[0,0])
function resize_workspace!(w,n)
    length(w.incoming)==n && return w
    resize!(w.next,n-1)
    for buffer in (w.incoming,w.visited,w.route_of,w.position,w.heads)
        resize!(buffer,n)
    end
    w
end

mutable struct ErrorBackend{S,E,O}
    kind::Symbol
    scalar::S
    equal::E
    ordered::O
    calls::Int
    evaluations::Int
    bank_sha256::String
    witnesses::Vector{Int}
    workspace::RouteScoreWorkspace
end

clone_backend(b::ErrorBackend) = ErrorBackend(b.kind,b.scalar,b.equal,b.ordered,0,0,
    b.bank_sha256,copy(b.witnesses),RouteScoreWorkspace())

function load_backend(kind::Symbol; bank=BANK)
    kind in (:naive,:icn,:direct) || throw(ArgumentError("unknown error backend"))
    kind == :icn || return ErrorBackend(kind,nothing,nothing,nothing,0,0,"",Int[],RouteScoreWorkspace())
    saved = TOML.parsefile(bank)["witnesses"]
    indices = [4,2,52]
    signatures = ((;op=(==),val=2), (;), (;))
    expected = (("sum","scalar condition"),("all_equal","numeric list"),
        ("ordered","order <, without offsets"))
    decoded = map(zip(indices,signatures,expected)) do (i,signature,identity)
        w = saved[i]
        (w["family"],w["variant"]) == identity || error("bank witness identity changed")
        w["factory"] == "learnable_composition; max_depth=1" || error("factory changed")
        network = CN.learnable_composition(signature;max_depth=1)
        schema_hash(network) == w["schema_sha256"] || error("ICN schema changed")
        weights = BitVector(w["weights"])
        CN.check_weights_validity(network,weights) || error("invalid recovered weights")
        CN.apply!(network,weights) || error("weights could not be applied")
        CN.composition(network)
    end
    ErrorBackend(kind,decoded...,0,0,bytes2hex(sha256(read(bank))),indices,RouteScoreWorkspace())
end

metadata(b::ErrorBackend) = Dict("backend"=>string(b.kind),"score_evaluations"=>b.evaluations,
    "icn_decoder_calls"=>b.calls,"bank_sha256"=>b.bank_sha256,"witness_indices"=>b.witnesses,
    "provenance"=>b.kind==:icn ? "recovered manually constructed witnesses in a learnable grammar; no new training" : "handwritten route error; Boolean reduction in naive variant",
    "structural_gate"=>"successor decoding checks service uniqueness and disconnected cycles",
    "workspace"=>"lane-owned route views and reusable ICN inputs/1; decoder functions unchanged",
    "mapping"=>"scalar residuals: fleet, continuous time, prefix load and return load; allEqual: pair routes; strict ordered: pickup before delivery")

function scalar(b,x,op,val)
    if b.kind == :icn
        b.calls += 1
        input = x isa Int ? b.workspace.scalar_integer :
            x isa Float64 ? b.workspace.scalar_real : [x]
        input[1] = x
        return b.scalar(input;op,val)
    end
    op === (==) && return abs(x-val)
    op === (<=) && return max(0.,x-val)
    op === (>=) && return max(0.,val-x)
    error("unsupported scalar relation")
end

"Times and prefix loads are derived views; recovered ICNs evaluate their constraint residuals."
function score(b::ErrorBackend,p,D,values)
    b.evaluations += 1
    d = p.data; n = length(d.demand)
    invalid = (error=1.,distance=Inf,vehicles=typemax(Int))
    length(values)==n-1 || return invalid
    w = resize_workspace!(b.workspace,n)
    fill!(w.incoming,0); fill!(w.visited,false)
    # Invalid neighbors are ordinary search outcomes, without exception/backtrace
    # construction. Validate the full structure before calling any ICN decoder.
    for i in 1:n-1
        value = values[i]
        value isa Real && isfinite(value) && isinteger(value) && 1<=value<=n || return invalid
        next = Int(value); w.next[i] = next
        if next!=1
            w.incoming[next] += 1
            w.incoming[next]<=1 || return invalid
        end
    end
    vehicles = 0; serviced = 0
    for first in 2:n
        w.incoming[first]==0 || continue
        vehicles += 1; w.heads[vehicles] = first
        node = first; order = 0
        while node!=1
            w.visited[node] && return invalid
            w.visited[node] = true; serviced += 1; order += 1
            w.route_of[node] = vehicles; w.position[node] = order
            node = w.next[node-1]
        end
    end
    serviced==n-1 || return invalid
    error = scalar(b,vehicles,(<=),d.vehicles)
    total = 0.
    for r in 1:vehicles
        clock = d.earliest[1]; load = 0; previous = 1
        node = w.heads[r]
        while node!=1
            travel = D[previous,node]; total += travel
            clock = max(d.earliest[node],clock+d.service[previous]+travel)
            error += scalar(b,clock-d.latest[node]-1e-8,(<=),0.)
            load += d.demand[node]
            error += scalar(b,load,(>=),0) + scalar(b,load,(<=),d.capacity)
            previous = node
            node = w.next[node-1]
        end
        total += D[previous,1]
        error += scalar(b,clock+d.service[previous]+D[previous,1]-d.latest[1]-1e-8,(<=),0.)
        error += scalar(b,load,(==),0)
    end
    for (pickup,delivery) in d.pairs
        if b.kind == :icn
            b.calls += 2
            w.pair[1] = w.route_of[pickup]; w.pair[2] = w.route_of[delivery]
            error += b.equal(w.pair)
            w.pair[1] = w.position[pickup]; w.pair[2] = w.position[delivery]
            error += b.ordered(w.pair)
        else
            error += w.route_of[pickup] != w.route_of[delivery]
            error += w.position[pickup] >= w.position[delivery]
        end
    end
    (;error=b.kind == :naive ? Float64(!iszero(error)) : Float64(error),distance=total,vehicles)
end
(b::ErrorBackend)(p,D,values) = score(b,p,D,values)
end
