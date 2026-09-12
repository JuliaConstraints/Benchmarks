include("activate.jl")
using JuMP,CBLS,LocalSearchSolvers,Random,TOML
include("../src/Anytime.jl");using .Anytime
include("../src/Profiles.jl");using .Profiles
const LS=LocalSearchSolvers
function solve_case(input,engine,id,seconds,seed)
    Random.seed!(seed);trace=Trace();d=read_routes(input);n=size(d.nodes,1)+d.fleet-2
    workers=Threads.nthreads()
    workers in (1,2,4) || error("Expected 1, 2 or 4 search workers")
    opts=LS.Options(iteration=(false,typemax(Int)),time_limit=(false,seconds),process_threads_map=Dict(1=>workers),
        dynamic=false,print_level=:silent,log_mode=:silent,log_to_file=false,progress_mode=:none,use_progress_meter=false)
    if engine=="lss_native"
        m=LS.model()
        for _ in 1:n;LS.variable!(m,LS.domain(2:n+1));end
        LS.constraint!(m,(v;X=nothing)->first(evaluate(d,Int.(v))),1:n)
        LS.objective!(m,(v;X=nothing)->last(evaluate(d,[Int(v[i]) for i in 1:n])))
        s=LS.solver(m;options=opts,strategies=profile(m,id))
        runsolve=()->LS.solve!(s)
    else
        m=Model(()->CBLS.Optimizer(;options=opts));set_silent(m)
        @variable(m,2<=x[1:n]<=n+1,Int)
        @constraint(m,x in CBLS.Error(v->first(evaluate(d,Int.(v)))))
        @objective(m,Min,CBLS.ScalarFunction(v->last(evaluate(d,Int.(v)))))
        # Force the JuMP cache to attach before setting the copied strategy.
        MOI=JuMP.MOI;MOI.Utilities.attach_optimizer(JuMP.backend(m))
        backend=unsafe_backend(m);backend.solver.strategies=profile(backend.solver.model,id)
        runsolve=()->optimize!(m)
    end
    LS.BENCHMARK_INCUMBENT_OBSERVER[]=(objective,values)->observe!(trace,objective,collect(values))
    trace.solve_origin=time_ns();build=(trace.solve_origin-trace.origin)/1e9
    try
        runsolve()
    finally
        LS.BENCHMARK_INCUMBENT_OBSERVER[]=nothing
    end
    elapsed=(time_ns()-trace.solve_origin)/1e9
    trace,Dict("engine"=>engine,"profile"=>id,"budget_seconds"=>seconds,"seed"=>seed,
        "build_seconds"=>build,"solve_call_seconds"=>elapsed,"threads"=>workers,"parallelism"=>"cooperating search workers","seed_controlled"=>true,
        "warmup_solves"=>2,"warmup_budget_seconds"=>2.,
        "objective_encoding"=>"fleet * certified_distance_bound + distance","big_m"=>d.big_m)
end
jobs=length(ARGS)==1 ? TOML.parsefile(only(ARGS))["jobs"] :
    [Dict(zip(["input","engine","profile","budget","seed","out"],ARGS))]
warmed=Set{Tuple{String,String}}()
for job in jobs
    input,engine,id,out=job["input"],job["engine"],job["profile"],job["out"]
    if !((engine,id) in warmed)
        # A short deadline can expire during compilation before the first move.
        # Warm twice long enough to exercise feasible admission and search paths.
        for _ in 1:2;solve_case(ENV["ANYTIME_WARMUP_INPUT"],engine,id,2.,0);end
        push!(warmed,(engine,id))
    end
    t,metadata=solve_case(input,engine,id,parse(Float64,string(job["budget"])),parse(Int,string(job["seed"])))
    save_trace(out,t;[Symbol(k)=>v for (k,v) in metadata]...)
    println("RESULT=",out," EVENTS=",length(t.events));flush(stdout)
end
