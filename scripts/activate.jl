# Activate before loading DrWatson, so no global DrWatson installation is needed.
import Pkg
Pkg.activate(normpath(joinpath(@__DIR__, "..")))
using DrWatson
@quickactivate "JuliaConstraintsBenchmarks"
