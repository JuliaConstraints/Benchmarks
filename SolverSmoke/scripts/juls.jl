include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using JuLS, Random, TOML, Dates
out=abspath(ARGS[1]);mkpath(out)
input=joinpath(out,"juls-instance.txt")
function solveone(seconds,seed)
    Random.seed!(seed);e=JuLS.KnapsackExperiment(input)
    start=time_ns();m=JuLS.init_model(e);build=(time_ns()-start)/1e9
    elapsed=@elapsed JuLS.optimize!(m;limit=JuLS.TimeLimit(seconds),rng=Xoshiro(seed))
    isnothing(m.best_solution) && error("No feasible JuLS incumbent")
    x=Int[v.value for v in m.best_solution.values]
    valid=length(x)==e.n_items && all(in(0:1),x) && sum(e.weights.*x)<=e.capacity
    valid || error("JuLS incumbent failed independent validation")
    Dict("engine"=>"juls_native","seed"=>seed,"validated"=>true,"objective"=>sum(e.values.*x),"values"=>x,
        "solve_call_seconds"=>elapsed,"build_seconds"=>build,"budget_seconds"=>seconds,"julia_version"=>string(VERSION),
        "initialization"=>"upstream default GreedyInitialization","neighborhood"=>"upstream default ExhaustiveNeighbourhood(2,n)",
        "selection"=>"upstream default GreedyMoveSelection","using_cp"=>true,"threads"=>Threads.nthreads())
end
solveone(0.25,0)
for seed in 1:3
    result=solveone(2.,seed)
    open(io->TOML.print(io,result;sorted=true),joinpath(out,"juls_native-$seed.toml"),"w")
    println(result);flush(stdout)
end
