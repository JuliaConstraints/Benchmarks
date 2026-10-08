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
This is not a completely incremental ICN scorer: the original error backend and
full validator still run at admission. Repair candidates, snapshots, pool
maintenance and HiGHS model builds still allocate.

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

`build_catalog(scope=:routing_kernels)` provides insertion, insertion enumeration, fresh/reused cache,
repair, ejection and repeated route-pool admission allocation profiles. `scope=:routing_strategies` accepts
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

The installed PerfChecker 1.0 native `profile_alloc` scenario collector captures
every allocation stack. On this workload its postprocessing exhausted the
diagnostic resource budget before the ICN decoder correction. The same native
API subsequently completed a targeted two-worker HiGHS/IPX portfolio CPU and
allocation qualification. For broad screening, the bounded command uses PerfChecker's
actual dependency-free scenario lifecycle with direct Julia allocation sampling
at 0.001 and aggregates only the top application frames. It reports exact total
allocated bytes/object counts from separate observations and observed GC time;
sampled frame weights are not exact allocation percentages. This fallback does
not substitute for a native full-stack collector result. Full MetaStrategist
observations include lane construction; prepared search observations do not.
Timing, search quality, long-run GC and multicore scaling require later evidence.

An explicit `--instance=/path/to/lc101.txt` profiles the complete original-instance
pipeline, including import, insertion, solver construction, search and final
audit. Its independent byte and object-count observations have separate search
trajectories under the same cap. Total GC includes the pipeline's forced
precollection; `search_gc_seconds` excludes it and the final audit. This mode is
an allocation diagnostic, not a comparative campaign. ICN banks are verified by
content hash on every preparation, while only pure compiled decoder functions
are shared. Mutable learning networks are absent from score closures; counters
and input/error buffers remain owned by each lane.

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

### Qualification recorded on 2026-10-08

All **52 new configurations passed** the two-worker original-model allocation
diagnostic. The structured route tests passed 4,206 assertions, the ICN route
checks passed 30,258, and the historical hybrid checks passed 1,483. Existing
OR-Tools 9.14.6206 also passed 39 original-validator assertions. Hexaly execution
still requires the colleague's licensed host.

For the same small fixed-work adaptive portfolio fixture (two workers, eight
episodes of eight steps), one allocation observation fell from **74,568,944 to
1,103,784 bytes**, and from 1,373,117 to 19,460 objects. Corrections removed
retained ICN learning networks, batched hot counter updates, reused route
summaries and tabu sets, and rejected unchanged proposals before snapshot
construction. These observations establish neither a speedup nor solution
quality on an original instance.

The final original LC101 diagnostics used two physical cores, a 30-second search
cap, and one GC, BLAS and native HiGHS thread:

| Configuration | Allocated bytes, whole pipeline | Search GC, seconds | Mean active CPUs, operational observation |
|---|---:|---:|---:|
| `rp_meta_adaptive_late` | 8,355,187,176 | 1.061 | 1.923 of 2 |
| `rp_meta_pool_ipx_late` | 24,827,329,192 | 5.252 | 1.768 of 2 |

Both passed the original validator. Neither byte-count observation recorded an
accepted original-variable MetaMove; high CPU occupation therefore cannot be
read as useful improvement. Many unchanged proposals were counted explicitly.
Allocation sampling still identifies ejection/route-copy work, exchange and
inheritance, and candidate successor construction. Those sites remain
optimization work; **the original-instance allocation/GC problem is not solved**.
Byte and object totals come from independent fresh observations, with all
source, environment and instance hashes saved in the qualification file. Other
chats were allowed to remain active, so these are allocation and operational
diagnostics rather than controlled scaling comparisons. No 60-second comparative
matrix was launched by this qualification.

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
