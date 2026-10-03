# Small Li–Lim pilot

## Current reconstructed cohort (2 October 2026)

The historical vendor reader/validator and dataset API below are absent from the
available dependency snapshots. Their old hashes remain in `vendor-inventory.toml`;
they have not been replaced with hashes of new code. The current continuation uses
`ConstraintModels.Benchmarks` at commit
`4ddd8f65417ac8a8d6bb12add6faf0c0c84801c3` and its explicit `perf/pdptw` environment.
Original lc101/lr101/lrc101 bytes were acquired from SINTEF's checksum-verified
100-task archive; raw files are opt-in and ignored by Git.

From this repository, choose an available CPU, restrict affinity before Julia
starts, set BLAS/OMP/MKL to one thread, and run with `--threads=1 --gcthreads=1
--compiled-modules=existing -O1 --project=$HOME/.julia/dev/ConstraintModels/perf/pdptw`:

- `LiLim/test/pdptw_oracle.jl`: 592 assertions, including agreement between the
  independent validator and fixed-arc MILP on all 576 small route partitions;
  unfixed lexicographic optima agree with exhaustive enumeration.
- `LiLim/test/meta_repair.jl`: 38 assertions for a real
  `LocalSearchSolvers.AbstractMetaVariableResolver`, including actual HiGHS solves
  with specialized and XCSP3Bridges formulations of the same fragment.

`src/MetaRepair.jl` represents each customer successor as a parent decision. A
meta-variable frees a union of complete current routes (at most 20 visits).
Other routes are fixed and complete requests cannot cross the fragment boundary.
The reduced RO model preserves continuous time/load and unrounded Euclidean
distance. Its discrete same-route equalities may use manually specified one-atom
equality DAGs through `XCSP3Bridges.add_program!`. These are versioned structural
weights, not a claim to have learned optimal bridges. The specialized variant
uses the same equality semantics. Both currently omit MIP starts.

The seconds budget covers construction, solving and validation, with cooperative
checks between phases; use an outer process deadline for a hard wall limit.
The adapter rejects partial-route scopes, oversized fragments, changed snapshots,
invalid solutions and results delivered after the budget. Only a lexicographic
global improvement becomes an owned, atomic `MetaMove`. The original problem is
validated again before returning it; outside successors cannot change.
`src/Hybrid.jl` now adds a qualified controller: native LSS steps plus best feasible
reinsertion of randomly selected complete pickup-delivery pairs, common to the
pure and hybrid variants. Both use atomic `MetaMove` commits in the parent solver.
The hybrid also calls the bounded RO resolver. The direct full-route score is
not an ICN; this is a deliberately minimal feasible greedy policy, not a fully
tuned solver. `test/hybrid.jl` passes 1,354 assertions, including exhaustive small
score checks and an independent enumeration of reachable pair relocations.
The original controller passed 1,269 assertions before adding structured moves.
These tiny tests are not comparative performance evidence on full Li-Lim instances.

The [current pilot protocol](CURRENT_PILOT.md) freezes a 72-job diagnostic:
three source instances, two budgets, three seeds and four methods. All 2,051
semantic/model/controller/observer assertions pass. `scripts/current_pilot.jl
check` checks the frozen environment, dependency revisions, source bytes and
single-CPU affinity; `campaign` runs it with resource supervision and immutable
evidence. See the protocol for the exact command and limitations. The campaign
uses this reconstructed cohort, without invoking the historical launchers below.

## Historical pilot

Opt-in DrWatson project. The user authorized four logical CPUs for this pilot on
12 September 2026. CPUs 4–7 (0xF0) are used sequentially; the separate HPO stays on 0–3.
The repository's existing two-CPU default is unchanged. Julia controls all processes.

## Run

From the repository root, set `SOLVER_COMPARISON_CPUS=4,5,6,7` and
`SOLVER_COMPARISON_CPU_LIMIT=4`, then run these Julia scripts successively with
`--startup-file=no --compiled-modules=existing --threads=1 --gcthreads=1 --project=LiLim`:

1. `LiLim/scripts/setup.jl`: offline dependency setup in a dedicated environment.
2. `LiLim/scripts/check.jl`: compact formulation versus exhaustive tiny-route oracles.
3. `LiLim/scripts/run.jl`: download the three selected instances explicitly and run them.
4. `LiLim/scripts/report.jl <campaign-uuid>`: validate and summarize the resulting archive.

HiGHS uses four solver threads with parallel mode enabled and its default presolve.
The controller permits one child at a time and limits it to 180 seconds wall time and
3 GiB of private memory. Compilation, data preparation and model construction are
included in this wall ceiling but reported separately from the 30-second solver budget.
Each phase shares that solver budget. No CP-SAT integer scaling or distance rounding.

## Methods and scope

The full `lc101`, `lr101`, `lrc101` instances use their source fleets. Source files and
archives are acquired through COPInstances and checksum checked. A frozen copy of the
ConstraintModels semantic readers and validator is used; shared checkouts/environments
are not changed. The vendor inventory guards the copied sources. A fresh setup needs
those same workspace source versions; a completed campaign contains their exact snapshot.

The Julia pair-insertion reference runs five construction orders, inserting paired
pickup/delivery tasks together in feasible routes and selecting the lexicographic best
result (vehicles, distance). It is a small authored reference, not a CBLS, GHOST or JuLS
adapter. Its independently validated result is given to HiGHS as a MIP start; every
algebraic constraint of that start is checked before solving.

`pdptw_compact_route_labels_v1` uses a vehicle-independent binary arc model. Each depot
departure anchors a route label to the unique first customer's index. Selected customer
arcs equate those labels; a pickup and its delivery must have equal labels. Order
constraints forbid subtours even at zero distance. Hence paired tasks share a route
without duplicating all arcs by vehicle. Loads and earliest-feasible schedules use
continuous variables; fleet size counts depot departures. This is a new MIP formulation
in this pilot, not a claim that the previous vehicle-indexed formulation was benchmarked.

The first solve minimizes the fleet. Distance is optimized only if fleet optimality is
reported; otherwise the incumbent distance is incidental and is not distance-optimal.
The 21 tiny-case assertions compare against exhaustive route partitions and include
zero distances, capacity, distinct routes, noninteger distances and infeasibility.
No general formal or performance qualification follows from this finite test set.

Raw data, logs, source snapshots, solutions in original node ids, phase statuses, bounds,
PIDs and resource supervision are preserved in `data/sims/<uuid>`. A completion marker
and its result digest are required before a result is reported as completed. The report
keeps construction/reference results separate from HiGHS results and SINTEF references.

CBLS/LocalSearchSolvers, GHOST, JuLS, Timefold and Hexaly do not yet have qualified
specialized Li–Lim routes here. Their absence is not a performance result. Shared HPO
memory/cache/frequency and the short single-seed run preclude an isolated solver ranking.
