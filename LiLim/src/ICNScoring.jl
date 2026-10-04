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

mutable struct ErrorBackend{S,E,O}
    kind::Symbol
    scalar::S
    equal::E
    ordered::O
    calls::Int
    evaluations::Int
    bank_sha256::String
    witnesses::Vector{Int}
end

clone_backend(b::ErrorBackend) = ErrorBackend(b.kind,b.scalar,b.equal,b.ordered,0,0,
    b.bank_sha256,copy(b.witnesses))

function load_backend(kind::Symbol; bank=BANK)
    kind in (:naive,:icn,:direct) || throw(ArgumentError("unknown error backend"))
    kind == :icn || return ErrorBackend(kind,nothing,nothing,nothing,0,0,"",Int[])
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
    ErrorBackend(kind,decoded...,0,0,bytes2hex(sha256(read(bank))),indices)
end

metadata(b::ErrorBackend) = Dict("backend"=>string(b.kind),"score_evaluations"=>b.evaluations,
    "icn_decoder_calls"=>b.calls,"bank_sha256"=>b.bank_sha256,"witness_indices"=>b.witnesses,
    "provenance"=>b.kind==:icn ? "recovered manually constructed witnesses in a learnable grammar; no new training" : "handwritten route error; Boolean reduction in naive variant",
    "structural_gate"=>"successor decoding checks service uniqueness and disconnected cycles",
    "mapping"=>"scalar residuals: fleet, continuous time, prefix load and return load; allEqual: pair routes; strict ordered: pickup before delivery")

function scalar(b,x,op,val)
    if b.kind == :icn
        b.calls += 1
        return b.scalar([x];op,val)
    end
    op === (==) && return abs(x-val)
    op === (<=) && return max(0.,x-val)
    op === (>=) && return max(0.,val-x)
    error("unsupported scalar relation")
end

"Times and prefix loads are derived views; recovered ICNs evaluate their constraint residuals."
function score(b::ErrorBackend,p,D,values)
    b.evaluations += 1
    routes = try
        routes_from_successors(p,values)
    catch error
        error isa ArgumentError || error isa DimensionMismatch || rethrow()
        return (error=1.,distance=Inf,vehicles=typemax(Int))
    end
    d = p.data
    error = scalar(b,length(routes),(<=),d.vehicles)
    route_of = zeros(Int,length(d.demand)); position = similar(route_of)
    total = 0.
    for (r,route) in enumerate(routes)
        clock = d.earliest[1]; load = 0; previous = 1
        for (order,node) in enumerate(route)
            route_of[node] = r; position[node] = order
            travel = D[previous,node]; total += travel
            clock = max(d.earliest[node],clock+d.service[previous]+travel)
            error += scalar(b,clock-d.latest[node]-1e-8,(<=),0.)
            load += d.demand[node]
            error += scalar(b,load,(>=),0) + scalar(b,load,(<=),d.capacity)
            previous = node
        end
        total += D[previous,1]
        error += scalar(b,clock+d.service[previous]+D[previous,1]-d.latest[1]-1e-8,(<=),0.)
        error += scalar(b,load,(==),0)
    end
    for (pickup,delivery) in d.pairs
        if b.kind == :icn
            b.calls += 2
            error += b.equal([route_of[pickup],route_of[delivery]])
            error += b.ordered([position[pickup],position[delivery]])
        else
            error += route_of[pickup] != route_of[delivery]
            error += position[pickup] >= position[delivery]
        end
    end
    (;error=b.kind == :naive ? Float64(!iszero(error)) : Float64(error),distance=total,vehicles=length(routes))
end
(b::ErrorBackend)(p,D,values) = score(b,p,D,values)
end
