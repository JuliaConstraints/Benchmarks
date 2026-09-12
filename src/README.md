# Shared research code

The repository root is the `JuliaConstraintsBenchmarks` DrWatson scientific project.
Reusable cross-study analysis can live here; importing code must not start experiments.
Solver-specific code is maintained in the independently activated `Solvers/src` project.
`PackageBenchmarks.jl` defines the active package kernels without launching them.
`Evidence.jl` records immutable attempts and snapshots. Historical environments and
results are preserved in `archive/legacy` and excluded from active launchers.
