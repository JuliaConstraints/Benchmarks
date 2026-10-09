# Experimental strategy panel

## Additive Li-Lim route strategies

The structured route panel adds **52 configurations (36 search profiles and 16
cooperative MetaStrategist portfolios)** to the historical 496. It is specific
to Li-Lim; it does not claim support for every classical family. Select it with
`routing-panel`, `routing-search-panel` or `routing-meta-panel`. The bounds and
future campaign settings are in
[routing-panel.toml](../LiLim/config/routing-panel.toml).

| Profiles | Implemented behavior |
|---|---|
| GES adaptations | Remove a short route; repair a complete-request bank; bounded one/two-request ejections; difficulty memory increases bounded ejection effort |
| ALNS | Random, Shaw-related, worst-contribution, entire-route and paired-string destruction; regret-2/3 insertion; reward-adaptive destruction selection |
| SISR adaptations | Adjacent strings closed over pickup/delivery partners; insertion blinks; separate periodic fleet-elimination attempts |
| Route VND | Pair relocation, cross-route pair exchange and two-request repair chains; greedy, late or arc-attribute tabu acceptance; genuine partial/full request resets |
| Diversity | Directed arc pheromone guidance/reinforcement; disjoint route inheritance from retained solutions followed by repair |
| Guided neighborhoods | Existing sparse value-pair QUBO scopes, direct time-window slack explanations, bounded certified pair incompatibilities and a greedy clique fleet lower bound |
| Cooperative portfolios | Actual typed MetaStrategist phases; independent owned CBLS states; validated solution and route pools; incumbent exchange at episode barriers; rotating or reward-adaptive roles |
| RO recombination | HiGHS restricted route set partitioning through the public semantic meta-variable resolver; simplex/IPX/HiPO LPs, integral MIP reconstruction, restricted LP dual request priorities |

These are bounded adaptations, **not exact implementations of the published
GES/AGES, ALNS, SISR, ECACO or memetic protocols**. In particular, the short
repair chain is not a general variable-depth search, and the pheromone variant
is not a full ant-colony system. The direct slack explanation is not a newly
trained ICN explanation network. QUBO input retains its provenance; the default
bounded structural proxy is explicitly unlearned.

Every admitted route solution passes the original validator and the actual
configured error backend. Structured candidates enter the existing CBLS model
as atomic original-successor MetaMoves. Incomplete request banks remain private
repair states. The HiGHS master only optimizes collected feasible route columns;
its bounds and duals do not certify the original complete problem. Pool columns
retain pickup/delivery closure and exact original distances and resource limits.

Sequence summaries cache fixed-order time propagation, load extrema and travel
distance. Insertion feasibility uses concatenation without constructing a route
per candidate. Accepted route changes rebuild affected caches using owned
buffers; large routes use an explicit scan fallback beyond the cache cell cap.
Each lane owns reusable route-copy, ejection, insertion-option, request-bank,
successor, changed-variable and inheritance buffers. Neither another worker nor
a retained incumbent/pool snapshot aliases these mutable buffers. This is not a
completely incremental ICN scorer: the original error backend and full validator
still run at admission. Retained snapshots, pool maintenance and HiGHS model
builds still allocate.

At widths 1/2, roles rotate between episodes so a four-role recipe does not
silently drop two or three algorithms for the entire trial. The adaptive recipe
uses observed episode improvements with mandatory exploration. Workers never
mutate each other's live solver state; pool sharing and the serial master happen
after all lanes join. The master consumes the same wall deadline and receives a
bounded slice and cumulative share; uninterruptible build/audit overhead can
overrun a slice, and late candidates are discarded. No asynchronous exchange or
thread migration is claimed.

## Prepared 1/2/4 colleague matrix

The current requested comparison is **60 seconds, widths 1/2/4, two seeds per
width**: six trials per configuration and original instance. Implementation
qualification has not launched that comparison. The future explicit command is:

```sh
julia --startup-file=no scripts/colleague.jl lilim-matrix --instances=lc101,lr101,lrc101 --methods=cbls_icn,rp_ges2_late,rp_alns_adaptive_regret3,rp_sisr_b15_regret3,rp_vnd_tabu,rp_meta_pool_ipx_late,ortools_native,hexaly_native --budget=60 --widths=1,2,4 --seeds=41,42 --cpu-slots=4 --output=LiLim/results/route-matrix-60s
```

Preflight must succeed first. Existing installations are reused and unavailable
optional solvers are skipped. The existing `ortools_native` Li-Lim baseline is
RoutingModel GLS with one internal search thread; its allocated width does not
turn it into a multicore search. OR-Tools portfolio and CP-SAT functional checks
remain in preflight, with their existing original-data restrictions.

The matrix assigns **disjoint CPU masks**. The colleague's host defaults to
**four CPU slots**: widths 1+2 can overlap, then width 4 runs alone, with two
seeds at each width. Only the local machine may opt into `--cpu-slots=8`;
with at least seven allocated CPUs, 1+2+4 runs can overlap there. Smaller hosts
use successive waves or reject an impossible width. Linux selects one CPU per
physical core before considering SMT siblings. Rendering waits for every
solve to finish. Resume verifies the matrix plan and preserves sealed child
trials. Concurrent processes share cache and memory bandwidth, so these results
must be labelled as concurrent local comparisons; they are not interchangeable
with exclusive vendor timings. For exclusive measurements, use `lilim` at each
width sequentially.

The complete new panel across all 354 originals schedules **110,448 trials**.
Ideal scheduling needs about **51.1 days** on the four-slot colleague host,
or **25.6 days** with local 1+2+4 overlap, at 60 seconds before warmup,
initialization, reports and interruptions. Start
with an explicit small selection; keep the larger grid prepared for later.

The colleague's fixes are covered by regression checks: native solver report
rows accept structured values; the Hexaly availability decision uses `<-`;
the PDPTW model uses `1000.0`, `serviceStart` and `routeLength`. These source
checks do not replace execution on a licensed Hexaly Optimizer 15.0 host.

## Structured routing profiling

### Overnight owned-workspace checkpoint, 2026-10-08

The clean `perf/routing-owned-oracles-20261008` branch integrates published CBLS,
LocalSearchSolvers, MetaStrategist and original PDPTW-validator improvements.
Each routing lane owns a validation workspace and reusable random-request
selection buffers. Complete original validation remains mandatory; returned
diagnostics, incumbents and pool entries retain independent ownership. The fused
ICN error-term buffer also preserves capacity across infeasible fleet layouts.

All 52 fixed-work configurations and 14 numerical/workflow kernels passed their
original-model oracles, together with 7,128 routing, 30,322 ICN/resource and 1,483
hybrid assertions. Additional fixed-work allocated bytes fell by **7.4–55.8%**
against the previous prefilter checkpoint. The insertion-enumeration fixture now
prepares its wrapper views outside measurement; that scope correction is excluded
from production improvement claims.

Five new 30-second LC101 diagnostics used two dedicated physical cores. Their
cumulative Julia allocations fell by **18–37%** against the previous checkpoint,
with lower search GC time in every observation. These time-capped runs executed
different numbers of steps and establish no controlled speedup. All solutions
and trajectories passed original validation. LC101 recorded no accepted
MetaMoves; three additional LR101 and three LRC101 observations exercise the
accepted-move paths and also passed. These are diagnostics, not a solver ranking.

Classical scheduling/resource callbacks use owned event, alternative-assignment,
machine-task and maintenance-load buffers with concrete numerical function
barriers. Across 384 fixed callbacks, native allocation totals changed from
870,400 to 30,720 bytes for RCPSP, 380,928 to 215,040 for JSSP, 620,544 to 215,040
for FJSP, and 571,392 to 49,152 for maintenance. Both direct and fused ICN
observations passed. The classical tests passed 10,459 assertions, including
6,514 new checks of ordered quantitative terms, ownership, mutable data and
wide-integer fallbacks. These totals exclude preparation, decoder compilation
and independent verification; allocations remaining in the machine maps and
dynamic dispatch are being investigated.

English [exact and XKCD figures](../perf/figures/owned-workspaces-20261008) and
the complete source/dependency hashes are published with
[the qualification record](../perf/routing-qualification.toml). Regenerate them
with the existing plotting environment:

```sh
julia --startup-file=no --project=LiLim/plotting perf/plots.jl perf/routing-qualification.toml perf/figures/owned-workspaces-20261008 exact
julia --startup-file=no --project=LiLim/plotting perf/plots.jl perf/routing-qualification.toml perf/figures/owned-workspaces-20261008 xkcd
```

The integrated dependency pins are distinct from the historical Handoff cohort;
its saved environment is preserved. Concurrent chats used disjoint CPU masks,
so operational timings are retained as observations and are not advertised as
controlled speedups. The 60-second colleague matrix remains unlaunched.

`build_catalog(scope=:routing_kernels)` provides insertion, insertion enumeration,
fresh/reused cache, repair, ejection, repeated pool/duplicate admission,
route-copy and successor-fill allocation profiles. `scope=:routing_strategies` accepts
explicit `rp_` IDs and profiles the actual configured error backend. Search
profiles use eight steps on a tiny original model; MetaStrategist profiles use
four real cooperative episodes of at most four search steps each, including the semantic route-pool resolver
where selected. These are bounded functional/allocation diagnostics, not
Li-Lim performance or scaling results. See
[routing-qualification.toml](../perf/routing-qualification.toml) for verified
checks and limits.

Before promoting a new routing configuration, run the bounded qualification in
the frozen solver environment with two workers:

```sh
OPENBLAS_NUM_THREADS=1 julia --startup-file=no --threads=2 --gcthreads=1 \
  --project="$HOME/.julia/dev/JuliaConstraintsHandoff/ConstraintModels/perf/pdptw" \
  perf/routing_perfcheck.jl --width=2 --seconds=30 --methods=routing-panel \
  --observations=native \
  --output=/tmp/routing-perfcheck.toml
```

Select explicit IDs for an incremental change. Restrict CPU affinity to two
physical cores when the operating system supports it. No package is installed
by this command. It locates an existing PerfChecker scenario runtime; an
explicit `--runtime=/path/to/PerfChecker/src/scenario_runtime.jl` is also accepted.
Each observation uses fresh owned state and the original validator. The search
cap is 40 steps per worker; the cooperative cap is eight episodes of eight
steps, covering reset thresholds, role rotation, adaptive allocation and the
periodic HiGHS resolver. The 30-second operation cap is a maximum, not a promise
that every small fixture runs for 30 seconds. Warmup is separate.

`--observations=native` invokes the installed PerfChecker 1.0 CPU and allocation
runtime APIs. Allocation collection records every stack at sample rate 1.0;
only aggregates and the top application frames are saved. This runs the native
collectors in process with fresh scenario state, not the `run_scenarios` process
orchestrator. Short fixtures can yield no CPU samples; their allocation and
functional checks still apply, but they provide no CPU hotspot evidence.
Byte counts, object counts and stack samples are separate native observations.
Full MetaStrategist observations include lane construction; prepared search
observations do not. Timing, search quality, long-run GC and multicore scaling
require later evidence.

The default `--observations=sampled` uses the same scenario lifecycle with direct
Julia allocation sampling at 0.001. It saves bounded frame aggregates and
independent byte/object totals; frame weights are not exact allocation
percentages. Native full-stack collection on a busy original instance can
consume excessive collector memory, so it is restricted to fixed-work fixtures.
Use `--observations=totals` for a single original-instance observation:

```sh
OPENBLAS_NUM_THREADS=1 julia --startup-file=no --threads=2 --gcthreads=1 \
  --project="$HOME/.julia/dev/JuliaConstraintsHandoff/ConstraintModels/perf/pdptw" \
  perf/routing_perfcheck.jl --width=2 --seconds=30 --methods=routing-panel \
  --observations=totals --instance=/path/to/lc101.txt \
  --output=/tmp/routing-lc101-perfcheck.toml
```

An explicit `--instance=/path/to/lc101.txt` profiles the complete original-instance
pipeline, including import, insertion, solver construction, search and final
audit. In totals mode, bytes, object counts and GC come from the same
uninstrumented operation. An independent one-second warmup follows compilation
on the small fixture. Total GC includes the pipeline's forced
precollection; `search_gc_seconds` excludes it and the final audit. This mode is
an allocation diagnostic, not a comparative campaign. ICN banks are verified by
content hash on every preparation, while only pure compiled decoder functions
are shared. Mutable learning networks are absent from score closures; counters
and input/error buffers remain owned by each lane. Completed observations are
checkpointed atomically; existing output files are never silently overwritten.
Allocated bytes mean cumulative Julia-managed allocations, not peak resident
memory or native HiGHS heap usage.

Candidate enumeration keeps exact evaluation/blink counts in machine integers
and publishes them on every exit, including deadline and candidate-cap exits.
Insertion alternatives use a concrete tuple layout. Cooperative workers repeat
bounded search chunks until their common episode deadline, then join at the
existing sharing barrier. Fixed-step diagnostics explicitly disable this slice
filling so before/after allocation observations retain the same work cap. These
changes do not establish 100% useful CPU utilization: sharing, validation, GC and
serial restricted masters still consume time and require separate measurement.
Identical incumbent proposals are rejected before allocating route-validation
and successor snapshots; their late-history update is preserved. Exact unchanged
proposal counts use a lane-owned integer and are published at episode boundaries,
so repeated no-op attempts cannot be mistaken for useful search progress. Tabu
arc sets are owned and reused per lane; profiles without tabu skip those sets.

The workspace route copier expects an independently owned source (or its exact
own active view). Arbitrary overlapping/reordered views into its backing buffers
are not supported. `MetaRepair.successors!` checks the original solution before
writing into caller storage; its internal unchecked fill is reserved for already
validated complete solutions. Neither helper replaces the admission oracle.
Destruction ranks are computed once per request, and immutable comparator
captures avoid boxed pickup/rank values. In-place insertion preserves pickup
precedence; successful ejections copy back into caller-owned route storage.
Unstable sorting may resolve equal-rank ties differently from older runs.

### Workspace checkpoint recorded on 2026-10-08

All **52 new configurations passed** the two-worker native PerfChecker
CPU/allocation fixture oracles. The structured route tests passed 4,416 assertions, the ICN route
checks passed 30,258, and the historical hybrid checks passed 1,483. Existing
OR-Tools 9.14.6206 also passed 39 original-validator assertions. Hexaly execution
still requires the colleague's licensed host.

For the same small fixed-work adaptive portfolio fixture (two workers, eight
episodes of eight steps), one allocation observation fell from **74,568,944 to
839,800 bytes**. Independent object-count observations fell from 1,373,117 to
13,101. Corrections removed retained ICN learning networks, batched hot counter
updates, reused route summaries, request/route/successor buffers and tabu sets,
and rejected unchanged proposals before snapshot construction. These
observations establish neither a speedup nor solution quality on an original
instance. The native collector's independent byte observation recorded 827,256
bytes for this configuration; the two totals need not match exactly.

All **11 native kernel allocation oracles passed**. After buffer setup, insertion
summary evaluation (1,024 repetitions), cache reuse (128), owned route copying
(1,024) and successor filling (1,024) each recorded **zero allocated bytes and
objects**. Repair/ejection and repeated pool admission still allocate. The
50-request Shaw regression also checks its ranking/destruction path independently
of the small three-request profiling fixture.

All **52 original LC101 pipeline diagnostics passed** with two physical cores,
a 30-second search cap, and one GC, BLAS and native HiGHS thread. Bytes and object
counts in this pass come from the same uninstrumented operation:

| Configuration | Previous published bytes | Current bytes, whole pipeline | Current search GC, seconds | Current mean active CPUs |
|---|---:|---:|---:|---:|
| `rp_meta_adaptive_late` | 8,355,187,176 | 2,382,976,832 | 0.865 | 1.945 of 2 |
| `rp_meta_pool_ipx_late` | 24,827,329,192 | 512,569,992 | 0.042 | 1.967 of 2 |
| `rp_vnd_greedy` | Not measured | 6,209,506,008 | 1.640 | 1.900 of 2 |

None of these 52 observations recorded an accepted original-variable MetaMove;
high CPU occupation therefore cannot be read as useful improvement. Many
unchanged proposals were counted explicitly. The original-instance allocation
range is 251,086,504–6,209,506,008 bytes per observation; search GC is
0.011–1.643 seconds. VND does not call HiGHS and remains a priority for targeted
original-instance stack analysis. Fixed-work native profiles still identify
validation, candidate/request guidance, pool snapshots and RO model builds.
**The complete pipeline is not allocation-free.**

Independent time-capped runs can complete different work, so these allocation
reductions per budget establish neither per-operation speedups nor search quality.
All source, environment, instance and frozen dependency hashes are saved in the
qualification file. Other chats were allowed to remain active, so these are
allocation and operational diagnostics rather than controlled scaling
comparisons. No 60-second comparative matrix was launched by this qualification.

### Incremental exchange qualification

Original LC101 allocation stacks identified the complete validator called by
random cross-route exchanges as a major allocation source. The owned controller
now rejects an infeasible modified route using its original Euclidean distance
matrix before constructing the full audit. Every surviving exchange still passes
the complete original validator. The default public exchange call retains its
previous behavior, including when a caller supplies a different distance matrix.

The extended routing suite passed **5,381 assertions**, including differential
exchange checks and a warmed rejected-exchange allocation regression. All **52
native fixture CPU/allocation oracles passed again**. Five targeted original
LC101 diagnostics passed with the same two physical cores and 30-second cap:

| Configuration | Workspace checkpoint bytes | Exchange prefilter bytes | Search GC before, seconds | Search GC after, seconds |
|---|---:|---:|---:|---:|
| `rp_vnd_greedy` | 6,209,506,008 | 1,534,983,912 | 1.640 | 0.100 |
| `rp_vnd_late` | 6,139,324,408 | 1,497,968,808 | 1.583 | 0.106 |
| `rp_vnd_tabu` | 5,851,355,896 | 1,506,079,944 | 1.643 | 0.110 |
| `rp_meta_fleet_distance_late` | 3,416,967,616 | 1,110,661,568 | 1.019 | 0.075 |
| `rp_meta_adaptive_late` | 2,382,976,832 | 874,251,648 | 0.865 | 0.053 |

These are cumulative whole-pipeline allocations; they do not describe peak
memory. Time-capped runs completed different step counts, recorded in the
versioned `night_exchange_prefilter` evidence. None recorded an accepted MetaMove.
This incremental pass therefore establishes allocation/GC reduction under this
budget, not a per-operation speedup, better search quality, or a new all-52
original-instance qualification. Frozen solver dependencies and the learned ICN
bank were unchanged. Subsequent package and workspace work uses separate source
cohorts so these historical observations remain reproducible.

## Historical extended panel

The kit provides **496 distinct opt-in configurations** in addition to the
historical methods. It shares the catalogue between Li-Lim and the discrete
classical runner. Historical defaults and selectors remain unchanged.

| Selector | Configurations | Actual differences |
|---|---:|---|
| `cbls-panel` | 220 | Four error backends; plateau acceptance, tabu tenure/clock, late history, partial/full random or universal resets, exhaustion |
| `hybrid-panel` | 72 | Four existing search policies; three repair intensities; MIP, root IPX/HiPO, simplex/IPX RINS, local branching |
| `qubo-panel` | 24 | Absolute/conditional interactions; depths 2/4/8; frequencies 16/64; exploration 5%/25% |
| `meta-panel` | 180 | Heterogeneous typed MetaStrategist portfolios; complementary policies, errors, QUBO and RO roles; equal/search-heavy/repair-heavy allocations |

`extended-panel` expands all four selectors. It is an explicit enumeration,
not a recommendation to run the full Cartesian grid. Configuration duplicates
and identical weighted roles are collapsed. The executable definitions and
bounds are in [strategy-panel.toml](../LiLim/config/strategy-panel.toml).

## Select a small cohort

Keep the usual colleague entry point and preflight. New model, policy and
workspace checks run with the existing qualification, including two owned
workers when the CPU allocation permits it. Absent optional
competitors retain their existing skip behavior.

```sh
julia --startup-file=no scripts/colleague.jl preflight
julia --startup-file=no scripts/colleague.jl lilim --instances=lc101,lr101,lrc101 --methods=cbls_icn,xp_cbls_icn_fused_all_tabu_t16_accepted,xp_hybrid_late_400_balanced_rins_ipx,xp_meta_qubo_ro_balanced_balanced_equal,ortools_native,hexaly_native --threads=4 --budget=8 --seeds=41,42,43 --output=LiLim/results/panel-screen-8s-4t
```

Do not start comparative cohorts until preflight succeeds and resources are
available. Start with a few complementary configurations, then promote on
original feasibility, fleet-first best/mean/median/spread, target attainment,
time-to-target and CPU/GC/allocation evidence. Confirm on fresh seeds and
previously unexposed original instances. Extend budgets to **32/128/512 seconds**
and widths **1/2/4/8/16** only for useful candidates. Record physical-core/SMT
affinity; thread count alone is insufficient for a hardware comparison.

Classical `run` accepts the same selectors and IDs. Its qualified integer repair
families are packing, SALBP, RCPSP, JSSP, FJSP and static aircraft landing.
FJSP repairs can now fix original start and machine-choice decisions separately.
XCSP3 bridge portfolios remain Li-Lim-only; unsupported families are recorded
explicitly. Classical ICNs retain the existing qualified residual witness and its
fused evaluation, rather than newly trained family-specific networks.

## Owned lanes and semantic RO fragments

Each worker owns its solver, error network, guide and scratch buffers. The
current MetaStrategist implementation allocates fixed heterogeneous roles and
merges validated incumbents. It does not perform adaptive role allocation or
continuous incumbent exchange. At 16 workers the four-role equal QUBO/RO recipe
allocates four workers to each role. At widths 1/2 some roles cannot participate;
the exact effective allocation and missing roles are saved with every result.

Li-Lim repairs select complete current routes and retain fixed outside routes.
Classical packing repairs extend selections to complete bins/stations and reject
oversized fragments. Scheduling repairs operate on original decisions with
fixed outside values. Candidate moves are checked by the original validator and
qualified error backend before admission.

HiGHS receives exact bounded integer fragments. RINS first solves an LP relaxation
and fixes integer decisions only where an optimal LP point agrees with the current
assignment. Local branching restricts binary Hamming distance or integer L1 distance.
MIP root IPX/HiPO uses `mip_lp_solver`; `solver=ipx/hipo` is used for actual LP
relaxations. Fractional LP points are never exported as solutions. Fragment bounds
are recorded as restricted bounds and cannot certify the complete original problem.
See the [HiGHS options](https://ergo-code.github.io/HiGHS/stable/options/definitions/).

Every subsolver uses one native thread. Repair intensity controls fragment size,
frequency, slice budget and total repair share. Setup, LP/MIP work, original
validation and guide work consume the recorded budgets. HiGHS models are still
built per repair; native solve/build allocations have not been eliminated.
Only qualified one-atom equality bridges are used; no broader bridge claim is made.

## Learned value-pair matrices

Set `JULIACONSTRAINTS_QUBO_GUIDE` to a guide file or a directory containing
`INSTANCE_ID.toml`. Without a supplied matrix, guided profiles use a bounded
**analytic structural proxy**, explicitly labelled as unlearned guidance.
Matrix energy ranks proposals and connected neighborhoods; original feasibility
and objective remain authoritative.

`QUBOGuidance.from_matrix(Q, atoms)` consumes full `z'Qz` convention: diagonal
coefficients are linear, and `Q[i,j]+Q[j,i]` becomes one unordered pair term.
Each atom is `(original_variable_index, original_integer_value)` with one-hot
value semantics. The simultaneous delta includes changed/changed terms once.
`from_component(component, bindings)` accepts QUBOConstraints components with
explicit primary BitID bindings, verifies supplied one-hot codebooks and rejects
domain-wall/unsupported encodings. Auxiliary interactions are omitted and this
projection is labelled; it is not an exact reformulation or certificate.

Use `write_guide(path, guide; instance_sha256=...)` to export a mapped learned
component. Existing files are preserved. The TOML schema is
`value-pair-qubo-guide/1`, with `encoding="one_hot_value_atoms"`,
`convention="canonical_polynomial"`, `atoms`, `linear`, and `quadratic` triples
`[atom_index_1, atom_index_2, coefficient]`. Instance-bound guides must match the
original bytes; atoms must belong to the original domains. Input hashes are
sealed and rechecked between trials and on resume.

Caps are 2,048 atoms and original variable indices, 20,000 pair terms, eight proxy values per variable and 32
candidate values per depth proposal. Guide work has a 10% share and is reported
including truth checks. Absolute and incumbent-conditional scopes use connected
interaction growth with explicit exploration. Buffers are borrowed within one
lane; retained moves/incumbents own their snapshots. Rejected guide proposals
leave the solver unchanged.

## PerfChecker and SIMD

[perf/catalog.jl](../perf/catalog.jl) defines 27 numerical scenarios and an
explicit per-configuration solver catalogue. It uses actual CBLS and typed
MetaStrategist execution, fresh owned state and an independent oracle. Solver
scenarios run a fixed 256-step cap on a tiny packing fixture; they qualify
profiling and shared kernels, not Li-Lim quality or full-corpus scalability.
Bridge variants are excluded from this classical profiling fixture.

From a controller environment containing the qualified PerfChecker 1.0 API:

```julia
using PerfChecker
include("perf/catalog.jl")
solver_project = joinpath(homedir(), ".julia/dev/JuliaConstraintsHandoff/ConstraintModels/perf/pdptw")
catalog = build_catalog(scope=:strategies,
    methods=["xp_cbls_direct_greedy_p0", "xp_meta_qubo_ro_balanced_balanced_equal"], width=4)
diagnose(catalog; project=solver_project, tools=[:gc, :locks, :latency, :snoopcompile],
    threads=4, reports=nothing)
run_scenarios(catalog; project=solver_project, threads=4, samples=5,
    reports="LiLim/results/panel-perfcheck")
```

Missing collectors/analyzers are reported as unavailable; solver environments
are never modified by these calls. The default collectors are CPU and allocation
profiles. Use the kernel catalogue for energy, simultaneous delta, full-move
recalculation, scope selection and depth proposals. Profile one representative
per shared kernel first, then configurations selected for promotion. Run timing
or width comparisons only with exclusive resources and identical affinity.

PerfChecker isolates its worker load path. Its SnoopCompile adapter therefore
requires SnoopCompile in the chosen diagnostic project. Locally, SnoopCompile
3.2.9 was already available in the optional `LiLim/perfcheck` environment; a
separate direct capture reused it as a load-path layer with the frozen solver
project first. It passed the actual two-worker QUBO/RO scenario. The recorded
inclusive inference accumulation is instrumented compiler evidence, not wall
time or a portable startup comparison. No solver dependency or sysimage changed.

Guide reductions and aircraft cost loops use safe SIMD annotations without
`@fastmath`. Sparse field updates visit affected neighbors, preserving joint
move semantics. Numerical kernel tests show zero warmed allocations; the complete
PerfChecker lifecycle has its own small overhead. Packing callbacks cache domains,
integer values and label workspaces. Hot objective evaluation uses separately
qualified objective kernels; the original validator still audits incumbents.
Classical workers reuse the compiled scalar ICN function by exact bank-content
hash, while inputs, error terms, counters and score workspaces remain private.
The cache lock is used during preparation, not scoring. The measured preparation
allocation change covers 16 backends after the first bank compilation; it does
not remove initial Julia/HiGHS compilation or per-repair model construction.
The [qualification evidence](../perf/qualification.toml) records measured
allocation changes and the limits of the small diagnostic. No full-machine
scaling or solver superiority is established by it.

The overnight routing qualification exercised all four implemented collectors
(`benchmark`, `chairmark`, `profile`, `profile_alloc`) and eight applicable
analyzers (`jet`, `alloccheck`, `snoopcompile`, `latency`, `gc`, `memory`, `heap`,
`locks`) on insertion, repair, adaptive MetaStrategist and the HiGHS IPX route
pool. All 48 tool/scenario executions completed with the original-model oracle
passing. Findings remain: static allocation reports include possible branches,
and dynamic dispatch boundaries limit inference coverage. A completed diagnostic
is not a clean performance verdict. Aqua is qualified on the actual packages in
their dedicated environments; this routing application is not an importable
package. Compact observations, source/environment hashes and scope limitations
are recorded in [routing qualification](../perf/routing-qualification.toml).
Whole-worker redacted heap snapshots were verified and removed after preserving
their sizes and hashes; native HiGHS memory is outside those snapshots.

The first classical workspace stage also completed 64 fresh-worker analyzer
runs: RCPSP, JSSP, FJSP and maintenance, each with direct and fused ICN scoring,
through all eight applicable analyzers. Every original-model callback oracle
passed. The general family/data callback still has 247 JET findings and 164
AllocCheck findings per specialization; these are recorded, not treated as
clean results. Lifecycle SnoopCompile excludes the bank generation performed
by the scenario factory. All eight redacted heap artifacts were verified and
removed. Source/environment hashes, exact finding counts, diagnostic scopes
and compact measurements are in the same routing qualification file.

The next workspace stage removes transient scheduling views and scalar tolerance
boxing, specializes routing and resource arithmetic, and retains at most eight
fresh-layout machine maps per private worker. Maps are reused only for the same
ordered active machine keys; data edits still enter every score calculation.
Wider/custom arithmetic retains its original fallback. Prepared direct and
fused-ICN callbacks on nine fixed fixture families each measured zero warm
allocations with the native PerfChecker allocation collector. This excludes
preparation, first bank compilation, cache misses and original validation.
Ordered term comparisons, changing machine patterns and explicit zero-allocation
regressions qualify these paths; this is not a whole-solver zero-allocation claim.

The Li-Lim guidance adapter now delegates its numerical kernels to the qualified
`QUBOConstraints.ValuePairGuidance` API. It retains matrix conventions, explicit
component bindings, provenance and original-model authority. A narrow move visits
the sparse pair frontier; wide frontiers retain the qualified full-scan fallback.
Each workspace belongs to its guide. The exact dependency cohort and portable
environment are pinned in `LiLim/config/workspace-cohort.toml`; package branches
may advance without changing these source commits. Earlier cohorts remain
recorded and existing installations are preserved.

The combined cohort passed **65,086 original-model, ownership and integration
assertions**, all 52 two-worker routing profile oracles, and an offline portable
environment check that preserved the frozen Project/Manifest bytes. Repeating
both scoring sources on that same dependency cohort confirmed the warm allocation
reduction on all 18 callback cases. All 72 fresh-worker collector checks passed;
BenchmarkTools retains a 16-byte result-boundary discrepancy, also visible in
instrumented stack samples despite zero independent native totals. Several
MetaStrategist fixed-work rows allocate approximately 1–1.5% more than the preceding
package cohort; these regressions are retained, with no package attribution or
speed/quality claim.

Private repair defaults now reuse their uniform-priority buffer, resetting every
entry before each call. Known algorithm and counter names also use immutable
strings. The historical explicit-priority path, custom-name fallback, acceptance
and RNG behavior remain intact. All 52 profiles executed the same observable
fixed work and allocated fewer bytes (0.5–24.9%) and objects (1.2–40.8%). The
routing suite passed 9,834 assertions, including 540 differential repairs that
compare routes, traces and the next RNG value. Initialization is included in
these allocation totals; they establish neither a speedup nor search quality.
English exact and XKCD figures are in
[the figure directory](../perf/figures/owned-workspaces-20261008/).

Corrected sampled-stack attribution resolves the actual application and package
checkouts. The original LR101 diagnostic retained 321/323 VND events and 213/233
MetaStrategist events in its top groups. These sampled weights identify source
locations; they are not percentages of total allocated memory.

Separate fresh-process capture now includes the actual first ICN bank recovery,
before any scenario factory. It allocated 672,133,600 bytes; immediate cached
recovery allocated 7,664 bytes with no observed compilation or GC. SnoopCompile
recorded 2,456 unique cold specializations, including expression printing.
Overlapping compiler aggregates are not elapsed time. Decoder truth, exact bank
hash and private buffers passed; this establishes the remaining cold cost,
without claiming an improvement or a controlled startup time.

The actual GHOST Li-Lim adapter also passed 855 original-model and ownership
assertions, including exhaustive tiny-instance permutations and bounded native
calls with one and two independent lanes. All calls retained the valid insertion
incumbent; no improved solution was observed. The native ABI does not apply the
seed label. This functional qualification leaves the optional runner gate
unchanged and establishes no search-quality or scaling result.

A further measured routing stage reuses private guidance IDs and QUBO node
membership, specializes the destruction call after the dynamic master lookup,
compacts removed visits in place, and reuses ACO's private arc set. All 52 paired
observations preserve full trace work checksums, original routes and next RNG
values; 46 allocate less and six are unchanged. The original routing suite passes
10,652 assertions, including 818 new buffer and differential checks. Native
LP/MIP lifecycle totals vary across fresh processes and remain reported as paired
observations. The original validator, search decisions, retained snapshots and
master semantics are preserved. The English exact and XKCD figures include every
configuration and a fixed previous-source reference.

The complete nine-family, two-backend classical pass now contains 144 qualified
fresh-worker executions through all eight analyzers. Every original complete
checksum and zero-set oracle passed. The general callback retains 195 JET and
111 AllocCheck findings per specialization. Invalid selector attempts and one
source-fingerprint retry are recorded separately and excluded from the qualified
counts. All 18 redacted heap captures were verified and removed. Timing remains
diagnostic under concurrent work; these passes do not establish a clean static
verdict or a controlled speedup.

The actual CBLS objective callbacks now use private scratch for TSP, QAP, CVRP,
CVRPTW, TOP, MSSC, car sequencing and maintenance. Across 24 fixed original-model
inputs, both the prepared callback and its actual CBLS wrapper fall from
816–3,360 allocated bytes per call to zero. Sixteen native PerfChecker checks
cover both direct and fused ICN backends with complete original-objective
checksums. Instrumented profiles retain a 16-byte boundary event despite zero
independent uninstrumented totals; the evidence keeps that distinction.

All 17,192 application checks pass, including 3,297 additional objective checks
for infeasible assignments, data and domain edits, private ownership, exact
MSSC floating-point reductions, checked QAP overflow and maintenance quantiles.
Independent risk additions produce four-lane Float64 SIMD instructions. Means
retain their original reduction order; partial sorting selects the same clamped
quantile while reusing private scratch, including larger scenario arrays.
Cold preparation, cache misses, unsupported arithmetic and final original
validation can still allocate. The MSSC dense matrix cache retains at most
eight shapes. This qualification establishes allocation reductions on the
reported workloads; concurrent observations do not establish a controlled
speedup or improved solution quality.

Pair relocation now retains its best insertion in lane-owned scratch and creates
one independent incumbent after selection. Active route buffers survive changes
in fleet size. Twelve generated original-PDPTW fixtures, with 8, 32, 64 and 128
requests and three seeds, reduce warm allocated bytes by 67–91%. Historical
routes, examined candidates and complete checksums match exactly, and every
incumbent passes the original validator. Independent returned snapshots still
allocate. The 1,511 hybrid assertions include buffer reuse, fleet-size changes,
retained results and the previous two-argument workspace constructor.

All 52 fixed-work routing profiles also preserve complete trace hashes, routes
and next RNG values. Five VND search profiles allocate less; the other search
profiles are unchanged. Small complete MetaStrategist workloads include both
reductions and slight lifecycle increases, which remain visible in the figures.
Fresh LP/MIP lifecycle observations can vary. English exact and XKCD figures
retain previous-source reference marks; the reported observations establish
allocation changes, without a controlled timing or search-quality conclusion.

The actual relocation call also completes 36 fresh-worker executions: three
fixture sizes through all four collectors and eight analyzers. Every full
original-model, enumeration and ownership oracle passes. JET reports zero
findings; AllocCheck retains 39 potential allocation findings per specialization.
One GC and one memory diagnostic flag remain recorded. Three redacted heap
captures were verified and removed. These results retain the independent
returned snapshots and do not imply a zero-allocation whole solver.
