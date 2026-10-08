"Sparse value-pair interaction guidance. Its energy never replaces original validation."
module QUBOGuidance
using SparseArrays, Random, TOML, SHA
import QUBOConstraints as QC
export Guide, Workspace, from_matrix, from_component, load_guide, structural_guide,
    refresh!, energy, delta!, scope!, proposal!, metadata, configured_guide,write_guide

isdefined(QC,:ValuePairGuidance) || error("This source cohort requires the qualified QUBOConstraints.ValuePairGuidance API")
const Guide=QC.ValuePairGuidance.Guide
const Workspace=QC.ValuePairGuidance.Workspace
const refresh! = QC.ValuePairGuidance.refresh!
const energy=QC.ValuePairGuidance.energy
const delta! = QC.ValuePairGuidance.delta!
const scope! = QC.ValuePairGuidance.scope!
const proposal! = QC.ValuePairGuidance.proposal!
const metadata=QC.ValuePairGuidance.metadata

"Full z'Qz matrix convention: off-diagonal Qij + Qji becomes one pair term."
function from_matrix(Q::AbstractMatrix,atoms;kw...)
    size(Q)==(length(atoms),length(atoms)) || throw(DimensionMismatch("QUBO matrix/atom order"))
    n=length(atoms);linear=zeros(n);pairs=Dict{Tuple{Int,Int},Float64}()
    # Sparse traversal avoids materializing a dense value-by-value matrix.
    rows,cols,values=findnz(sparse(Q))
    for (i,j,v) in zip(rows,cols,values)
        if i==j;linear[i]+=Float64(v)
        else;k=minmax(i,j);pairs[k]=get(pairs,k,0.)+Float64(v);end
    end
    Guide(atoms,linear,[(i,j,v) for ((i,j),v) in sort!(collect(pairs);by=first)];kw...)
end

"Import a QUBOConstraints component with explicit primary-bit -> (variable,value) bindings."
function from_component(q,bindings;max_atoms=2048,max_terms=20000)
    length(q.bits)<=max_atoms || throw(ArgumentError("QUBO guide size cap exceeded"))
    primary=findall(b->b.role==:primary,q.bits)
    all(i->haskey(bindings,q.bits[i]),primary) || throw(ArgumentError("explicit binding required for every primary bit"))
    for book in q.codebooks
        hasproperty(book,:codes) || throw(ArgumentError("only explicit one-hot codebooks are qualified for value-atom guidance"))
        for column in axes(book.codes,2)
            count(view(book.codes,:,column))==1 || throw(ArgumentError("component uses a non-one-hot codebook"))
            bit=book.bits[findfirst(view(book.codes,:,column))]
            bindings[bit][2]==book.values[book.value_indices[column]] || throw(ArgumentError("binding changes a codebook value"))
        end
        length(unique(bindings[bit][1] for bit in book.bits))==1 || throw(ArgumentError("one codebook must bind one original variable"))
    end
    atoms=[bindings[q.bits[i]] for i in primary];positions=Dict(i=>k for (k,i) in enumerate(primary))
    linear=Float64[q.linear[i] for i in primary];terms=Tuple{Int,Int,Float64}[]
    rows,cols,values=findnz(q.quadratic)
    for (i,j,v) in zip(rows,cols,values)
        haskey(positions,i) && haskey(positions,j) || continue
        push!(terms,(positions[i],positions[j],Float64(v)))
    end
    Guide(atoms,linear,terms;max_atoms,max_terms,
        provenance="primary interaction projection; auxiliaries omitted; "*q.provenance)
end

"Serialize an explicitly mapped learned guide without overwriting existing evidence."
function write_guide(path,g::Guide;instance_sha256="")
    destination=abspath(path);ispath(destination) && throw(ArgumentError("guide destination already exists"))
    row=Dict("schema"=>"value-pair-qubo-guide/1","encoding"=>"one_hot_value_atoms",
        "convention"=>"canonical_polynomial","instance_sha256"=>instance_sha256,"provenance"=>g.provenance,
        "atoms"=>[Dict("variable"=>i,"value"=>v) for (i,v) in g.atoms],"linear"=>g.linear,
        "quadratic"=>[[g.left[k],g.right[k],g.coefficient[k]] for k in eachindex(g.coefficient)])
    mkpath(dirname(destination))
    mktemp(dirname(destination)) do temporary,io
        TOML.print(io,row;sorted=true);close(io);mv(temporary,destination)
    end
    destination
end

function load_guide(path;instance_sha256=nothing,max_atoms=2048,max_terms=20000)
    row=TOML.parsefile(path)
    row["schema"]=="value-pair-qubo-guide/1" || throw(ArgumentError("unknown guide schema"))
    row["encoding"]=="one_hot_value_atoms" || throw(ArgumentError("explicit one-hot value atoms required"))
    row["convention"]=="canonical_polynomial" || throw(ArgumentError("explicit canonical polynomial required"))
    expected=get(row,"instance_sha256","")
    isempty(expected) || (instance_sha256!==nothing && expected==instance_sha256) ||
        throw(ArgumentError("guide belongs to another original instance"))
    Guide([(a["variable"],a["value"]) for a in row["atoms"]],row["linear"],
        [(t[1],t[2],t[3]) for t in row["quadratic"]];max_atoms,max_terms,
        provenance=get(row,"provenance","external value-pair matrix"),source_sha256=bytes2hex(sha256(read(path))))
end

"Analytic structural proxy, explicitly not a learned constraint or an exact QUBO reformulation."
function structural_guide(domains,relations;max_values=8,max_atoms=2048,max_terms=20000)
    atoms=Tuple{Int,Int}[];ranges=[Int[] for _ in domains]
    for (i,domain) in enumerate(domains)
        length(atoms)+min(length(domain),max_values)<=max_atoms || break
        for value in Iterators.take(domain,max_values)
            push!(atoms,(i,Int(value)));push!(ranges[i],length(atoms))
        end
    end
    terms=Tuple{Int,Int,Float64}[]
    for (i,j,weight) in relations
        1<=i<=length(ranges) && 1<=j<=length(ranges) || throw(ArgumentError("invalid structural relation"))
        i==j && continue
        for a in ranges[i],b in ranges[j]
            length(terms)<max_terms || break
            # Agreement/disagreement creates value-dependent edges for guidance only.
            c=weight*(atoms[a][2]==atoms[b][2] ? 1.0 : -0.25)
            push!(terms,(a,b,Float64(c)))
        end
        length(terms)>=max_terms && break
    end
    combined=Dict{Tuple{Int,Int},Float64}()
    for (a,b,c) in terms;k=minmax(a,b);combined[k]=get(combined,k,0.)+c;end
    Guide(atoms,zeros(length(atoms)),[(a,b,c) for ((a,b),c) in sort!(collect(combined);by=first)];
        max_atoms,max_terms,provenance="analytic structural proxy; no learned matrix supplied; guidance only")
end
function configured_guide(domains,relations;id="",instance_sha256=nothing,kw...)
    source=get(ENV,"JULIACONSTRAINTS_QUBO_GUIDE","")
    isempty(source) && return structural_guide(domains,relations;kw...)
    path=isdir(source) ? joinpath(source,id*".toml") : source
    isfile(path) || throw(ArgumentError("requested QUBO guide is unavailable: $path"))
    g=load_guide(path;instance_sha256)
    all(a->a[1]<=length(domains) && a[2] in domains[a[1]],g.atoms) ||
        throw(ArgumentError("guide atom is outside the original variable domain"))
    g
end

"Freeze every explicitly requested external guide before a cohort can start or resume."
function input_manifest(ids)
    source=get(ENV,"JULIACONSTRAINTS_QUBO_GUIDE","")
    isempty(source) && return Dict("source"=>"analytic_proxy","files"=>Dict{String,String}())
    files=Dict{String,String}()
    for id in ids
        path=isdir(source) ? joinpath(source,id*".toml") : source
        isfile(path) || throw(ArgumentError("requested QUBO guide is unavailable: $path"))
        files[string(id)]=bytes2hex(sha256(read(path)))
    end
    Dict("source"=>"external_matrix","files"=>files)
end
end
