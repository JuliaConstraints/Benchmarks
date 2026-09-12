# Julia Constraints Benchmarks

A DrWatson scientific project for package diagnostics and honest solver comparisons.
All preparation, checks, experiment launchers and analysis scripts are Julia. Solver
adapters may call a required foreign runtime from Julia; orchestration stays in Julia.

## Studies

| Study | Location | Current scope |
|---|---|---|
| Package diagnostics | `src/PackageBenchmarks.jl` | 15 bounded cases: ConstraintCommons, ConstraintDomains, PatternFolds |
| Solver comparisons | [Solvers](Solvers/README.md) | Independent DrWatson environment; ILP oracle and functional protocol; adapters pending |
| Actual solver pilot | [SolverSmoke](SolverSmoke/README.md) | CBLS, LSS, GHOST, Timefold and JuLS; small common ILP and reduced Li–Lim; four-CPU ceiling |
| Li–Lim exploratory pilot | [LiLim](LiLim/README.md) | Three full instances, compact JuMP/HiGHS and Julia insertion reference; explicitly authorized four-CPU override |
| Historical evidence | [archive/legacy](archive/legacy/README.md) | Original scripts, CSV and figures, preserved with SHA-256 inventory; excluded from launchers |

The machine-readable catalogue is [config/catalogue.toml](config/catalogue.toml).
ConstraintLearning's former folder contained only an environment, so it is retired from
the active catalogue. This repository does not modify or launch the separate live
ConstraintLearningBenchmarks HPO experiments.

## Setup and use

Run from the repository root. Allocate CPU ids explicitly for the current session.
The example allocation below was coordinated on 12 September 2026: CPU 4–5 here, CPU 0–3
for the other HPO task. It must be rechecked for a future session. The resource guard
currently supports Windows and limits every launcher and child to the chosen CPUs.

```powershell
$env:SOLVER_COMPARISON_CPUS = '4,5'
julia --startup-file=no --threads=2 --gcthreads=1 --project=. scripts/setup.jl --offline
julia --startup-file=no --compiled-modules=existing --threads=2 --gcthreads=1 --project=. scripts/run.jl check
julia --startup-file=no --compiled-modules=existing --threads=2 --gcthreads=1 --project=. scripts/run.jl packages-measure
julia --startup-file=no --compiled-modules=existing --threads=2 --gcthreads=1 --project=. scripts/run.jl solvers-plan
```

Commands run successively. `setup` only instantiates the pinned root and Solvers
environments; remove `--offline` to allow required downloads. Dependency re-resolution
is explicit with `--resolve`. Automatic precompilation is disabled during setup.
No benchmark starts during setup or source imports. Scientific manifests are retained;
the present lockfiles were resolved and checked with Julia 1.13.0. Julia 1.10 remains
declared compatible but unqualified.

`run.jl check` checks DrWatson paths and historical hashes, executes package smoke
diagnostics and then ILP infrastructure checks. The other commands select one study.
`scripts/report.jl <package-attempt-uuid>` verifies and summarizes one completed package
attempt into `data/exp_pro/packages/<report-uuid>/report.md`; it never pools attempts.
The launcher serializes work using `_research/run.lock`, records its owner, and stops
on failure. A stale lock requires checking its owner before manual removal. There are
no background workers, automatic version sweeps or scheduled campaigns.

## Data and interpretation

- `data/sims/packages/<uuid>`: per-case raw BenchmarkTools timings, GC timings,
  minimum allocations/memory, seed, resources, configuration and source hashes.
- `data/sims/orchestration/<uuid>`: sequential step logs and run status.
- `Solvers/data/checks` and `Solvers/data/plans`: independent functional evidence.
- `data/exp_raw`, `data/exp_pro`, `plots`, `notebooks`, `papers`: DrWatson locations
  for future inputs, derived analyses and publications. Generated data stay out of Git.

Each new attempt has its own directory, source/environment snapshot and completion
digest. Interrupted or failed attempts have no valid completion marker. Existing
results are never overwritten. Snapshots include uncommitted Julia/TOML inputs; no
claim that a dirty Git revision alone identifies the run. Historical results retain
their original provenance limitations.

The initial measurements are diagnostic only. Inputs are deterministic, mutable setup
is recreated per sample, `evals=1` batch, and correctness is checked outside the timing.
Each batch uses 256 independent inputs (8 for exhaustive exploration) and retains every
output. Raw batch measurements and normalized values per operation are both saved;
normalization includes the loop and output-storage overhead. This measures amortized
throughput, not isolated call latency. Unresolved timings are explicitly flagged.
The [qualification record](docs/qualification.md) links the one/two-thread checks,
the bounded measurements and their limits.
Compilation is warmed outside measurements. Both smoke and measurement presets remain
short (3 or at most 50 samples per case; 0.01 or 0.1 seconds of sampling per case).
These are sampling budgets, not hard end-to-end deadlines. Package import, compilation,
setup and validation take additional time. See [method and migration](docs/method.md).

No solver ranking or performance equivalence follows from these checks, particularly
while HPO shares memory/cache/frequency. The primary research goal remains optimized
native solver comparisons; native versus JuMP overhead and strategy-matched generated
solvers are separate, explicitly identified experiments.

The working branch is `feat/solver-comparison-ilp`. The authorized publication target
is `git@nohost.d-vision.fr:julia/Benchmarks.git`, private, directly in the Julia group;
no Oasis registration is needed. The private GitLab project was created and the signed
branch pushed on 2026-09-12 after service recovery. Later, selected material can
be released on Mirage Interactive's public GitHub after campaign qualification.
