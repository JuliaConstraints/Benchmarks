"Discrete benchmark toolkit; loaded only in the frozen Julia Constraints environment."
module HexalyReproduction
include("Problems.jl")
include("Readers.jl")
include("Scoring.jl")
include("Solvers.jl")
include("ORTools.jl")
include("Hexaly.jl")
include("Sources.jl")
include("Selections.jl")
include("Campaign.jl")
end
