# Explicit setup only. Existing subproject environments and HPO are never activated.
include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
import Pkg
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
all(arg -> arg in ("--offline", "--resolve"), ARGS) || error("usage: setup.jl [--offline] [--resolve]")
Pkg.offline("--offline" in ARGS)
root = normpath(joinpath(@__DIR__, ".."))
for project in (root, joinpath(root, "Solvers"))
    Pkg.activate(project)
    "--resolve" in ARGS && Pkg.resolve()
    Pkg.instantiate(; allow_autoprecomp=false)
    for relative in ("data/sims", "data/exp_raw", "data/exp_pro", "plots",
            "notebooks", "papers", "_research/tmp")
        mkpath(joinpath(project, split(relative, '/')...))
    end
end
Pkg.activate(root)
println("Prepared root and Solvers scientific environments; no campaigns started.")
