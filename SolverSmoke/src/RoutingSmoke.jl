module RoutingSmoke
using SHA, TOML
include(joinpath(@__DIR__,"..","vendor","formulations","Benchmarks.jl"))
using .Benchmarks
export fixture, error_cost, validate, oracle, export_fixture
function fixture()
    source=get(ENV,"LILIM_SMOKE_SOURCE",abspath(@__DIR__,"..","..","LiLim","data","sims","f6c75ba8-3020-498d-b88d-541808a99667","lc101","instance.txt"))
    isfile(source) || error("Set LILIM_SMOKE_SOURCE to a downloaded original lc101 file; raw data are opt-in.")
    full=read_benchmark(source,:li_lim);d=full.data
    route=[5,3,7,8,10,11,9,6,4,2,1,75].+1
    pairs=filter(p->p[1] in route && p[2] in route,d.pairs)[1:3]
    ids=[1;sort([i for pair in pairs for i in pair])]
    reduced=PickupDeliveryProblem(1,d.capacity,d.coordinates[ids,:],d.demand[ids],d.earliest[ids],d.latest[ids],d.service[ids],
        [(findfirst(==(p),ids),findfirst(==(q),ids)) for (p,q) in pairs])
    p=BenchmarkInstance("lc101-three-pairs-one-vehicle",reduced;
        provenance=Dict("source_sha256"=>bytes2hex(sha256(read(source))),"source_node_ids"=>ids.-1,
            "scope"=>"Reduced smoke fixture; three complete pairs from one known feasible route; fleet fixed to one"))
    return p
end
function error_cost(p,route)
    d=p.data;error=length(route)-length(unique(route));cost=0.;clock=d.earliest[1];load=0;previous=1
    seen=Set{Int}()
    for i in route
        travel=hypot(d.coordinates[i,1]-d.coordinates[previous,1],d.coordinates[i,2]-d.coordinates[previous,2]);cost+=travel
        clock=max(d.earliest[i],clock+d.service[previous]+travel);error+=max(0,clock-d.latest[i])
        load+=d.demand[i];error+=max(0,-load)+max(0,load-d.capacity)
        for (pickup,delivery) in d.pairs
            i==delivery && !(pickup in seen) && (error+=1)
        end
        push!(seen,i);previous=i
    end
    travel=hypot(d.coordinates[previous,1]-d.coordinates[1,1],d.coordinates[previous,2]-d.coordinates[1,2]);cost+=travel
    error+=max(0,clock+d.service[previous]+travel-d.latest[1])+abs(load)
    return Float64(error),cost
end
validate(p,route)=Benchmarks.validate_solution(p,[route])
function oracle(p)
    best=Inf;feasible=0;checked=0
    function visit!(route,remaining)
        if isempty(remaining)
            checked+=1
            result=validate(p,route)
            violation,cost=error_cost(p,route)
            (violation<=1e-8)==result.valid || error("Scorer disagrees with independent validator")
            if result.valid
                feasible+=1;best=min(best,result.objective.distance)
                isapprox(cost,result.objective.distance;atol=1e-8) || error("Distance mismatch")
            end
        else
            for i in remaining; visit!([route;i],filter(!=(i),remaining));end
        end
    end
    visit!(Int[],collect(2:length(p.data.demand)))
    return Dict("distance"=>best,"feasible_permutations"=>feasible,"checked_permutations"=>checked)
end
function export_fixture(p,out)
    mkpath(out);d=p.data
    open(joinpath(out,"instance.txt"),"w") do io
        println(io,length(d.demand)," ",d.capacity)
        for i in eachindex(d.demand)
            pickup=last([0;[a for (a,b) in d.pairs if b==i]])
            println(io,join((i,d.coordinates[i,1],d.coordinates[i,2],d.demand[i],d.earliest[i],d.latest[i],d.service[i],pickup)," "))
        end
    end
    open(io->TOML.print(io,p.provenance;sorted=true),joinpath(out,"provenance.toml"),"w")
    open(io->TOML.print(io,oracle(p);sorted=true),joinpath(out,"oracle.toml"),"w")
end
end
