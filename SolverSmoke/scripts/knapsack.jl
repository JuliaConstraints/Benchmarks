include("activate.jl")
using JuMP, CBLS, GHOST, LocalSearchSolvers, HiGHS, Random, TOML, SHA, Dates
const LS=LocalSearchSolvers
import MathOptInterface as MOI
const weights=[12,7,11,8,9,6,13,5,14,10,3,4]
const profits=[24,13,23,15,16,11,28,9,30,19,5,8]
const capacity=40
const oracle=maximum(sum(profits[i] for i in eachindex(weights) if (mask>>(i-1))&1==1;init=0)
    for mask in 0:(1<<length(weights))-1 if sum(weights[i] for i in eachindex(weights) if (mask>>(i-1))&1==1;init=0)<=capacity)
function lsoptions(seconds)
    LS.Options(iteration=(false,typemax(Int)),time_limit=(false,seconds),process_threads_map=Dict(1=>4),
        print_level=:silent,log_mode=:silent,log_to_file=false,progress_mode=:none,use_progress_meter=false)
end
function solveone(engine,seconds,seed)
    Random.seed!(seed)
    n=length(weights); start=time_ns()
    if engine=="lss_native"
        m=LS.model()
        for _ in 1:n; LS.variable!(m,LS.domain(0:1)); end
        LS.constraint!(m,(v;X=nothing)->max(0.0,sum(weights.*v)-capacity),1:n)
        LS.objective!(m,(v;X=nothing)->sum(profits[i]*v[i] for i in 1:n)); LS.sense!(m,Val(:max))
        s=LS.solver(m;options=lsoptions(seconds))
        build=(time_ns()-start)/1e9
        elapsed=@elapsed LS.solve!(s)
        x=round.(Int,collect(LS.best_values(s))); status=string(LS.status(s))
    elseif engine=="ghost_native_c"
        c=GHOST.CAPI; s=c.create_session(false); o=c.create_options()
        try
            ids=Cint[c.add_variable(s,0,1,"x$i") for i in 1:n]
            c.add_linear_le(s,ids,Float64.(weights),Float64(capacity))
            c.set_linear_objective(s,true,ids,Float64.(profits),0.0)
            c.set_parallel(o,true); c.set_num_threads(o,4)
            build=(time_ns()-start)/1e9
            elapsed=@elapsed c.solve(s,o,seconds*1e6)
            x=c.variable_values(s,n); status=string(c.solution_status(s))
        finally
            c.destroy_options(o); c.destroy_session(s)
        end
    else
        factory=engine=="cbls_jump" ? (() -> CBLS.Optimizer(;options=lsoptions(seconds))) :
            engine=="ghost_jump" ? (() -> GHOST.Optimizer(time_limit=seconds,number_threads=4)) : HiGHS.Optimizer
        m=Model(factory);set_silent(m);set_time_limit_sec(m,seconds)
        if engine=="highs_control"
            set_attribute(m,"threads",4);set_attribute(m,"random_seed",seed)
        end
        @variable(m,xv[1:n],Bin)
        @constraint(m,sum(weights.*xv)<=capacity)
        @objective(m,Max,sum(profits.*xv))
        build=(time_ns()-start)/1e9
        elapsed=@elapsed optimize!(m)
        status=string(termination_status(m))
        has_values(m) || error("No feasible incumbent: $engine $status")
        x=round.(Int,value.(xv))
    end
    valid=length(x)==n && all(in(0:1),x) && sum(weights.*x)<=capacity
    objective=sum(profits.*x)
    valid || error("Independent knapsack validation failed: $engine $x")
    objective<=oracle || error("Oracle disagreement")
    Dict("engine"=>engine,"seed"=>seed,"validated"=>valid,"objective"=>objective,
        "oracle"=>oracle,"gap"=>oracle-objective,"values"=>x,"status"=>status,
        "build_seconds"=>build,"solve_call_seconds"=>elapsed,"budget_seconds"=>seconds,
        "threads"=>4,"seed_controlled"=>!startswith(engine,"ghost"))
end
out=isempty(ARGS) ? datadir("knapsack-"*Dates.format(now(),"yyyymmdd-HHMMSS")) : abspath(ARGS[1]);mkpath(out)
println("RESULT_DIR=",out);flush(stdout)
write(joinpath(out,"juls-instance.txt"),"$(length(weights)) $capacity\n"*join(["$(profits[i]) $(weights[i])" for i in eachindex(weights)],"\n")*"\n")
write(joinpath(out,"timefold-instance.txt"),"$(length(weights)) $capacity\n"*join(["$(weights[i]) $(profits[i])" for i in eachindex(weights)],"\n")*"\n")
for engine in get(ENV,"SMOKE_ENGINES","cbls_jump,lss_native,ghost_jump,ghost_native_c,highs_control") |> x->split(x,',') .|> String
    try
        warmup=solveone(engine,0.25,0)
        for seed in 1:3
            result=solveone(engine,2.0,seed)
            open(io->TOML.print(io,result;sorted=true),joinpath(out,"$engine-$seed.toml"),"w")
            println(engine," seed=",seed," objective=",result["objective"],"/",oracle," call=",result["solve_call_seconds"]);flush(stdout)
        end
    catch e
        err=sprint(showerror,e,catch_backtrace())
        open(io->TOML.print(io,Dict("engine"=>engine,"error"=>err)),joinpath(out,"$engine-error.toml"),"w")
        println(engine," FAILED: ",err);flush(stdout)
    end
end
