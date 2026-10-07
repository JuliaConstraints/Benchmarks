# Small Li–Lim pilot

## Current preparation (7 October 2026)

Li-Lim is the first qualification target for the new Etendu-aligned cohort.
The [Hexaly coverage catalog](config/hexaly-benchmark-catalog.toml) records all
20 benchmark pages, with their exact source URLs. Other families still need
their data/model adapters and original validators; an inventory entry is not
a completed reproduction. The new public cohort has not been published yet.
Existing public snapshots and historical trial evidence remain available.

The strategy catalog now contains 27 policies, 35 ICN/hybrid variants and four
MetaStrategist portfolios. It retains every historical configuration and adds
random, universal and tabu-triggered full resets, tabu plus partial/full resets,
an exhaustion policy that always resets fully, late acceptance with full resets,
and complementary hybrid/portfolio combinations. Policy state remains local to
each worker. No comparative performance claim follows from these settings.

`--methods=panel` selects the historical methods supported at the requested width,
all strategy variants and portfolios, OR-Tools and Hexaly. `all` retains its old
internal-method meaning. `--missing-solvers=skip` is the default: absent SDKs,
unsupported installed versions and unavailable licenses are recorded explicitly
in the manifest/report and excluded from performance denominators. Use
`--missing-solvers=error` to require every selected solver. Adapter/model defects
and invalid solutions still fail qualification. Availability is frozen in the
campaign identity: do not resume an old output with a different panel or SDK.

### Optional solver installation and platforms

Existing Python/OR-Tools installations are probed before any installation.
An incompatible or broken existing SDK is preserved and reported; it is never
upgraded, reinstalled or repaired automatically. `ORTOOLS_PYTHON` or
`--ortools=/path/to/python` selects an existing environment. Otherwise the local
venv is tried before Python on PATH. Running a campaign never downloads a solver.
Only the explicitly requested `colleague.jl setup` may install a missing SDK.

- OR-Tools 9.14.6206 and its frozen dependencies have lazy Julia Artifacts for
  Linux x86_64/aarch64 with glibc, macOS Intel/Apple Silicon and Windows x86_64.
  A missing SDK requires an existing Python 3.12 interpreter. The installer
  extracts unchanged upstream PyPI wheels using Julia's bundled 7z, verifies
  archive SHA-256 and extracted tree hashes, and retains license notices.
  It loads the immutable cache through PYTHONPATH without pip or venv changes.
  [Bindings](Artifacts.toml) and [provenance](config/solver-artifacts.toml) freeze
  the bytes. Unsupported platforms/interpreters are reported as unavailable.
- HiGHS already uses `HiGHS_jll` Artifacts in the Julia solver environment;
  `Pkg.instantiate` reuses cached binaries and downloads only missing ones.
- Hexaly is an external SDK with an independently installed license. No
  proprietary binary or license is redistributed. Use `HEXALY_EXECUTABLE` or
  `--hexaly=/path/to/hexaly`. Qualification performs a bounded license/version
  probe, followed by original-validator checks; missing access is skipped.
- Timefold currently uses the existing Maven/Java adapter, not these Artifacts.
  CBLS/ICN/MetaStrategist remain Julia source dependencies. JuLS is installed
  locally through its separate Julia environment. GHOST must be called through
  **GHOST.jl**, with its native library provided by `GHOST_jll`; direct C++
  launchers are disabled. The intended wrapper has UUID
  `11b06263-fdad-4e56-a327-8fd38a91e0b8` and was qualified historically at
  `ebeef2c43a094b92d3b11d4642c03b81667597e4` (`forge/moi-wrapper-2026`). Its
  sources and JLL checkout are absent here, although SolverSmoke still references
  them. The accessible older pure-Julia port has a different UUID and is not a
  replacement for this wrapper. Recover the correct sources, then qualify its
  platform artifact and Li-Lim model against the original validator. JuLS and
  GHOST.jl are not yet auto-installed by `colleague.jl setup` or included in this
  runner's `panel`; unavailable support is not a performance result. Historical
  C++ trial evidence remains unchanged and must not be relabeled as GHOST.jl.

OR-Tools is distributed under [Apache 2.0](https://github.com/google/or-tools/blob/v9.14/LICENSE);
HiGHS uses [MIT](https://github.com/ERGO-Code/HiGHS/blob/master/LICENSE.txt).
Artifact wheels retain their upstream dependency and bundled-library notices.
Hexaly installation follows the [vendor documentation](https://www.hexaly.com/docs/last/installation/index.html).

Linux keeps hard CPU affinity. macOS and Windows use solver thread caps and
explicitly record `solver_thread_caps_only`; CPU IDs do not imply P-core
placement there. Darwin uses its native CPU clocks and reaped-child accounting;
Windows uses process/thread times, with sampled child CPU. Mac/Windows launch
paths and SDK bindings are prepared, but runtime qualification on those hosts
is still required. Do not label cross-host measurements as identical hardware.

The no-reinstallation/availability tests passed 85 assertions and the actual
catalog/selector tests passed 47 assertions on Linux. The artifact SDK's native
OR-Tools import also passed. These checks perform no RoutingModel search.
The GHOST frontend checks passed 32 assertions: direct C++ commands and compiler
entry points refuse execution before dependency loading or filesystem changes.
This is an interface-policy check, not a GHOST.jl solver qualification.
Requalification of route policies, ICN resources, hybrids and actual native
solvers on this new cohort remains pending until shared compute resources are free.

```sh
julia LiLim/scripts/colleague.jl setup
julia LiLim/scripts/colleague.jl qualify
julia LiLim/scripts/colleague.jl run --threads=1 --budget=8 --methods=panel --instances=lc101,lr101,lrc101 --seeds=41,42,43 --output=LiLim/results/new-cohort-screen
```

`setup` preserves existing development clones and refuses to clone the unpublished
new cohort. It becomes a complete public handoff after publication and qualification.
Keep new runs in new output directories; stopped historical runs are not resumed.
Bulk trial/log evidence stays local. Selected validated summaries/reports/figures
are the Git deliverables.

## Existing strategy screening (6 October 2026)

Historical method names, allocations, acceptance and zero-fraction reset settings
remain available. `tabu()` meant **no tabu** in those CBLS lanes. The native
stagnation trigger could still restore the best state, without perturbing it.
Their old trial files, manifests and published results remain untouched.

[strategy-variants.toml](config/strategy-variants.toml) initially added 17 existing policy
combinations: short/long tabu, accepted/proposal tabu clocks, keen/weak tabu,
random partial resets from best/current, scaled universal resets, tabu-triggered
resets, selection-exhaustion resets with periodic full resets, assignment-only
search, the native compatibility strategy and the existing late-acceptance policy
with histories of 64 and 400. The settings are initial screening candidates,
not tuned recommendations. All added score paths use the recovered ICN bank;
four variants also use specialized or qualified bridged HiGHS repairs. Two new
MetaStrategist portfolios cycle diverse policy lanes, including mixed hybrids.
These are fixed portfolios, not adaptive strategy selection.

Use `--methods=cbls_icn,hybrid_specialized_icn,strategies` for the initial screen.
`--methods=all,strategies` adds the variants to every historical internal method;
`all` alone retains its previous meaning. Native OR-Tools/Hexaly remain separate
opt-in profiles for those historical screens. The source manifest freezes the strategy catalog and the
reused `SolverSmoke/src/Profiles.jl` acceptance implementation.

The first screen uses LC101/LR101/LRC101, seeds 41/42/43, 8 seconds and one P-core.
Inspect fleet-first best/mean/median/spread, BKS/time-to-target, CPU use, GC,
infeasible-step share and actual tabu entries. Retain a few complementary
profiles for 32/128-second screens and widths 1/2/4/8/16, then confirm with
unexposed official instances and fresh seeds. LC101's already-optimal common
start cannot establish competitive superiority. Avoid multiplying every policy,
instance, seed, budget and thread width before screening them.

After a native reset, successor assignments can temporarily be structurally or
semantically infeasible. Pair reinsertion and RO snapshots wait for feasibility;
the native ICN search continues. Every exported incumbent is independently
validated in the original problem, and late improvements remain censored.
Policy caches and tabu state are synchronized after externally committed moves.
Random/tabu-triggered reset counts are not observable from native strategy types;
reports show them as unavailable rather than inventing counts. Universal and
exhaustion counters use the actual native state. Partial resets operate on raw
successor variables and may be ineffective; that is a measured screening question.

Run `LiLim/test/search_policies.jl --routes` in the qualified solver environment
for strategy contracts and recovered-ICN/original-validator integration. This
test mode does not solve a HiGHS subproblem. Run `LiLim/test/hybrid.jl` and
`LiLim/test/icn_resources.jl` before the comparative cohort when resources are free.
The strategy/ICN route qualification passed 298 assertions on 6 October; six
additional checks of the actual campaign selectors passed. No comparative
strategy cohort has run yet. All 37 configured internal/external plot profiles
have distinct color/marker pairs; all 13 interactive marker shapes and the
embedded JavaScript syntax were checked without rendering.
Reports and plots support the larger catalog, with distinct color/marker pairs,
shared-scale panels, fixed references and interactive solver selection.

## OR-Tools comparison profile (6 October 2026)

The full-corpus runner accepts `--methods=all,ortools_native` and
`--ortools=/absolute/path/to/python` (or `ORTOOLS_PYTHON`). The Python environment
must provide the versions pinned in [requirements.txt](native/ortools/requirements.txt).
Without an explicit override, the runner first selects
`LiLim/native/ortools/.venv/bin/python` when it exists, then falls back to `python3`.
Python is required here by the official OR-Tools RoutingModel interface used for
this external solver; the campaign, validation, aggregation and plots remain in Julia.

OR-Tools 9.14.6206 is installed on this host in that isolated environment with
Python 3.12.3. Dependency consistency, native RoutingModel/CP-SAT/linear-solver
library loading and the adapter command-line entry point were checked on
6 October 2026. No solver search was started during installation. The environment
and bytecode caches are ignored by Git; exact runtime dependency versions are saved.
For the new cohort, use `colleague.jl setup` with an existing Python 3.12
interpreter. It detects an installed SDK first and uses the frozen Artifacts only
when the SDK is absent. The old requirements file is retained as provenance;
setup does not invoke pip or recreate an existing venv.

The OR-Tools profile uses Guided Local Search on one configured P-core, the shared
insertion start, and a dominating fixed vehicle cost for fleet-first ranking.
Its distance costs are scaled by 1,000,000, and its time constraints by 10,000
with conservative rounding; reported distance comes from the original unrounded
Julia validator. It is a local competitor profile, not an exact reproduction of
the vendor's published model. Every retained incumbent is independently audited,
and improvements delivered after the wall budget are censored. Repetition seed
labels do not modify the OR-Tools search, so they measure repeated timings rather
than independent random-seed experiments. Wider campaign thread counts do not
increase this solver's one-thread allocation.

The adapter still has no measured solver trial. Model execution and exported
solutions/trajectories must pass the original validator before comparative use;
that qualification waits until the other active tasks release resources.
See the [capability and hardware estimate](results/hexaly-capability-estimate-20261006.md)
for the published Hexaly comparison, local evidence and limitations.

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
