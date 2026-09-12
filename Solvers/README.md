# Solver comparisons

This independent subproject of JuliaConstraints/Benchmarks prepares reproducible
comparisons of optimization solvers. ConstraintLearningBenchmarks remains dedicated to
its learning/HPO experiments; this project does not write to that repository.

**Current slice:** ILP functional protocol, path registry, six authored finite fixtures,
independent exact oracle and immutable attempt directories. The 19 registered paths are
targets, not implemented or qualified adapters. The planner performs no solver run.

**Primary objective:** an honest comparison using suitable native models and configurations
for each engine. **Secondary objective:** compare each engine's native and JuMP paths.
LocalSearchSolvers is the solver generator; CBLS is its JuMP interface. Strategy choices
and other hyperparameters define each generated solver. Matched GHOST-like/JuLS-like/etc.
profiles and HPO-improved profiles are separate experiment identities.

See [implementation plan](docs/plan.md), [adapter contract](docs/adapters.md), and
[coordination and publication](docs/coordination.md).
The [initial qualification](docs/qualification.md) records the scope of the checks performed.

## Bounded infrastructure checks

Instantiate DrWatson using the repository-root `scripts/setup.jl` before these checks.
No instance download, solver license or modification of a shared Julia environment is
required. CPU ids must be explicitly allocated for the current machine.
For the coordinated Windows session of 12 September 2026, CPU ids 4 and 5 avoid the HPO
running on ids 0–3. This is a session allocation, not a universal default.

```powershell
$env:SOLVER_COMPARISON_CPUS = '4'
julia --startup-file=no --threads=1 --gcthreads=1 --project=. test/runtests.jl
$env:SOLVER_COMPARISON_CPUS = '4,5'
julia --startup-file=no --threads=2 --gcthreads=1 --project=. test/runtests.jl
julia --startup-file=no --threads=2 --gcthreads=1 --project=. scripts/plan.jl
```

Run commands successively from `Solvers`. Limits apply to the whole task: at most two
logical CPUs and one active run. The current affinity guard is Windows-only and refuses
to expand inherited affinity. Two Julia workers exercised by an infrastructure test do
not qualify any solver's threading. Data under `data/` are ignored by Git and never replace
prior attempts. Results are functional evidence, not performance measurements.

External solver adapters will use separate pinned environments per engine, optional
dependencies and explicit native/JuMP entry points. No automatic background campaign or
CI schedule is installed. The preparation remains local; first publication is intended
for the private GitLab, with public release considered later.
