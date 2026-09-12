bag,route=ARGS
empty!(ARGS);push!(ARGS,bag)
module BagWorker
include("juls.jl")
end
empty!(ARGS);append!(ARGS,[joinpath(route,"instance.txt"),route])
module RouteWorker
include("juls_routing.jl")
end
