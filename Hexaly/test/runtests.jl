using Test,TOML,Random
include("../src/Problems.jl")
include("../src/Readers.jl")
include("../src/Scoring.jl")
include("../src/Solvers.jl")
include("fixtures.jl")
using .ReproductionProblems,.ReproductionReaders,.ReproductionScoring,.ReproductionSolvers
const CASES=fixtures()
include("objective_workspaces.jl")
@test isempty(Test.detect_ambiguities(ReproductionScoring;recursive=false))

# Preserve the allocating scheduling/resource algorithm as a differential oracle.
# This checks quantitative term order as well as the independent validity zero set.
function reference_resource_terms!(terms,p,x;atol=p.family==:maintenance ? 1e-5 : 1e-8)
    empty!(terms);d=p.data;f=p.family
    add(v)=push!(terms,Float64(max(0,v)))
    if f in (:rcpsp,:jssp,:fjsp)
        jobs=length(d["duration"]);starts=view(x,1:jobs)
        duration=f==:fjsp ? [d["alternatives"][i][x[jobs+i]][2] for i in 1:jobs] : d["duration"]
        for i in 1:jobs;add(starts[i]+duration[i]-d["horizon"]);end
        for(a,b)in d["precedence"];add(starts[a]+duration[a]-starts[b]);end
        if f==:rcpsp
            events=sort!(unique(vcat(starts,starts.+duration)))
            for t in events,r in axes(d["resource_use"],2)
                add(sum((d["resource_use"][i,r] for i in 1:jobs if starts[i]<=t<starts[i]+duration[i]);init=0.)-d["capacity"][r])
            end
        else
            machine=f==:fjsp ? [d["alternatives"][i][x[jobs+i]][1] for i in 1:jobs] : d["machine"]
            groups=Dict{Int,Vector{Int}}()
            for i in 1:jobs;duration[i]>0 && push!(get!(groups,machine[i],Int[]),i);end
            for tasks in Base.values(groups)
                sort!(tasks;by=i->starts[i]);finish=-1
                for i in tasks;add(finish-starts[i]);finish=max(finish,starts[i]+duration[i]);end
            end
        end
    elseif f==:maintenance
        H=d["horizon"];R=length(d["capacity_upper"][1]);used=zeros(H,R)
        for i in eachindex(x)
            start=x[i];len=d["duration"][i][start];add(start+len-1-H)
            for t in start:min(H,start+len-1);used[t,:].+=d["resource_use_by_start"][i][start][t-start+1];end
        end
        for t in 1:H,r in 1:R
            add(d["capacity_lower"][t][r]-used[t,r]-atol);add(used[t,r]-d["capacity_upper"][t][r]-atol)
        end
        for(a,b,season)in d["exclusions"]
            add(count(t->x[a]<=t<x[a]+d["duration"][a][x[a]] && x[b]<=t<x[b]+d["duration"][b][x[b]],season))
        end
    else
        error("Reference covers scheduling and maintenance resource terms")
    end
    terms
end
function reference_routing_terms!(terms,p,x;atol=1e-8)
    empty!(terms);d=p.data;f=p.family;n=length(x)÷2
    order=view(x,1:n);labels=view(x,n+1:2n)
    add(v)=push!(terms,Float64(max(0,v)))
    add(length(order)-length(unique(order)))
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
    terms
end

@testset "Concrete routing callbacks retain original term order and mutable data" begin
    rng=Xoshiro(721);reference=Float64[];terms=Float64[]
    for f in (:cvrp,:cvrptw,:top),wide in (false,true)
        p=deepcopy(CASES[f]);wide && (p.data["distance"]=BigFloat.(p.data["distance"]))
        ds=domains(p);workspace=ReproductionScoring.ScoreWorkspace(p)
        for _ in 1:128
            x=rand.(Ref(rng),ds)
            for atol in (0.,1e-8,big"0.125",1//8)
                expected=copy(reference_routing_terms!(reference,p,x;atol))
                @test isequal(residuals!(terms,p,x;atol,workspace),expected)
            end
        end
        p.data["distance"]=p.data["distance"].+0.25
        x=first.(ds);expected=copy(reference_routing_terms!(reference,p,x))
        @test isequal(residuals!(terms,p,x;workspace),expected)
    end
end

@testset "Owned scheduling/resource workspaces preserve ordered quantitative terms" begin
    rng=Xoshiro(731);models=Problem[deepcopy(CASES[f]) for f in (:rcpsp,:jssp,:fjsp,:maintenance)]
    n=64;duration=rand(rng,0:5,n);precedence=[[i,i+1] for i in 1:n-1]
    for f in (:rcpsp,:jssp,:fjsp)
        d=Dict{String,Any}("duration"=>duration,"precedence"=>precedence,"horizon"=>sum(duration))
        if f==:rcpsp;d["resource_use"]=rand(rng,n,3);d["capacity"]=[2.,3.,4.]
        elseif f==:jssp;d["machine"]=[mod1(i,7) for i in 1:n]
        else;d["alternatives"]=[[[mod1(i,7),duration[i]],[mod1(i+1,7),duration[i]+1]] for i in 1:n];end
        push!(models,problem(f,d))
    end
    for f in (:rcpsp,:jssp,:fjsp)
        p=deepcopy(CASES[f]);p.data["duration"]=BigInt.(p.data["duration"])
        f==:jssp && (p.data["machine"]=BigInt.(p.data["machine"]))
        f==:fjsp && (p.data["alternatives"]=[[BigInt.(choice) for choice in choices] for choices in p.data["alternatives"]])
        push!(models,p)
    end
    for p in models
        a=prepare_backend(:direct);b=prepare_backend(:direct);ds=domains(p);original=Float64[]
        for repetition in 1:128
            x=rand.(Ref(rng),ds)
            expected=copy(reference_resource_terms!(original,p,x))
            @test error_value(a,p,x)==sum(expected)
            @test isequal(a.residuals,expected)
            @test iszero(sum(expected))==validate(p,x).valid
            retained=copy(a.residuals)
            @test error_value(b,p,x)==error_value(a,p,x)
            @test isequal(retained,expected)
        end
        @test a.workspace!==b.workspace
        @test a.workspace.events!==b.workspace.events
        @test a.workspace.durations!==b.workspace.durations
        @test a.workspace.machines!==b.workspace.machines
        @test a.workspace.task_buffers!==b.workspace.task_buffers
        @test a.workspace.machine_groups!==b.workspace.machine_groups
        @test a.workspace.machine_keys!==b.workspace.machine_keys
        @test a.workspace.machine_cache!==b.workspace.machine_cache
        @test a.workspace.resource_load!==b.workspace.resource_load
        @test allunique(objectid(v) for v in a.workspace.task_buffers)
        # Same problem object with edited data must not reuse stale derived values.
        if p.family==:fjsp
            p.data["alternatives"][1][1][2]+=1
        elseif p.family==:maintenance
            p.data["resource_use_by_start"][1][1][1][1]+=.25
        else
            p.data["duration"][1]+=1
            p.family==:jssp && (p.data["machine"][1]=11)
        end
        x=first.(ds);expected=copy(reference_resource_terms!(original,p,x))
        @test error_value(a,p,x)==sum(expected)
        @test isequal(a.residuals,expected)
        @test error_value(a,p,fill(NaN,length(ds)))==1.
        @test error_value(a,p,x)==sum(expected)
    end
    for f in (:rcpsp,:jssp,:fjsp,:maintenance)
        p=CASES[f];x=first.(domains(p));b=prepare_backend(:direct);original=Float64[]
        function allocated_resource_terms(backend,p,x,original)
            error_value(backend,p,x);reference_resource_terms!(original,p,x)
            optimized=@allocated for _ in 1:1024;error_value(backend,p,x);end
            reference=@allocated for _ in 1:1024;reference_resource_terms!(original,p,x);sum(original);end
            (;optimized,reference)
        end
        allocated_resource_terms(b,p,x,original)
        bytes=allocated_resource_terms(b,p,x,original)
        @test bytes.optimized<bytes.reference
    end
end
@testset "Machine map reuse preserves fresh-map term order after data changes" begin
    n=48;rng=Xoshiro(911)
    p=problem(:jssp,Dict{String,Any}("duration"=>ones(Int,n),
        "precedence"=>Vector{Int}[],"horizon"=>3n,"machine"=>[mod1(i,12) for i in 1:n]))
    backend=prepare_backend(:direct);original=Float64[];x=rand(rng,0:8,n)
    error_value(backend,p,x);first_map=backend.workspace.machine_groups
    for _ in 1:16
        rand!(rng,x,0:8)
        expected=copy(reference_resource_terms!(original,p,x))
        @test error_value(backend,p,x)==sum(expected)
        @test isequal(backend.residuals,expected)
        @test backend.workspace.machine_groups===first_map
    end
    for group_count in (24,1,7,0,12,48,2,12)
        for i in 1:n
            p.data["duration"][i]=group_count==0 || i%5==0 ? 0 : 1+i%3
            p.data["machine"][i]=group_count==0 ? 1 : mod1(n+1-i,group_count)
        end
        expected=copy(reference_resource_terms!(original,p,x))
        @test error_value(backend,p,x)==sum(expected)
        @test isequal(backend.residuals,expected)
        @test allunique(objectid(v) for v in values(backend.workspace.machine_groups))
        @test length(backend.workspace.machine_cache)<=8
        @test allunique(first(entry) for entry in backend.workspace.machine_cache)
        retained_map=backend.workspace.machine_groups
        @test error_value(backend,p,x)==sum(expected)
        @test backend.workspace.machine_groups===retained_map
    end
    p=CASES[:fjsp];backend=prepare_backend(:direct);inputs=([0,2,1,1],[1,1,2,2],[2,0,1,2])
    for x in inputs;error_value(backend,p,x);end
    for _ in 1:32,x in inputs
        expected=copy(reference_resource_terms!(original,p,x))
        @test error_value(backend,p,x)==sum(expected)
        @test isequal(backend.residuals,expected)
    end
    @test length(backend.workspace.machine_cache)<=8
end
@testset "Owned tolerance storage retains custom arithmetic and consecutive calls" begin
    p=deepcopy(CASES[:bpp]);p.data["weights"]=Float64.(p.data["weights"]);p.data["weights"][1,1]=4.125
    x=[1,2,3];workspace=ReproductionScoring.ScoreWorkspace(p);terms=Float64[]
    for atol in (0.,1e-8,.125,big"0.125",1//8,0.)
        expected=Float64[]
        for label in unique(x),r in axes(p.data["weights"],2)
            load=0.0
            for i in eachindex(x);x[i]==label && (load+=p.data["weights"][i,r]);end
            push!(expected,max(0.,load-p.data["capacity"][r]-atol))
        end
        @test isequal(residuals!(terms,p,x;atol,workspace),expected)
    end
    p=CASES[:maintenance];x=[1,1];workspace=ReproductionScoring.ScoreWorkspace(p);reference=Float64[]
    for atol in (0.,1e-5,.125,big"0.125",1//8,0.)
        expected=copy(reference_resource_terms!(reference,p,x;atol))
        @test isequal(residuals!(terms,p,x;atol,workspace),expected)
    end
end
@testset "Original validators and quantitative/ICN zero sets" begin
    @test Set(keys(CASES))==Set(FAMILY_IDS)
    backends=[prepare_backend(k) for k in (:naive,:direct,:icn,:icn_fused)]
    for (f,p) in CASES
        ds=domains(p);@test !validate(p,[first(r) for r in ds[1:end-1]]).valid
        @test !validate(p,fill(NaN,length(ds))).valid
        @test !validate(p,[last(r)+1 for r in ds]).valid
        @test !validate(p,[first(r)+.5 for r in ds]).valid
        @test prod(length.(ds))<=10_000
        for tuple in Iterators.product(ds...)
            x=collect(tuple);checked=validate(p,x)
            direct=Base.invokelatest(error_value,backends[2],p,x)
            @test iszero(direct)==checked.valid
            @test Base.invokelatest(search_objective_value,backends[2],p,x)≈ReproductionScoring.objective_value(p,x)
            for b in backends
                e=Base.invokelatest(error_value,b,p,x)
                @test isfinite(e) && e>=0 && iszero(e)==checked.valid
                b.kind in (:icn,:icn_fused) && @test e≈direct
            end
        end
    end
    @test validate(CASES[:qap],[1,2]).objective==(big(14),)
    @test validate(CASES[:mssc],[1,1,2]).objective[1]≈2.
    @test validate(CASES[:tsp],[1,2,3]).objective==(4.,)
    @test validate(CASES[:top],[1,2,1,1]).objective==(-9.,)
    @test validate(CASES[:maintenance],[1,2]).objective[1]≈1.25
    @test search_objective_value(backends[2],CASES[:bpp],[NaN,1,2])==Inf
    @test search_objective_value(backends[2],CASES[:bpp],[1,1])==Inf
    @test !validate(CASES[:maintenance],[1,1]).valid
    @test_throws ArgumentError problem(:jssp,Dict("duration"=>[1,1],"machine"=>[1,2],"precedence"=>[[1,2],[2,1]],"horizon"=>2))
    @test_throws ArgumentError problem(:qap,Dict("flow"=>[[1]],"distance"=>[[0,1],[1,0]]))
end
@testset "Prepared classical callback paths retain zero warm allocations" begin
    function callback_allocations(backend,p,x)
        error_value(backend,p,x)
        @allocated for _ in 1:1024;error_value(backend,p,x);end
    end
    for f in (:rcpsp,:jssp,:fjsp,:maintenance,:cvrp,:cvrptw,:bpp,:salbp,:aircraft_landing),kind in (:direct,:icn_fused)
        p=CASES[f];x=first.(domains(p));backend=prepare_backend(kind)
        Base.invokelatest(callback_allocations,backend,p,x)
        @test Base.invokelatest(callback_allocations,backend,p,x)==0
    end
end
@testset "Packing callback buffers reduce allocation pressure" begin
    p=CASES[:bpp];a=prepare_backend(:direct);b=prepare_backend(:direct);x=[1,2,3]
    error_value(a,p,x);error_value(b,p,x)
    @test a.workspace!==b.workspace && a.workspace.integers!==b.workspace.integers
    function objective_allocations(backend,p,x)
        search_objective_value(backend,p,x);ReproductionScoring.objective_value(p,x)
        optimized=@allocated for _ in 1:1024;search_objective_value(backend,p,x);end
        oracle=@allocated for _ in 1:1024;ReproductionScoring.objective_value(p,x);end
        (;optimized,oracle)
    end
    objective_allocations(a,p,x)
    bytes=objective_allocations(a,p,x)
    @test bytes.optimized<bytes.oracle÷8
    icn=prepare_backend(:icn);fused=prepare_backend(:icn_fused)
    @test icn.decoder===fused.decoder
    @test icn.input!==fused.input && icn.residuals!==fused.residuals
    clones=Vector{Any}(undef,Threads.nthreads())
    Threads.@threads :static for i in eachindex(clones)
        clones[i]=prepare_backend(:icn_fused)
        for _ in 1:100;Base.invokelatest(error_value,clones[i],p,i%2==0 ? [1,1,1] : x);end
    end
    @test all(b->b.decoder===icn.decoder && b.calls==100,clones)
    @test allunique(objectid(b.input) for b in clones)
    mktemp() do path,io
        original=joinpath(@__DIR__,"../../LiLim/resources/icn-pdptw-witnesses.toml")
        row=TOML.parsefile(original);row["witnesses"][4]["schema_sha256"]="invalid"
        TOML.print(io,row);close(io)
        @test_throws ErrorException prepare_backend(:icn;bank=path)
        @test prepare_backend(:icn).decoder===icn.decoder
    end
end
@testset "Original reader boundaries and metrics" begin
    mktempdir() do d
        path=joinpath(d,"original")
        write(path,"NAME: triangle\nTYPE: TSP\nDIMENSION: 3\nEDGE_WEIGHT_TYPE: EUC_2D\nNODE_COORD_SECTION\n1 0 0\n2 3 0\n3 3 4\nEOF\n")
        p=read_problem(path;family=:tsp);@test validate(p,[1,2,3]).objective==(12.,)
        for (metric,cost) in ((:EUC_2D,5.),(:CEIL_2D,5.),(:MAN_2D,7.),(:MAX_2D,4.),(:ATT,2.),(:euclidean,5.))
            @test CoordinateDistances([0. 0.;3. 4.],metric)[1,2]==cost
        end
        @test CoordinateDistances([0. 0. 0.;1. 2. 3.],:MAN_3D)[1,2]==6
        @test CoordinateDistances([16.47 96.10;16.47 94.44],:GEO)[1,2]==153
        write(path,"2\n0 3 4 0\n0 2 2 0\n");@test validate(read_problem(path;family=:qap),[1,2]).objective==(big(14),)
        write(path,"3\n4\n2 2 3\n");@test validate(read_problem(path;family=:bpp),[1,1,2]).valid
        write(path,"2\n4 4\n3\n1 3\n3 1\n2 2\n3\n");@test validate(read_problem(path;family=:vbp),[1,1,2]).valid
        write(path,"n 4\nm 1\ntmax 4\n0 0 0\n1 0 4\n2 0 5\n3 0 0\n");@test validate(read_problem(path;family=:top),[1,2,1,1]).objective==(-9.,)
        write(path,"3 1 2 1 2 1\n1 2 1\n1 2 1\n2 1 0\n0 0 1\n")
        p=read_problem(path;family=:car_sequencing);@test validate(p,[1,2]).valid;@test p.data["history"]==[3]
        write(path,"2 1\n1 2 1 1 3 1\n1 1 1 2\n")
        @test_throws Exception read_problem(path;family=:fjsp)
        @test_throws ArgumentError read_problem(path;family=:irp)
    end
end
@testset "CBLS front end and existing strategies execute bounded steps" begin
    for (f,p) in CASES
        lane=prepare_cbls(p;kind=:direct)
        result=Base.invokelatest(search!,lane;seconds=.01,max_steps=1)
        @test result["steps"]<=1
        @test all(row->validate(p,row["values"]).valid,result["trajectory"])
    end
    for policy in POLICIES
        lane=prepare_cbls(CASES[:bpp];policy,kind=:icn_fused)
        result=Base.invokelatest(search!,lane;seconds=.01,max_steps=1)
        @test result["policy"]["id"]==policy
    end
    # Real MetaStrategist API with a single lane also qualifies 1-thread hosts.
    result=portfolio(CASES[:bpp];seconds=.01,max_steps=1,workers=[(;kind=:icn_fused,policy="late_400")])
    @test length(result)==1
end
@testset "Optional exact HiGHS formulations" begin
    import HiGHS
    for f in (:bpp,:bppc,:vbp,:rcpsp,:jssp,:fjsp,:salbp,:aircraft_landing)
        p=CASES[f];r=solve_mip(p,HiGHS.Optimizer;seconds=1.)
        @test !isempty(r.values) && validate(p,r.values).valid
        optimum=minimum(validate(p,collect(x)).objective[1] for x in Iterators.product(domains(p)...) if validate(p,collect(x)).valid)
        @test validate(p,r.values).objective[1]≈optimum
        @test r.bound<=optimum+1e-6
    end
    @test_throws ArgumentError mip_model(CASES[:rcpsp];max_cells=1)
end
