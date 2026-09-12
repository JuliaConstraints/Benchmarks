module PackageBenchmarks
using BenchmarkTools, Random
import ConstraintCommons as CC
import ConstraintDomains as CD
import PatternFolds as PF
import Intervals

struct Case{P,F,V}
    id::String
    family::String
    prepare::P
    operation::F
    validate::V
    scope::String
end
case(id, family, prepare, operation, validate; scope="operation only; fresh input setup excluded") =
    Case(id, family, prepare, operation, validate, scope)

"""Deterministic inputs; setup and validation are outside measured expressions."""
function cases(seed::Int)
    word = [0, 1, 1, 0, 1, 0]
    states = Dict((:a,0)=>:a, (:a,1)=>:b, (:b,1)=>:c,
        (:c,0)=>:d, (:d,0)=>:d, (:d,1)=>:e, (:e,0)=>:e)
    transitions = [Dict((:r,0)=>:n1, (:r,1)=>:n2, (:r,2)=>:n3),
        Dict((:n1,2)=>:n4, (:n2,2)=>:n4, (:n3,0)=>:n5),
        Dict((:n4,0)=>:t, (:n5,0)=>:t)]
    vectorfold() = PF.make_vector_fold([0, 1], 2, 32)
    return [
        case("commons.automaton", "ConstraintCommons",
            () -> (CC.Automaton(copy(states), :a, :e), copy(word)),
            x -> CC.accept(x[1], x[2]), x -> x === true),
        case("commons.mdd", "ConstraintCommons", () -> CC.MDD(deepcopy(transitions)),
            a -> (CC.accept(a, [0,2,0]), CC.accept(a, [2,1,2])), x -> x == (true,false)),
        case("commons.dictionary", "ConstraintCommons", () -> Dict{Int,Int}(),
            d -> (CC.incsert!(d, 23); CC.incsert!(d, 23); CC.incsert!(d, 42, 42); d),
            d -> d == Dict(23=>2, 42=>42)),
        case("commons.extrema", "ConstraintCommons", () -> [-8, 2, 13, 0, 7],
            CC.δ_extrema, x -> x == 21),
        case("domains.empty", "ConstraintDomains", () -> nothing,
            _ -> isempty(CD.domain()), x -> x === true; scope="empty domain construction and query"),
        case("domains.continuous", "ConstraintDomains",
            () -> CD.domain(Intervals.Interval{Intervals.Closed,Intervals.Closed}(1.0, 3.15)),
            d -> (2.3 in d, 5.1 in d), x -> x == (true,false)),
        case("domains.discrete", "ConstraintDomains", () -> CD.domain([4,3,2,1]),
            d -> (2 in d, 42 in d, length(d)), x -> x == (true,false,4)),
        case("domains.mutation", "ConstraintDomains", () -> CD.domain([1,2,3,4]),
            d -> (CD.add!(d, 5); delete!(d, 1); (1 in d, 5 in d, length(d))),
            x -> x == (false,true,4)),
        case("domains.explore", "ConstraintDomains", () -> [CD.domain(1:4) for _ in 1:4],
            ds -> CD.explore(ds, allunique), x -> length(x[1]) == 24 && length(x[2]) == 232),
        case("folds.construct", "PatternFolds", () -> [0,1],
            x -> PF.make_vector_fold(x, 2, 32), x -> collect(x) == collect(0:63);
            scope="fold construction; input vector setup excluded"),
        case("folds.collect", "PatternFolds", vectorfold, collect, x -> x == collect(0:63)),
        case("folds.unfold", "PatternFolds", vectorfold, PF.unfold, x -> collect(x) == collect(0:63)),
        case("folds.reverse", "PatternFolds", vectorfold,
            x -> reverse(collect(x)), x -> x == collect(63:-1:0)),
        case("folds.interval", "PatternFolds",
            () -> PF.IntervalsFold(Intervals.Interval{Intervals.Open,Intervals.Closed}(0.0, 1.0), 2.0, 32),
            collect, x -> length(x) == 32 && 0.5 in first(x) && !(0.0 in first(x))),
        case("folds.sample", "PatternFolds", () -> (Xoshiro(seed), vectorfold()),
            x -> rand(x[1], x[2], 16), x -> length(x) == 16 && all(v -> v in 0:63, x)),
    ]
end

function check(c::Case)
    c.validate(c.operation(c.prepare())) || error("incorrect result for $(c.id)")
    return true
end

function prepare_batch(c::Case, operations)
    # Probe on a separate input: mutable benchmark inputs must remain untouched.
    output_type = typeof(c.operation(c.prepare()))
    return ([c.prepare() for _ in 1:operations], Vector{output_type}(undef, operations))
end

function execute_batch(operation, batch)
    inputs, outputs = batch
    for i in eachindex(inputs)
        outputs[i] = operation(inputs[i])
    end
    return outputs # Materialize every result so work cannot disappear as an unused call.
end

function measure(c::Case; samples::Int, seconds::Float64, operations::Int)
    1 <= operations <= 256 || error("operation batch budget exceeded")
    check(c) # Compilation and correctness check outside timed expressions.
    operation = c.operation
    prepare = () -> prepare_batch(c, operations)
    all(c.validate, execute_batch(operation, prepare())) || error("incorrect batched result for $(c.id)")
    benchmark = @benchmarkable execute_batch($operation, batch) setup=(batch=$prepare()) evals=1
    trial = run(benchmark; samples, seconds, evals=1)
    return Dict{String,Any}("id" => c.id, "family" => c.family, "scope" => c.scope,
        "validated" => true, "times_ns" => trial.times ./ operations, "gctimes_ns" => trial.gctimes ./ operations,
        "raw_batch_times_ns" => trial.times, "raw_batch_gctimes_ns" => trial.gctimes,
        "operations_per_sample" => operations, "raw_batch_minimum_memory_bytes" => trial.memory,
        "raw_batch_minimum_allocations" => trial.allocs,
        "minimum_memory_bytes" => trial.memory / operations, "minimum_allocations" => trial.allocs / operations,
        "timing_status" => any(t -> t <= 0.001, trial.times) ? "below_timer_resolution" : "measured_batch",
        "samples" => length(trial), "evals" => 1)
end
end
