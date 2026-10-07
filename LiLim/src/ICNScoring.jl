"Recovered ICN decoders as the actual route constraint error backend."
module ICNScoring
using TOML, SHA
import CompositionalNetworks as CN
using ..MetaRepair

export ErrorBackend, load_backend, clone_backend, score, metadata
const LEGACY_BANK = joinpath(homedir(), ".julia", "dev", "ConstraintLearningBenchmarks",
    "scripts", "xcsp3_core", "learnable_catalog", "weights.toml")
const PORTABLE_BANK = normpath(joinpath(@__DIR__, "..", "resources", "icn-pdptw-witnesses.toml"))
const BANK = get(ENV, "JULIACONSTRAINTS_ICN_BANK", isfile(PORTABLE_BANK) ? PORTABLE_BANK : LEGACY_BANK)

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
    error_terms::Vector{Float64}
end
RouteScoreWorkspace() = RouteScoreWorkspace(Int[],Int[],BitVector(),Int[],Int[],Int[],[0],[0.],[0,0],Float64[])

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
clone_backend(b::ErrorBackend, kind::Symbol) = ErrorBackend(kind,b.scalar,b.equal,b.ordered,0,0,
    b.bank_sha256,copy(b.witnesses),RouteScoreWorkspace())

function load_backend(kind::Symbol; bank=BANK)
    kind in (:naive,:icn,:icn_fused_scalar,:icn_fused_all,:direct) || throw(ArgumentError("unknown error backend"))
    kind in (:icn,:icn_fused_scalar,:icn_fused_all) || return ErrorBackend(kind,nothing,nothing,nothing,0,0,"",Int[],RouteScoreWorkspace())
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
    "provenance"=>startswith(string(b.kind),"icn") ? "recovered manually constructed witnesses in a learnable grammar; no new training" : "handwritten route error; Boolean reduction in naive variant",
    "structural_gate"=>"successor decoding checks service uniqueness and disconnected cycles",
    "workspace"=>"lane-owned route views and reusable ICN inputs/1; decoder functions unchanged",
    "mapping"=>"scalar residuals: fleet, continuous time, prefix load and return load; allEqual: pair routes; strict ordered: pickup before delivery",
    "fusion"=>b.kind==:icn_fused_scalar ? "exact sum of scalar constraint residuals through one learned sum-condition decoder; pair decoders remain per pair" :
        b.kind==:icn_fused_all ? "exact sum of scalar and pair violation indicators through one learned sum-condition decoder; pair-specific ICN decoders are bypassed" : "none")

@inline function direct_residual(x,op,val)
    op === (==) && return abs(x-val)
    op === (<=) && return max(0.,x-val)
    op === (>=) && return max(0.,val-x)
    error("unsupported scalar relation")
end

@inline function scalar(b,x,op,val)
    if b.kind == :icn
        b.calls += 1
        input = x isa Int ? b.workspace.scalar_integer :
            x isa Float64 ? b.workspace.scalar_real : [x]
        input[1] = x
        return b.scalar(input;op,val)
    elseif b.kind in (:icn_fused_scalar,:icn_fused_all)
        b.calls += 1
        input = b.workspace.scalar_real
        input[1] = direct_residual(x,op,val)
        return b.scalar(input;op=(==),val=0)
    end
    direct_residual(x,op,val)
end

@inline function add_scalar_constraint!(b,x,op,val)
    if b.kind in (:icn_fused_scalar,:icn_fused_all)
        push!(b.workspace.error_terms,Float64(direct_residual(x,op,val)))
        return 0.0
    end
    scalar(b,x,op,val)
end

"Times and prefix loads are derived views; recovered ICNs evaluate their constraint residuals."
function score(b::ErrorBackend,p,D,values)
    b.evaluations += 1
    d = p.data; n = length(d.demand)
    invalid = (error=1.,distance=Inf,vehicles=typemax(Int))
    w = b.workspace
    fused_scalar = b.kind in (:icn_fused_scalar,:icn_fused_all)
    fused_all = b.kind == :icn_fused_all
    if fused_scalar
        empty!(w.error_terms)
        sizehint!(w.error_terms,1+3*(n-1)+2d.vehicles+2length(d.pairs))
    end
    # Invalid neighbors are ordinary search outcomes, without exception/backtrace
    # construction. Validate the full structure before calling any ICN decoder.
    vehicles = decode_successor_views!(w,n,values)
    vehicles===nothing && return invalid
    error = fused_scalar ? 0.0 : scalar(b,vehicles,(<=),d.vehicles)
    fused_scalar && push!(w.error_terms,Float64(direct_residual(vehicles,(<=),d.vehicles)))
    total = 0.
    for r in 1:vehicles
        clock = d.earliest[1]; load = 0; previous = 1
        node = w.heads[r]
        while node!=1
            travel = D[previous,node]; total += travel
            clock = max(d.earliest[node],clock+d.service[previous]+travel)
            error += add_scalar_constraint!(b,clock-d.latest[node]-1e-8,(<=),0.)
            load += d.demand[node]
            error += add_scalar_constraint!(b,load,(>=),0) + add_scalar_constraint!(b,load,(<=),d.capacity)
            previous = node
            node = w.next[node-1]
        end
        total += D[previous,1]
        error += add_scalar_constraint!(b,clock+d.service[previous]+D[previous,1]-d.latest[1]-1e-8,(<=),0.)
        error += add_scalar_constraint!(b,load,(==),0)
    end
    for (pickup,delivery) in d.pairs
        if b.kind == :icn
            b.calls += 2
            w.pair[1] = w.route_of[pickup]; w.pair[2] = w.route_of[delivery]
            error += b.equal(w.pair)
            w.pair[1] = w.position[pickup]; w.pair[2] = w.position[delivery]
            error += b.ordered(w.pair)
        elseif b.kind == :icn_fused_scalar
            b.calls += 2
            w.pair[1] = w.route_of[pickup]; w.pair[2] = w.route_of[delivery]
            error += b.equal(w.pair)
            w.pair[1] = w.position[pickup]; w.pair[2] = w.position[delivery]
            error += b.ordered(w.pair)
        elseif fused_all
            push!(w.error_terms,Float64(w.route_of[pickup] != w.route_of[delivery]))
            push!(w.error_terms,Float64(w.position[pickup] >= w.position[delivery]))
        else
            error += w.route_of[pickup] != w.route_of[delivery]
            error += w.position[pickup] >= w.position[delivery]
        end
    end
    if fused_scalar
        b.calls += 1
        error += b.scalar(w.error_terms;op=(==),val=0)
    end
    (;error=b.kind == :naive ? Float64(!iszero(error)) : Float64(error),distance=total,vehicles)
end
(b::ErrorBackend)(p,D,values) = score(b,p,D,values)
end
