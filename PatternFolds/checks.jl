using BenchmarkTools
using CairoMakie
using Chairmarks
using PerfChecker

@info "Defining utilities"

d_commons = Dict(
    :targets => ["PatternFolds"],
    :path => @__DIR__,
    :pkgs => ("PatternFolds", :custom, [v"0.1.1", v"0.1.2", v"0.1.3", v"0.1.4", v"0.1.5", v"0.2.0", v"0.2.1", v"0.2.2", v"0.2.3", v"0.2.4", v"0.2.5", v"0.2.6"], true),
    :tags => [:patterns],
    # :seconds => 100,
    # :samples => 10,
    # :evals => 10,
)

## SECTION - Utilities
tags(d) = mapreduce(x -> string(x), (y, z) -> y * "_" * z, d[:tags])

function visu(x, d, ::Val{:allocs})
    mkpath(joinpath(@__DIR__, "visuals"))
    c = checkres_to_scatterlines(x, Val(:alloc))
    save(joinpath(@__DIR__, "visuals", "allocs_evolution_$(tags(d)).png"), c)

    for (name, c2) in checkres_to_pie(x, Val(:alloc))
        save(joinpath(@__DIR__, "visuals", "allocs_pie_$(name)_$(tags(d)).png"), c2)
    end
end

function visu(x, d, ::Val{:benchmark})
    mkpath(joinpath(d[:path], "visuals"))
    c = checkres_to_scatterlines(x, Val(:benchmark))
    save(joinpath(d[:path], "visuals", "bench_evolution_$(tags(d)).png"), c)

    for kwarg in [:times, :gctimes, :memory, :allocs]
        c2 = checkres_to_boxplots(x, Val(:benchmark); kwarg)
        save(joinpath(d[:path], "visuals", "bench_boxplots_$(kwarg)_$(tags(d)).png"), c2)
    end
end

function visu(x, d, ::Val{:chairmark})
    mkpath(joinpath(d[:path], "visuals"))
    c = checkres_to_scatterlines(x, Val(:chairmark))
    save(joinpath(d[:path], "visuals", "chair_evolution_$(tags(d)).png"), c)

    for kwarg in [:times, :gctimes, :bytes, :allocs]
        c2 = checkres_to_boxplots(x, Val(:chairmark); kwarg)
        save(joinpath(d[:path], "visuals", "chair_boxplots_$(kwarg)_$(tags(d)).png"), c2)
    end
end

@info "Running checks: :benchmark"

d = deepcopy(d_commons)

x = @check :benchmark d begin
    using PatternFolds
    if d[:current_version] ≥ v"0.2.0"
        using Intervals
    end
end begin
    if d[:current_version] ≥ v"0.2.0"
        itv = Interval{Open,Closed}(0.0, 1.0)
        i = IntervalsFold(itv, 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = make_vector_fold([0, 1], 2, 1000)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        rand(vf, 1000)
    else
        # Intervals
        i = IntervalsFold(Interval((0.0, true), (1.0, false)), 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = VectorFold([0, 1], 2, 1000)
        # @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        map(_ -> rand(vf), 1:1000)

    end
end

visu(x, d, Val(:benchmark))

@info "Running checks: :chairmark"

x = @check :chairmark d begin
    using PatternFolds
    if d[:current_version] ≥ v"0.2.0"
        using Intervals
    end
end begin
    if d[:current_version] ≥ v"0.2.0"
        itv = Interval{Open,Closed}(0.0, 1.0)
        i = IntervalsFold(itv, 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = make_vector_fold([0, 1], 2, 1000)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        rand(vf, 1000)
    else
        # Intervals
        i = IntervalsFold(Interval((0.0, true), (1.0, false)), 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = VectorFold([0, 1], 2, 1000)
        # @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        map(_ -> rand(vf), 1:1000)

    end
end

visu(x, d, Val(:chairmark))

@info "Running checks: :allocs"

x = @check :alloc d begin
    using PatternFolds
    if d[:current_version] ≥ v"0.2.0"
        using Intervals
    end
end begin
    if d[:current_version] ≥ v"0.2.0"
        itv = Interval{Open,Closed}(0.0, 1.0)
        i = IntervalsFold(itv, 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = make_vector_fold([0, 1], 2, 1000)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        rand(vf, 1000)
    else
        # Intervals
        i = IntervalsFold(Interval((0.0, true), (1.0, false)), 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # Vectors
        vf = VectorFold([0, 1], 2, 1000)
        # @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        map(_ -> rand(vf), 1:1000)

    end
end

visu(x, d, Val(:allocs))

@info "All checks have been successfully run!"
