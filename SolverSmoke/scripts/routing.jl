include("activate.jl")
using JuMP, CBLS, LocalSearchSolvers, Random, TOML, Dates
import MathOptInterface as MOI
include(joinpath(@__DIR__,"..","src","RoutingSmoke.jl"))
using .RoutingSmoke
const LS=LocalSearchSolvers
const p=fixture()
const optimum=oracle(p)
function solveone(seconds,seed)
    Random.seed!(seed);start=time_ns()
    options=LS.Options(iteration=(false,typemax(Int)),time_limit=(false,seconds),process_threads_map=Dict(1=>4),
        print_level=:silent,log_mode=:silent,log_to_file=false,progress_mode=:none,use_progress_meter=false)
    m=Model(()->CBLS.Optimizer(;options));set_silent(m)
    n=length(p.data.demand)-1
    @variable(m,2<=x[1:n]<=n+1,Int)
    # Explicit permutation error and full-route feasibility error.
    @constraint(m,x in CBLS.Error(v->n-length(unique(v))))
    @constraint(m,x in CBLS.Error(v->first(error_cost(p,Int.(v)))))
    @objective(m,Min,CBLS.ScalarFunction(v->last(error_cost(p,Int.(v)))))
    build=(time_ns()-start)/1e9
    elapsed=@elapsed optimize!(m)
    has_values(m) || error("CBLS found no feasible route: $(termination_status(m))")
    route=round.(Int,value.(x));result=validate(p,route)
    result.valid || error("Independent route validation failed: $(result.errors)")
    return Dict("engine"=>"cbls_jump","route"=>route,"validated"=>true,"seed"=>seed,"distance"=>result.objective.distance,
        "gap"=>result.objective.distance-optimum["distance"],"solve_call_seconds"=>elapsed,"build_seconds"=>build,
        "budget_seconds"=>seconds,"threads"=>4,"status"=>string(termination_status(m)))
end
out=isempty(ARGS) ? datadir("routing-"*Dates.format(now(),"yyyymmdd-HHMMSS")) : abspath(ARGS[1]);mkpath(out)
export_fixture(p,out);println("RESULT_DIR=",out);flush(stdout)
try
    solveone(0.25,0)
catch e
    println("Warm-up: ",sprint(showerror,e));flush(stdout)
end
for seed in 1:3
    result=solveone(2.0,seed)
    open(io->TOML.print(io,result;sorted=true),joinpath(out,"cbls_jump-$seed.toml"),"w")
    println(result);flush(stdout)
end
