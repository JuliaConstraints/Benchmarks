# Discrete benchmark catalogue

The [published catalogue](../LiLim/config/hexaly-benchmark-catalog.toml) preserves
20 entries from the Hexaly comparison page. **19 are active**; inventory routing
(IRP) is deferred because its delivery quantities are continuous. Real-valued
distances and costs are allowed in discrete models. MSSC optimizes a partition,
with centers determined analytically.

This is a multi-solver kit. From the repository root:

```sh
julia --startup-file=no scripts/colleague.jl preflight
```

See [the repository guide](../README.md) for prerequisites and solver coverage.
Existing installations are reused; absent optional solvers are skipped.
`--hexaly`, `--ortools`, `--java` and `--cpus` select existing runtimes or resources.
Old entry points remain compatible.

## Models and strategies

Original validators cover TSP, CVRP, CVRPTW, TOP, QAP, BPP, BPPC, VBP, MSSC,
RCPSP, JSSP, FJSP, SALBP, static aircraft landing, car sequencing and maintenance.
Large CVRP/JSSP reuse those problem semantics. Li-Lim has its [dedicated guide](../LiLim/PUBLIC.md).

CBLS includes naive violation counts, quantitative manual errors, the existing
ICN residual witness and its fused evaluation. These are not newly trained
family-specific ICNs. All four feasible zero sets are checked against original
validators. The **27 existing policies** retain partial/full resets, tabu,
exhaustion, late acceptance and universal policies. Raw permutation/schedule
resets can be ineffective; unavailable counters are reported as unavailable.

MetaStrategist runs independent seeded lanes. Classical hybrid repairs use
bounded HiGHS integer fragments through actual meta-variables, preserve decisions
outside the fragment and validate every accepted repair. FJSP can fix original
starts and machine choices separately. Qualified XCSP3 bridge repairs remain in Li-Lim.
The general model layer is functional; large-instance GC/scaling is unqualified.

The [opt-in strategy panel](STRATEGIES.md) adds 496 distinct configurations,
including 180 heterogeneous MetaStrategist recipes, bounded LP/MIP repairs,
QUBO-guided deep neighborhoods and explicit PerfChecker scenarios.

## Explicit comparisons

```sh
julia --startup-file=no scripts/colleague.jl run --instances=bpp_t60_00 --methods=cbls_naive,cbls_direct,cbls_icn,cbls_icn_fused,strategies,metastrategist,hybrid_highs,highs,ortools,ghost,hexaly --budget=8 --threads=1 --seeds=41,42,43 --output=Hexaly/results/local-bpp-8s
julia --startup-file=no scripts/colleague.jl report --output=Hexaly/results/local-bpp-8s
```

`config/instances.toml` contains **functional smoke inputs**, not complete published
cohorts. For other selections use `--selection=...`, with original byte hashes,
model parameters and reference provenance. TOP uses negative profit for internal
minimization. Primal runs reject RCPSP certified-bound record selections.

Reports preserve lexicographic best/worst, feasible-solution mean/median/spread,
feasibility over all attempts, BKS attainment and observed time-to-target.
Native endpoints without callbacks have unobserved target times. Every solution
and trajectory is revalidated. English exact/XKCD plots retain distinct markers
and visible reference values when supplied.

`--max-cells=250000` bounds exact expansions. `STOP_AFTER_TRIAL` and
`--resume=true` preserve sealed trials; source/environment/instance hashes must
match. Model defects fail; unsupported models and absent solvers are recorded
separately. Raw inputs, vendor templates and trials stay outside Git.

## Remaining qualification

Complete published membership and references remain pending outside Li-Lim.
The report separates small functional qualification from corpus qualification.
Native Hexaly tests require a usable 15.0 license; TOP/VBP/BPPC/maintenance have
no Hexaly adapter yet. Classical OR-Tools covers eight integer families; its
routing families outside Li-Lim remain unqualified. GHOST classical native
qualification covers BPP. Other commercial and JuLS adapters remain unqualified.

Published solver versions, budgets, hardware and primal/dual metrics are frozen
in the catalogue. Different local hardware and model settings must be reported
as local comparisons rather than identical replications.
