include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
import Pkg
Pkg.activate(normpath(joinpath(@__DIR__, "..")))
using DrWatson
@quickactivate "LiLimPilot"
