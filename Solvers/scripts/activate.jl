# Pkg is a standard library: first select the environment, then load its DrWatson.
import Pkg
Pkg.activate(normpath(joinpath(@__DIR__, "..")))
using DrWatson
@quickactivate "SolverComparisonBenchmarks"
