"Sparse value-pair interaction guidance. Its energy never replaces original validation."
module QUBOGuidance
using SparseArrays, Random, TOML, SHA
export Guide, Workspace, from_matrix, from_component, load_guide, structural_guide,
    refresh!, energy, delta!, scope!, proposal!, metadata, configured_guide,write_guide

struct Guide
    atoms::Vector{Tuple{Int,Int}}
    linear::Vector{Float64}
    left::Vector{Int}
    right::Vector{Int}
    coefficient::Vector{Float64}
    by_variable::Vector{Vector{Int}}
    by_atom_terms::Vector{Vector{Int}}
    by_variable_terms::Vector{Vector{Int}}
    provenance::String
    source_sha256::String
end
function Guide(atoms,linear,terms;provenance="unspecified guidance",source_sha256="",
        max_atoms=2048,max_terms=20000)
    a=Tuple{Int,Int}[(Int(i),Int(v)) for (i,v) in atoms]
    length(a)<=max_atoms && length(terms)<=max_terms || throw(ArgumentError("QUBO guide size cap exceeded"))
    allunique(a) && all(x->x[1]>0,a) || throw(ArgumentError("duplicate or invalid value atom"))
    length(linear)==length(a) && all(isfinite,linear) || throw(ArgumentError("invalid linear guide coefficients"))
    l=Float64.(linear);left=Int[];right=Int[];coefficient=Float64[]
    seen=Set{Tuple{Int,Int}}()
    for (i,j,c) in terms
        1<=i<=length(a) && 1<=j<=length(a) && isfinite(c) || throw(ArgumentError("invalid pair coefficient"))
        i,j=minmax(Int(i),Int(j));(i,j) in seen && throw(ArgumentError("duplicate canonical pair coefficient"))
        push!(seen,(i,j))
        if i==j;l[i]+=c
        elseif !iszero(c);push!(left,i);push!(right,j);push!(coefficient,Float64(c));end
    end
    all(isfinite,l) && all(isfinite,coefficient) || throw(ArgumentError("coefficient conversion overflow"))
    n=isempty(a) ? 0 : maximum(first,a);n<=max_atoms || throw(ArgumentError("variable index exceeds guide cap"))
    by=[Int[] for _ in 1:n]
    for (k,(i,_)) in enumerate(a);push!(by[i],k);end
    atom_terms=[Int[] for _ in a];variable_terms=[Int[] for _ in by]
    for k in eachindex(coefficient)
        i,j=left[k],right[k];u,v=a[i][1],a[j][1]
        push!(atom_terms[i],k);push!(atom_terms[j],k)
        push!(variable_terms[u],k);u==v || push!(variable_terms[v],k)
    end
    Guide(a,l,left,right,coefficient,by,atom_terms,variable_terms,String(provenance),String(source_sha256))
end

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

mutable struct Workspace
    active::Vector{Float64}
    change::Vector{Float64}
    strength::Vector{Float64}
    affinity::Vector{Float64}
    chosen::Vector{Int}
    replacements::Vector{Int}
    selected::Vector{Bool}
    field::Vector{Float64}
end
Workspace(g::Guide)=Workspace(zeros(length(g.atoms)),zeros(length(g.atoms)),
    zeros(length(g.by_variable)),zeros(length(g.by_variable)),Int[],Int[],fill(false,length(g.by_variable)),zeros(length(g.atoms)))
function refresh!(w,g,values)
    length(values)>=length(g.by_variable) || throw(DimensionMismatch("guide parent variables"))
    @inbounds @simd for k in eachindex(g.atoms)
        i,v=g.atoms[k];w.active[k]=Float64(values[i]==v)
    end
    w
end
function energy(g,w)
    total=0.0
    @inbounds @simd for i in eachindex(g.linear);total+=g.linear[i]*w.active[i];end
    @inbounds @simd for k in eachindex(g.coefficient)
        total+=g.coefficient[k]*w.active[g.left[k]]*w.active[g.right[k]]
    end
    total
end
"Exact simultaneous-move delta for this guide, including changed/changed interactions once."
function delta!(w,g,ids,replacements)
    length(ids)==length(replacements) || throw(ArgumentError("invalid move scope"))
    # Small depth scopes: avoid allocating a Set on every candidate evaluation.
    for k in eachindex(ids),j in firstindex(ids):k-1
        ids[k]!=ids[j] || throw(ArgumentError("duplicate move variable"))
    end
    fill!(w.change,0.0)
    for (i,v) in zip(ids,replacements)
        1<=i<=length(g.by_variable) || throw(BoundsError(g.by_variable,i))
        for k in g.by_variable[i];w.change[k]=Float64(g.atoms[k][2]==v)-w.active[k];end
    end
    total=0.0
    @inbounds @simd for i in eachindex(g.linear);total+=g.linear[i]*w.change[i];end
    @inbounds @simd for k in eachindex(g.coefficient)
        i,j=g.left[k],g.right[k]
        total+=g.coefficient[k]*(w.change[i]*w.active[j]+w.active[i]*w.change[j]+w.change[i]*w.change[j])
    end
    total
end
function scope!(w,g,values,depth,rng;mode="absolute",exploration=0.10)
    mode in ("absolute","conditional") && 0<=exploration<=1 && depth>0 || throw(ArgumentError("invalid guide policy"))
    refresh!(w,g,values);fill!(w.strength,0.);fill!(w.affinity,0.);fill!(w.selected,false);empty!(w.chosen)
    for k in eachindex(g.coefficient)
        i,j=g.left[k],g.right[k];a,b=g.atoms[i][1],g.atoms[j][1]
        c=abs(g.coefficient[k])*(mode=="conditional" ? (w.active[i]+w.active[j])/2 : 1.)
        w.strength[a]+=c;w.strength[b]+=c
    end
    n=length(w.strength);n==0 && return w.chosen
    seed=rand(rng)<exploration || maximum(w.strength)==0 ? rand(rng,1:n) : argmax(w.strength)
    for _ in 1:min(depth,n)
        w.selected[seed]=true;push!(w.chosen,seed)
        for k in g.by_variable_terms[seed]
            a,b=g.atoms[g.left[k]][1],g.atoms[g.right[k]][1]
            c=abs(g.coefficient[k])*(mode=="conditional" ? (w.active[g.left[k]]+w.active[g.right[k]])/2 : 1.)
            if a==seed;w.affinity[b]+=c
            elseif b==seed;w.affinity[a]+=c;end
        end
        best=0;quality=-Inf
        for i in 1:n
            w.selected[i] && continue
            q=w.affinity[i]+1e-6*w.strength[i]
            if q>quality;best=i;quality=q;end
        end
        best==0 && break
        seed=best
    end
    sort!(w.chosen)
end
"Bounded depth proposal; sequential field minimization permits non-worsening joint guide moves."
function proposal!(w,g,values,depth,rng;mode="absolute",exploration=0.1,max_candidates=32)
    max_candidates>0 || throw(ArgumentError("positive guide candidate cap required"))
    scope!(w,g,values,depth,rng;mode,exploration);empty!(w.replacements)
    # One sparse field pass, then neighbor-only updates after each accepted atom.
    copyto!(w.field,g.linear)
    for k in eachindex(g.coefficient)
        a,b=g.left[k],g.right[k]
        g.atoms[a][1]==g.atoms[b][1] && continue # mutually exclusive atoms
        w.field[a]+=g.coefficient[k]*w.active[b];w.field[b]+=g.coefficient[k]*w.active[a]
    end
    # active/field are lane-owned scratch; restore active before returning a move.
    examined=0
    for i in w.chosen
        best=values[i];oldfield=0.0
        for k in g.by_variable[i];oldfield+=w.active[k]*w.field[k];end
        bestfield=oldfield
        for k in g.by_variable[i]
            examined>=max_candidates && break
            candidate=g.atoms[k][2];examined+=1
            if w.field[k]<bestfield;best=candidate;bestfield=w.field[k];end
        end
        push!(w.replacements,Int(best))
        for a in g.by_variable[i]
            change=Float64(g.atoms[a][2]==best)-w.active[a]
            iszero(change) && continue
            for k in g.by_atom_terms[a]
                b=g.left[k]==a ? g.right[k] : g.left[k]
                g.atoms[b][1]==i && continue
                w.field[b]+=g.coefficient[k]*change
            end
            w.active[a]+=change
        end
    end
    refresh!(w,g,values)
    (;ids=w.chosen,values=w.replacements,examined,delta=delta!(w,g,w.chosen,w.replacements))
end
metadata(g::Guide)=Dict("provenance"=>g.provenance,"source_sha256"=>g.source_sha256,
    "atoms"=>length(g.atoms),"pair_terms"=>length(g.coefficient),"authority"=>"guidance_only",
    "encoding"=>"explicit_one_hot_value_atoms","convention"=>"canonical_polynomial")

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
