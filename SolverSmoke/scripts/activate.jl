include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using Pkg
Pkg.activate(abspath(@__DIR__,".."))
using DrWatson
@quickactivate "SolverSmoke"
