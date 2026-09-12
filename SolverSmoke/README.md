# Solver functional pilot

The [full-fleet anytime extension](ANYTIME.md) adds discovery-time traces,
generated strategy profiles and the 30/60/120/240-second Li–Lim campaign. The
historical pilot described below retains its original scope and evidence.

DrWatson study orchestrated entirely in Julia. It executes real CBLS/JuMP,
LocalSearchSolvers native, GHOST/JuMP and native C ABI, Timefold native Java,
JuLS native Julia, and HiGHS as an ILP control. Hexaly is explicitly excluded
until its license is activated.

This is a functional pilot, not a calibrated performance campaign. Default
strategies are retained where applicable; no HPO or strategy matching is claimed.

The [qualified pilot report](QUALIFICATION.md) records the final attempt and its
33 independently validated results. Earlier development attempts are excluded.

## Setup and run

Use four allocated logical CPUs, for example `SOLVER_COMPARISON_CPUS=4,5,6,7`
and `SOLVER_COMPARISON_CPU_LIMIT=4`. Every Julia entry point applies and verifies
Windows process affinity before loading solvers; children inherit it. BLAS, GC
and precompilation helper concurrency are limited. Other HPO work stays on CPUs
0–3; no changes are made to its checkouts or environment.

From the repository, invoke these Julia scripts (with `--startup-file=no`,
`--threads=4,0`, `--gcthreads=1`, and `--project=SolverSmoke` after setup):

1. `SolverSmoke/scripts/setup.jl`: copy local dependencies, resolve the dedicated
   environment offline, retain source hashes. Shared source packages are not edited.
2. `SolverSmoke/scripts/runtime.jl`: fetch a portable JDK and the public JuLS source.
   JDK checksum is checked against the publisher's checksum file. Exact URLs and
   checksums are recorded. No system Java installation is changed.
3. `SolverSmoke/scripts/setup_juls_111.jl` with `julia +1.11 --threads=4`: prepare
   JuLS in its separate environment. Upstream JuLS fails to load on Julia 1.13
   because of its `eval` binding; the tested source is unmodified on Julia 1.11.9.
4. `SolverSmoke/scripts/build_timefold.jl`: build Timefold 2.6.0 with the portable
   JDK and the user's Maven 3.9.1 installation. Maven artifacts stay under runtime/.
5. `SolverSmoke/scripts/build_ghost_portable.jl`: fetch portable w64devkit 2.9.1 and
   compile the native route adapter against a private GHOST source copy. Nothing
   is installed globally. Source, compiler and output hashes are recorded.
6. Set `LILIM_SMOKE_SOURCE` to an original lc101 file downloaded through COPInstances.
   Existing local pilot data are the fallback. Raw data are never downloaded by
   the benchmark launcher, nor bundled in Git.
7. `SolverSmoke/scripts/run.jl`: run all cases sequentially, sharing the repository
   campaign lock, and write a new UUID directory under `data/sims/`.

The supervisor stores exact source/environment snapshots, runtime fingerprints,
logs and subprocess wall times. Each run has a bounded wall deadline. Timefold's
JVM heap is capped at 1 GiB. The final report independently rereads every incumbent.
Completed runs have `completed.toml`; failures retain their evidence without that
marker. Old development attempts remain in data/ and are not pooled into a report.

## Cases and formulations

| Case | Scope | Actual solver paths |
|---|---|---|
| Binary knapsack | 12 variables, capacity 40; exhaustive oracle over 4096 assignments | CBLS/JuMP, LSS native, GHOST/JuMP, GHOST C ABI, Timefold Java, JuLS, HiGHS control |
| Reduced Li–Lim lc101 | Three complete requests, six visits, original time windows and Euclidean distances, one vehicle | CBLS/JuMP, GHOST C++ permutation, Timefold planning list, JuLS permutation invariant |

The routing fixture is deliberately small and has only one feasible permutation
among 720. It qualifies the integration and route semantics, not optimization speed
on full Li–Lim. Native route objectives and constraints are preliminary full-route
evaluators. Timefold uses EasyScoreCalculator; JuLS uses a custom invariant without
CP filtering for routing. Incremental scoring and tuned neighborhoods are future
performance work, not capabilities already qualified by this pilot.

JuLS accumulates constraint deltas and tests feasibility against exact zero. The
routing adapter therefore encodes its error in bounded integral units before
applying the penalty; objective distances remain unrounded. It checks all 10800
permutation/swap transitions and verifies the final feasibility flag against a
fresh evaluation. An earlier attempt exposed floating-penalty drift; its raw
evidence is retained with an audit note and is excluded from qualification.

All solvers receive a two-second solve budget, with three fresh repetitions after
a separate warm-up. Timefold Community uses its default single search thread under
the four-CPU process ceiling; no Enterprise features or license bypass are used.
GHOST's wrapper does not expose a seed: its repetitions cannot be paired by seed.
Wall-budget termination and multithreading also limit seed reproducibility elsewhere.
JuLS keeps its upstream knapsack initialization and heuristics; native initialization
cost is included in build time. No common optimal incumbent is supplied to a solver.

Solver-call time includes model transfer and engine initialization where performed
inside the API call. Runtime startup, import and build times remain separate. A
two-second run is not a measurement of time to first feasible or best solution.
No conclusion about native/JuMP overhead follows from this pilot.

## Availability boundaries

- GHOST/JuMP is qualified here for the small linear integer model, not for the
  custom native route objective. The native C++ path is separate.
- Timefold and JuLS JuMP interfaces are not implemented by these workers.
- The CBLS model is one generated solver profile; it does not characterize all
  possible LocalSearchSolvers/CBLS strategies.
- The first MSVC native build attempt failed because the historical Visual Studio
  installation is absent; the portable compiler path replaces that local setup.
- Private GitLab publication and long-term public release are separate from run
  qualification. Downloaded runtime binaries and raw datasets stay out of Git.
