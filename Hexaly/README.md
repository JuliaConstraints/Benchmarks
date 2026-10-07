# Discrete reproductions of the Hexaly benchmark page

The catalogue preserves all **20 published entries**. **19 are active**; the ROADEF-2016 inventory-routing model is deferred because its delivery quantities are continuous. Distances, risks and data coordinates may be real without introducing continuous decisions. MSSC optimizes the partition; cluster centers follow analytically from it. Integer aircraft landing times retain the original static single-runway scope.

This toolkit prepares local comparisons. It does **not** claim that every exact published cohort is ready or that the public Hexaly results have been reproduced. The 20-entry protocol catalogue, original instance selection and preflight state those differences explicitly.

## One command for the colleague

From the repository root, with Julia **1.13.1**, Git and an existing Hexaly **15.0** installation/license:

```sh
julia --startup-file=no Hexaly/scripts/colleague.jl preflight
```

This reuses installed solvers, prepares missing permitted dependencies, fetches checksum-frozen original data/templates, checks the frozen Julia cohort, runs bounded model/validator/native API tests on one CPU, and writes an English Markdown/TOML report under `Hexaly/results`. It starts no comparative campaign. Hexaly is never installed or redistributed by this script. Its license/version probe uses the existing Li-Lim gate and excludes raw vendor diagnostics from reports.

Exit codes: **0** for a fully ready check, **1** for an actual qualification/preparation failure, **2** for incomplete published-corpus/model readiness. Currently the catalogue-wide command returns **2** after successful functional qualification because exact published selections and references remain incomplete. An absent optional solver is skipped; an installed solver with a broken model is a failure. A successful license probe alone does not qualify its models.

To inspect a prepared machine without installing/downloading or solving:

```sh
julia --startup-file=no Hexaly/scripts/colleague.jl preflight --prepare=false --qualify=false
```

`--hexaly=/path/to/hexaly`, `--ortools=/path/to/python` and `--cpus=8` select existing installations or an allowed Linux CPU. Other systems use thread caps without claiming Linux CPU affinity. Julia development checkouts stay under `~/.julia/dev`; the benchmark repository belongs under `~/Gits`. Existing mismatched or dirty checkouts are preserved and reported.

## Li-Lim first

Li-Lim retains its original qualified model, learned constraint ICNs, specialized and XCSP3 bridge repairs, route-aware strategy panel, MetaStrategist portfolios, OR-Tools RoutingModel with guided local search, GHOST.jl and optional Hexaly. The existing 354-instance byte/reference manifest and historical configurations are preserved.

```sh
julia --startup-file=no Hexaly/scripts/colleague.jl lilim --instances=lc101,lr101,lrc101 --methods=cbls_icn,hybrid_specialized_icn,strategies,ortools_native,hexaly_native --budget=8 --threads=1 --seeds=41,42,43 --output=LiLim/results/colleague-lilim-8s
```

The selected Li-Lim methods must be supported by its existing campaign selector. Use the [Li-Lim public guide](../LiLim/PUBLIC.md) for its complete panel, plots, export and resume options.

## Classic discrete models

Independent original validators and quantitative error implementations cover TSP, CVRP, CVRPTW, TOP, QAP, BPP, BPPC, VBP, MSSC, RCPSP, JSSP, FJSP, SALBP, static aircraft landing, car sequencing and maintenance scheduling. Large CVRP/JSSP reuse those semantics; RCPSP bound records use the same problem but a different measurement protocol.

The native CBLS panel contains naive violation counts, manual quantitative errors, the existing ICN witness applied to individual residuals, and its scalar fused evaluation. **These are not newly trained family-specific ICNs**. All four zero sets are checked against an independently implemented original validator on exhaustive small cases. The 27 existing policies include short/long/accepted/keen/weak tabu, partial/full best/current/random/tabu resets, exhaustion, universal policies, late acceptance and compatibility/assignment policies. No historical profile is replaced. Raw variable resets can be ineffective on permutations or schedules; only measured reset counters justify conclusions, and unexposed counters remain unavailable.

The classical hybrid uses an actual `LocalSearchSolvers.MetaVariableRequest`, a bounded HiGHS integer fragment and an atomic `MetaMove`. Decisions outside that fragment stay fixed, original labels are preserved, and the original validator checks every accepted repair. FJSP repair currently requires the complete small decision group. Classical families do not acquire XCSP3 bridge semantics by association; qualified bridge repairs remain in Li-Lim.

MetaStrategist resolves a real typed phase containing independent solver lanes. The diverse portfolio rotates late acceptance, tabu, partial exhaustion and universal-best policies. Other CBLS modes run independent seeded lanes at the requested width. Every lane owns its mutable error backend and solver state. This initial general model layer still allocates collections and validates incumbents; its qualification does **not** establish optimized GC, throughput or scaling on the large corpora.

`metastrategist_mixed` additionally assigns one in four workers to bounded HiGHS repair and one in four to manual quantitative errors. It is available only for families with a prepared exact integer fragment. Allocations repeat at widths above four; the actual thread cap is recorded. This is a configuration to test, not evidence that a mixed portfolio performs better.

### Optional solver coverage

| Solver | Prepared adapter | Remaining qualification |
|---|---|---|
| HiGHS | Exact integer models for BPP/BPPC/VBP/SALBP/RCPSP/JSSP/FJSP/aircraft | Original large selections; capped expansion may be unsuitable |
| OR-Tools 9.14 | Same eight integer models through CP-SAT; Li-Lim uses its separate RoutingModel GLS adapter | Classical routing and other families have no adapter yet; no scaling/rounding of noninteger constraints |
| GHOST | Exclusively the Julia JuMP/MOI wrapper, direct/ICN callbacks | Generic native test covers BPP; other families require native qualification; seed setter unavailable and one native worker |
| Hexaly 15.0 | External vendor models and original decision exporters for 12 classical families, plus Li-Lim | Real native output qualification requires a usable license; TOP/VBP/BPPC/maintenance adapters remain absent |
| Gurobi/CPLEX/CP Optimizer and other Julia wrappers | Existing installation detection only | Additional licensed model/API adapters are not yet qualified |

The external Hexaly application templates are downloaded by checksum and remain outside Git. They are not copied into the CBLS implementations. The OR-Tools Python file exists solely at the official SDK boundary; Julia handles models, data, original validation, orchestration and reports. Permitted SDK Artifacts and optional GHOST platform builds are managed by the existing Li-Lim kit. Installed versions are never silently replaced.

### Explicit local trial selection

The committed `config/instances.toml` contains original-format **functional smoke inputs**, not the exact published selection. It deliberately does not attach invented BKS values, fleet caps, cluster counts or optimality claims. For a scientific cohort, provide a selection with original byte hashes, parameters, reference objective/kind/URL, and `scope = "published_selection"` only after exact published membership has been checked.

```sh
julia --startup-file=no Hexaly/scripts/colleague.jl run --instances=bpp_t60_00 --methods=cbls_naive,cbls_direct,cbls_icn,cbls_icn_fused,strategies,metastrategist,hybrid_highs,highs,ortools,ghost,hexaly --budget=8 --threads=1 --seeds=41,42,43 --output=Hexaly/results/local-bpp-8s
```

This is an example **local comparison**, not a published BPP reproduction. `--selection=...`, `--max-cells=250000` and `--resume=true` are available. No campaign starts without explicit instances and an output path. Source/environment/instance hashes and sealed trials prevent mixing changed configurations on resume. `STOP_AFTER_TRIAL` in the output directory stops after the current sealed trial. Unsupported models and unavailable solvers are recorded separately; model defects fail without an alternative fallback.

Each solution and trajectory is validated in the original problem. Statistics retain lexicographic best/worst, component-wise mean/median/population standard deviation/spread, feasibility rate, BKS attainment and observed time-to-target. Means use feasible solutions only, and the denominator of the feasibility rate includes all attempts. Native endpoints without callbacks have **unobserved time-to-target**, rather than an invented reference time. Cold preparation and complete wall time are recorded separately from the requested CBLS search budget. These are functional prototypes; fair native warmup and performance profiling remain required before publishable timing comparisons.

TOP stores negative collected profit to keep every internal objective minimized. Reference vectors must follow the same minimization/lexicographic convention. The native local duration may overrun a deadline while an atomic step finishes; the overrun is recorded, and post-budget CBLS incumbents are excluded from trajectories.

After an explicit run, revalidate its seals and create English exact and XKCDMakie quality/success figures:

```sh
julia --startup-file=no Hexaly/scripts/colleague.jl report --output=Hexaly/results/local-bpp-8s
```

Color/marker pairs are distinct across the complete selector panel; fixed reference marks stay visible. Component plots retain the lexicographic interpretation and do not merge incomparable distances from different fleets.

## Published protocols and outstanding corpus work

See [the frozen 20-entry catalogue](../LiLim/config/hexaly-benchmark-catalog.toml) for each source, dataset, solver version, budget and primal/dual metric. Older published Hexaly releases are kept as protocol metadata; the local licensed target is 15.0. The published Ryzen 7 7700 (8 cores, 32 GB) differs from the local i7-12700 (8 P-cores, 4 E-cores, 20 logical CPUs). Record affinity, widths 1/2/4/8/16, CPU model and memory; do not describe the local run as identical hardware replication.

Full source bundles are already registered for the modified VBP instances, Muritiba BPPC and seven-source FJSP collection. Frozen vendor archives provide several original examples. TOP Chao and ROADEF-2020 official examples/checker add original format checks. **Exact selections and BKS records are still required**, notably CVRPLIB X/Arnold, Solomon/Homberger, TSPLIB symmetric TSP, RG300, Otto large/very-large SALBP, large industrial JSSP, selected hard BPPLIB, largest Taillard QAP, all car-sequencing groups and RTE A/B/C. Example data must not be promoted into those cohorts. ROADEF-2020 resource tolerance is `1e-5`, matching the official checker.

RCPSP records compare **certified lower bounds**, not CBLS makespans. The primal runner rejects dual-record selections; a separate certified-bound comparison must qualify those bound outputs first. Continuous IRP remains listed as deferred and does not block discrete qualification. Unsupported original formats or model-size caps are reported; large expansions are never launched merely to fill a table.

No new performance campaign was launched while preparing this kit. Bulk original data, templates and raw trials stay local; publish source, selected protocol/reference metadata, summaries and English figures only.
