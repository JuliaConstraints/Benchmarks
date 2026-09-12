# Small Li–Lim pilot

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
