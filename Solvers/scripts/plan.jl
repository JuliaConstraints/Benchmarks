include("resources.jl")
include("activate.jl")
include(srcdir("SolverComparison.jl"))
using .SolverComparison
using TOML
const ROOT = projectdir()
isempty(ARGS) || error("this entry point only prepares a plan; solver execution is not implemented")
plan = pilot_plan(joinpath(ROOT, "campaigns", "ilp-functional.toml"))
plan["cpus"] = COMPARISON_CPUS
plan["affinity"] = string(COMPARISON_AFFINITY; base=16)
plan["concurrency_note"] = get(ENV, "SOLVER_COMPARISON_CONCURRENCY_NOTE", "not_recorded")
path = write_attempt(datadir("plans"), plan)
println(length(plan["planned_runs"]), " planned case/path/thread combinations; no solvers run.")
println(path)
