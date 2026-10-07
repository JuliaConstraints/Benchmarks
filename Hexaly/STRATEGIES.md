# Experimental strategy panel

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
