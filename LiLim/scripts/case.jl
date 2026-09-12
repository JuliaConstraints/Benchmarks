include("activate.jl")
using COPInstances, Dates, SHA, TOML, JuMP
include(projectdir("vendor","formulations","Benchmarks.jl"))
include(srcdir("Pilot.jl"))
using .Benchmarks
length(ARGS)==2 || error("usage: case.jl lc101|lr101|lrc101 output-directory")
id,output=ARGS
id in ("lc101","lr101","lrc101") || error("instance outside pilot")
isdir(output) || error("supervisor must create output directory")
function save_record(name,record)
    path=joinpath(output,name*".toml")
    ispath(path) && error("refusing to overwrite $path")
    tmp=path*".partial"
    open(io->TOML.print(io,record;sorted=true),tmp,"w")
    mv(tmp,path)
end
save_record("started",Dict("id"=>id,"pid"=>getpid(),"started_utc"=>string(now(UTC)),
    "cpus"=>COMPARISON_CPUS,"affinity"=>string(COMPARISON_AFFINITY;base=16),
    "solver_threads"=>length(COMPARISON_CPUS),"julia_threads"=>Threads.nthreads(),
    "julia"=>string(VERSION),"seconds_per_solver"=>30.0,"seed"=>1))
try
    data=download_dataset(:li_lim;ids=[id],cache=datadir("raw"),
        downloader=(url,target)->COPInstances.Downloads.download(url,target;timeout=30))
    spec=only(instances(data.registry)); path=data.paths[spec.id]
    bytes2hex(sha256(read(path)))==spec.sha256 || error("source digest mismatch")
    cp(path,joinpath(output,"instance.txt"))
    p=read_benchmark(path,:li_lim;id=id)
    # Tiny warmup is not included in the reference construction timer.
    warm=BenchmarkInstance("warmup",PickupDeliveryProblem(1,1,zeros(3,2),[0,1,-1],zeros(3),fill(10.,3),zeros(3),[(2,3)]))
    Pilot.insertion(warm;starts=1)
    start=time_ns(); routes=Pilot.insertion(p;starts=5,seed=1); baseline_seconds=(time_ns()-start)/1e9
    baseline=Dict{String,Any}("solver"=>"Julia pair-insertion reference (not CBLS)","starts"=>5,
        "seconds"=>baseline_seconds,"accepted"=>routes!==nothing)
    if routes!==nothing
        v=validate_solution(p,routes)
        merge!(baseline,Dict("vehicles"=>v.objective.vehicles,"distance"=>v.objective.distance,
            "routes_source_node_ids"=>[r.-1 for r in routes]))
    end
    save_record("baseline",baseline)
    println(id," baseline: ",get(baseline,"vehicles","no solution")," vehicles; ",get(baseline,"distance","n/a"))
    start=time_ns(); f=Pilot.model(p;threads=length(COMPARISON_CPUS),seconds=30.,logpath=joinpath(output,"highs.log"))
    build_seconds=(time_ns()-start)/1e9
    routes===nothing || Pilot.warmstart!(f,routes)
    save_record("model",Dict("formulation"=>"pdptw_compact_route_labels_v1","variables"=>num_variables(f.m),
        "constraints"=>num_constraints(f.m;count_variable_in_set_constraints=true),"build_seconds"=>build_seconds,
        "full_source_fleet"=>p.data.vehicles,"requests"=>length(p.data.pairs),"source_sha256"=>spec.sha256,
        "source_url"=>spec.source,"warmstart"=>routes!==nothing,"distance"=>"euclidean_float64",
        "presolve"=>"default_on","parallel"=>"on"))
    println(id," solving ",num_variables(f.m)," variables with ",length(COMPARISON_CPUS)," solver threads")
    solution,phases,solve_seconds=Pilot.solve!(f;seconds=30.)
    result=Dict{String,Any}("id"=>id,"solver"=>"HiGHS through JuMP","solver_package_version"=>string(pkgversion(Pilot.HiGHS)),
        "accepted"=>solution!==nothing,"phases"=>phases,"solve_seconds"=>solve_seconds,
        "baseline"=>baseline,"fleet_optimal"=>first(phases)["status"]=="OPTIMAL")
    if solution!==nothing
        v=validate_solution(p,solution)
        merge!(result,Dict("vehicles"=>v.objective.vehicles,"distance"=>v.objective.distance,
            "routes_source_node_ids"=>[r.-1 for r in solution]))
    end
    save_record("result",result)
    save_record("completed",Dict("finished_utc"=>string(now(UTC)),"result_sha256"=>bytes2hex(sha256(read(joinpath(output,"result.toml"))))))
    println(id," completed: ",get(result,"vehicles","no validated incumbent")," vehicles; phases ",phases)
catch err
    save_record("failed",Dict("finished_utc"=>string(now(UTC)),"error"=>sprint(showerror,err)))
    rethrow()
end
