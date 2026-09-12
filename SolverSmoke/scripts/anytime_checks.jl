include("activate.jl")
using Test,TOML,Random,Dates,COPInstances
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
out=datadir("anytime-checks");mkpath(out);input=fixtures(out);d=read_routes(input)
function permutations(f,a,k=1)
    if k>length(a);f(a);return;end
    for i in k:length(a)
        a[k],a[i]=a[i],a[k];permutations(f,a,k+1);a[k],a[i]=a[i],a[k]
    end
end
@testset "full fleet scoring, timing and validation" begin
    checked=Ref(0)
    permutations(collect(2:6)) do x
        e,c=evaluate(d,x);nodes=d.nodes
        p=Benchmarks.BenchmarkInstance("oracle",Benchmarks.PickupDeliveryProblem(2,2,nodes[:,2:3],Int.(nodes[:,4]),nodes[:,5],nodes[:,6],nodes[:,7],[(2,3),(4,5)]))
        v=Benchmarks.validate_solution(p,decode(d,x))
        @test iszero(e)==v.valid
        if v.valid;@test c≈v.objective.vehicles*d.big_m+v.objective.distance;end
        checked[]+=1
    end
    @test checked[]==120
    @test first(evaluate(d,[2,3,2,3,6]))>0
    t=Trace();t.solve_origin=time_ns()
    @sync for worker in 1:4
        Threads.@spawn for i in 100:-1:1;observe!(t,Float64(i),[worker]);end
    end
    @test t.best==1.
    @test all(diff([e["objective"] for e in t.events]).<0)
    @test issorted([e["elapsed_seconds"] for e in t.events])
    @test !isempty(t.events)
    save_trace(joinpath(out,"concurrency.toml"),t;solve_call_seconds=1.)
    valid=Trace();valid.solve_origin=time_ns();x=[2,3,4,5,6]
    observe!(valid,last(evaluate(d,x)),x)
    good=joinpath(out,"valid.toml");save_trace(good,valid;solve_call_seconds=1.,budget_seconds=1.)
    @test check_trace(input,good;require_solution=true)["within_budget_feasible"]
    bad=TOML.parsefile(good);bad["events"][1]["values"]=[3,2,4,5,6]
    broken=joinpath(out,"broken.toml")
    open(io->TOML.print(io,bad),broken,"w")
    @test_throws ErrorException check_trace(input,broken)
    late=TOML.parsefile(good);late["events"][1]["solve_seconds"]=.8;late["budget_seconds"]=.5
    open(io->TOML.print(io,late),broken,"w")
    @test !check_trace(input,broken)["within_budget_feasible"]
    validparse(x)=!(x isa Expr) || (!(x.head in (:error,:incomplete)) && all(validparse,x.args))
    for path in [joinpath(dir,f) for folder in ("scripts","src") for (dir,_,fs) in walkdir(projectdir(folder)) for f in fs if endswith(f,".jl")]
        @test validparse(Meta.parseall(read(path,String)))
    end
end
registry=COPInstances.li_lim_registry()
@testset "unreduced historical routes" begin
    for id in ("lc101","lr101","lrc101")
        dir=projectdir("..","LiLim","data","sims","f6c75ba8-3020-498d-b88d-541808a99667",id)
        if isfile(joinpath(dir,"result.toml"))
            result=TOML.parsefile(joinpath(dir,"result.toml"));p=Benchmarks.read_benchmark(joinpath(dir,"instance.txt"),:li_lim)
            input=joinpath(out,id*"-full.txt");write_input(input,p);full=read_routes(input)
            values=Int[];separator=length(p.data.demand)+1
            for route in result["routes_source_node_ids"]
                append!(values,route.+1);push!(values,separator);separator+=1
            end
            append!(values,separator:length(p.data.demand)+p.data.vehicles-1)
            @test first(evaluate(full,values))==0
            @test last(evaluate(full,values))≈result["vehicles"]*full.big_m+result["distance"]
            @test Benchmarks.validate_solution(p,decode(full,values)).valid
        end
    end
end
println("REGISTRY_TYPE=",typeof(registry)," FIELDS=",fieldnames(typeof(registry)))
println("FIXTURE=",input)
open(io->TOML.print(io,Dict("completed_utc"=>string(now(UTC)),"threads"=>Threads.nthreads(),"affinity"=>string(COMPARISON_AFFINITY;base=16),"exhaustive_permutations"=>120)),joinpath(out,"checks.toml"),"w")
