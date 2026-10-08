using Test, Random, SparseArrays, TOML, SHA
import QUBOConstraints as QC
include(joinpath(@__DIR__,"../src/StrategyPanel.jl"))
include(joinpath(@__DIR__,"../src/QUBOGuidance.jl"))
include(joinpath(@__DIR__,"../src/CampaignCatalog.jl"))
include(joinpath(@__DIR__,"../src/SearchPolicies.jl"))
include(joinpath(@__DIR__,"../src/PanelPlotStyles.jl"))
import LocalSearchSolvers as LS

@testset "Distinct opt-in strategy configurations" begin
    @test length(StrategyPanel.CATALOG)==496
    @test allunique(collect(values(StrategyPanel.CATALOG)))
    @test isempty(intersect(CampaignCatalog.select_methods(1,"panel"),StrategyPanel.methods()))
    @test CampaignCatalog.select_methods(1,"extended-panel")==StrategyPanel.methods()
    @test_throws ArgumentError CampaignCatalog.select_methods(1,"missing-method")
    for id in StrategyPanel.methods(),width in (1,2,4,8,16)
        lanes=StrategyPanel.allocation(id,width)
        @test length(lanes)==width
        @test all(lane->lane in StrategyPanel.CATALOG[id].lanes,lanes)
        @test lanes==StrategyPanel.allocation(id,width)
    end
    for row in values(StrategyPanel.CATALOG),lane in row.lanes
        material=SearchPolicies.materialize(LS.model(),lane.policy;overrides=lane.overrides)
        @test material.description["id"]==lane.policy
        @test all(material.description[string(k)]==v for (k,v) in pairs(lane.overrides))
    end
    @test_throws ArgumentError SearchPolicies.settings("tabu_short";overrides=(;fake=1))
    @test_throws ArgumentError SearchPolicies.materialize(LS.model(),"reset_current";overrides=(;fraction=1.1))
    @test SearchPolicies.settings("greedy_guided").plateau_rejection==10
    styles=PanelPlotStyles.styles(StrategyPanel.methods(),StrategyPanel.methods())
    @test allunique([(s.color,s.marker,s.linestyle) for s in values(styles)])
    @test length(styles)==496
end

@testset "Sparse value-pair guide conventions and owned buffers" begin
    G=QUBOGuidance
    @test G.Guide===QC.ValuePairGuidance.Guide
    @test G.Workspace===QC.ValuePairGuidance.Workspace
    atoms=[(i,v) for i in 1:5 for v in 1:3]
    rng=Xoshiro(73);Q=randn(rng,15,15);g=G.from_matrix(Q,atoms)
    w=G.Workspace(g);other=G.Workspace(g)
    @test w.active!==other.active && w.field!==other.field
    for _ in 1:100
        values=rand(rng,1:3,5);G.refresh!(w,g,values)
        z=[Float64(values[i]==v) for (i,v) in atoms]
        @test G.energy(g,w)≈sum(z.*(Q*z)) atol=1e-10
        ids=sort!(randperm(rng,5)[1:rand(rng,1:5)]);replacement=rand(rng,1:3,length(ids))
        trial=copy(values);trial[ids]=replacement
        old=G.energy(g,w);d=G.delta!(w,g,ids,replacement)
        G.refresh!(other,g,trial)
        @test old+d≈G.energy(g,other) atol=1e-10
        for mode in ("absolute","conditional")
            proposal=G.proposal!(w,g,values,4,rng;mode,max_candidates=12)
            @test proposal.examined<=12 && length(proposal.ids)==4 && allunique(proposal.ids)
            @test w.active==z
            @test proposal.delta<=1e-10
            candidate=copy(values);candidate[proposal.ids]=proposal.values
            G.refresh!(other,g,candidate)
            @test old+proposal.delta≈G.energy(g,other) atol=1e-10
        end
    end
    @test_throws ArgumentError G.delta!(w,g,[1,1],[1,2])
    distinct=G.from_matrix(Q,atoms)
    @test_throws ArgumentError G.refresh!(w,distinct,ones(Int,5))
    @test_throws ArgumentError G.energy(distinct,w)
    @test_throws ArgumentError G.delta!(w,distinct,(1,),(2,))
    @test_throws ArgumentError G.Guide([(1,1)],[NaN],[])
    @test_throws ArgumentError G.Guide([(1,1),(1,1)],[0.,0.],[])
    @test_throws ArgumentError G.Guide([(1,1),(2,1)],[0.,0.],[(1,2,1.),(2,1,2.)])
    @test_throws ArgumentError G.proposal!(w,g,ones(Int,5),2,rng;max_candidates=0)
    sparse_guide=G.from_matrix(sparse(Q),atoms)
    @test sparse_guide.coefficient==g.coefficient && sparse_guide.linear==g.linear
    proxy=G.structural_guide(fill(1:3,5),[(1,2,1.),(2,3,2.)])
    @test occursin("no learned matrix",proxy.provenance)
    book=QC.codebook(:variable_a,[1,2,3]);b=QC.BitID(:variable_b,1)
    aux=QC.BitID(:aux,1;role=:semantic_auxiliary)
    component=QC.QUBOComponent(vcat(book.bits,[b,aux]);coefficient_type=Float64,codebooks=[book],
        linear=[(1,1.),(4,2.)],quadratic=[(2,4,-3.),(2,5,100.)],provenance="learned fixture")
    bindings=Dict(bit=>(1,i) for (i,bit) in enumerate(book.bits));bindings[b]=(2,1)
    projection=G.from_component(component,bindings)
    @test length(projection.atoms)==4 && length(projection.coefficient)==1
    projected=G.Workspace(projection);G.refresh!(projected,projection,[2,1])
    @test G.energy(projection,projected)≈-1.
    @test occursin("auxiliaries omitted",projection.provenance)
    @test_throws ArgumentError G.from_component(component,Dict{QC.BitID,Tuple{Int,Int}}())
    wrong=copy(bindings);wrong[book.bits[2]]=(1,99)
    @test_throws ArgumentError G.from_component(component,wrong)
    binary=QC.codebook(:binary,[1,2,3];encoding=:domain_wall)
    q=QC.QUBOComponent(binary.bits;codebooks=[binary])
    @test_throws ArgumentError G.from_component(q,Dict(bit=>(1,i) for (i,bit) in enumerate(binary.bits)))
    mktempdir() do dir
        path=joinpath(dir,"fixture.toml");digest=bytes2hex(sha256("fixture"))
        row=Dict("schema"=>"value-pair-qubo-guide/1","encoding"=>"one_hot_value_atoms",
            "convention"=>"canonical_polynomial","instance_sha256"=>digest,
            "atoms"=>[Dict("variable"=>1,"value"=>2),Dict("variable"=>2,"value"=>1)],
            "linear"=>[1.,2.],"quadratic"=>[[1,2,-3.]],"provenance"=>"learned test fixture")
        open(io->TOML.print(io,row),path,"w")
        @test_throws ArgumentError G.load_guide(path;instance_sha256="wrong")
        loaded=G.load_guide(path;instance_sha256=digest)
        @test loaded.source_sha256==bytes2hex(sha256(read(path)))
        exported=joinpath(dir,"export.toml");G.write_guide(exported,projection;instance_sha256=digest)
        @test G.load_guide(exported;instance_sha256=digest).atoms==projection.atoms
        @test_throws ArgumentError G.write_guide(exported,projection)
        withenv("JULIACONSTRAINTS_QUBO_GUIDE"=>path) do
            @test G.configured_guide(fill(1:3,2),[];instance_sha256=digest).atoms==loaded.atoms
            @test G.input_manifest(["fixture"])["files"]["fixture"]==loaded.source_sha256
            @test_throws ArgumentError G.configured_guide(fill(2:3,2),[];instance_sha256=digest)
        end
    end
    # Warmed allocation checks are stable even while other tasks use the machine.
    function allocations(g,w,values,rng)
        QUBOGuidance.refresh!(w,g,values);QUBOGuidance.energy(g,w);QUBOGuidance.delta!(w,g,(1,2),(2,3))
        QUBOGuidance.proposal!(w,g,values,4,rng)
        (energy=@allocated(QUBOGuidance.energy(g,w)),delta=@allocated(QUBOGuidance.delta!(w,g,(1,2),(2,3))),
            proposal=@allocated(QUBOGuidance.proposal!(w,g,values,4,rng)))
    end
    allocations(g,w,ones(Int,5),rng)
    @test allocations(g,w,ones(Int,5),rng)==(;energy=0,delta=0,proposal=0)
    # The adapter uses the library's sparse frontier instead of rescanning all
    # pair terms for a narrow move. Its delta remains a full polynomial delta.
    sparse_atoms=[(i,v) for i in 1:64 for v in 1:2]
    sparse_terms=[(2i-2+a,2mod1(i+1,64)-2+b,Float64(a-2b)) for i in 1:64 for a in 1:2 for b in 1:2]
    sparse_model=G.Guide(sparse_atoms,zeros(128),sparse_terms)
    sparse_work=G.Workspace(sparse_model);reference=G.Workspace(sparse_model)
    values=ones(Int,64);G.refresh!(sparse_work,sparse_model,values)
    old=G.energy(sparse_model,sparse_work);delta=G.delta!(sparse_work,sparse_model,(1,),(2,))
    values[1]=2;G.refresh!(reference,sparse_model,values)
    @test old+delta≈G.energy(sparse_model,reference) atol=1e-10
    @test sparse_work.pair_visits<length(sparse_model.coefficient)÷8
end
