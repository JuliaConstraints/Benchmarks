using ConstraintDomains
using Intervals
using PatternFolds

#NOTE - No profiling possible for commons

# function to_profile_commons(iterations = 10^6)
#     for _ in 1:iterations
#         ed = domain()
#         domain_size(ed) == 0 == length(ed)
#         isempty(ed)
#         π ∉ ed
#     end

#     return nothing
# end

# @profview (to_profile_commons())

# @profview (
#     for i in 1:10
#         to_profile_commons()
#     end
# )

function to_profile_continuous(iterations=1000)
    domains = fill(domain([1., 2, 3, 4, 5, 6]), 6)
    for _ in 1:iterations
        d1 = domain(1.0 .. 3.15)
        d2 = domain(PatternFolds.Interval{Open,Open}(-42.42, 5.0))
        domains = [d1, d2]
        for d in domains
            for x in [1, 2.3, π]
                x ∈ d
            end
            for x in [5.1, π^π, Inf]
                x ∉ d
            end
            rand(d) ∈ d
            rand(d, 1) ∈ d
            domain_size(d) > 0.0
        end
    end
    return nothing
end

@profview (to_profile_continuous())

@profview (
    for i in 1:100
        to_profile_continuous()
    end
)



function to_profile_discrete(iterations=1)
    for _ in 1:iterations
        d1 = domain([4, 3, 2, 1])
        d2 = domain(1)
        foreach(i -> add!(d2, i), 2:4)
        domains = [d1, d2]
        for d in domains
            for x in [1, 2, 3, 4]
                x ∈ d
            end
            length(d) == 4
            rand(d) ∈ d
            add!(d, 5)
            5 ∈ d
            delete!(d, 5)
            5 ∉ d
            domain_size(d) == 3
        end

        d3 = domain(1:5)
        d4 = domain(1:0.5:5)

        # NOTE - This avoid runtime dispatch
        domains2::Vector{Union{typeof(d3),typeof(d4)}} = [d3, d4]
        for d in domains2
            for x in [1, 2, 3, 4, 5]
                x ∈ d
            end
            for x in [42]
                x ∉ d
            end
            rand(d) ∈ d
        end
    end
    return nothing
end

@profview (to_profile_discrete())

@profview (
    for i in 1:10
        to_profile_discrete()
    end
)

function to_profile_explore(iterations=10)
    domains = [domain([1, 2, 3, 4, 5, 6]) for i = 1:6]
    for _ in 1:iterations
        explore(domains, allunique)
    end
    return nothing
end

@profview (to_profile_explore())

@profview (
    for i in 1:100
        to_profile_explore()
    end
)
