module BenchmarkTargets

export REPORTED_DISTANCE_DIGITS, reaches_published_bks

const REPORTED_DISTANCE_DIGITS = 2

"""Whether a feasible result reaches SINTEF's displayed lexicographic target.

SINTEF publishes best-known distances rounded to two decimals. Keep the solver's
raw distance for ranking, but compare rounded values when reporting attainment.
"""
function reaches_published_bks(vehicles::Integer, distance::Real,
        target_vehicles::Integer, target_distance::Real;
        distance_digits::Integer=REPORTED_DISTANCE_DIGITS)
    distance_digits >= 0 || throw(ArgumentError("distance precision must be nonnegative"))
    isfinite(distance) && distance >= 0 || return false
    isfinite(target_distance) && target_distance >= 0 ||
        throw(ArgumentError("published target distance must be finite and nonnegative"))
    vehicles < target_vehicles && return true
    vehicles == target_vehicles || return false
    round(Float64(distance); digits=distance_digits) <=
        round(Float64(target_distance); digits=distance_digits)
end

end
