# Li-Lim comparison guide

Start with the shared preflight from the repository root:

```sh
julia --startup-file=no scripts/colleague.jl preflight
```

It checks every kit solver. Hexaly is optional; absent solvers are skipped.
The [repository guide](../README.md) lists prerequisites and coverage.

## Compare

```sh
julia --startup-file=no scripts/colleague.jl lilim --instances=lc101,lr101,lrc101 --methods=cbls_icn,hybrid_specialized_icn,strategies,ortools_native,ghost_icn,hexaly_native --budget=60 --threads=1 --seeds=41,42,43 --output=LiLim/results/local-60s-1t
```

Omit `--methods` to use the complete existing panel: historical CBLS profiles,
35 ICN/hybrid variants, four MetaStrategist portfolios, HiGHS, OR-Tools, GHOST
and available Hexaly. Methods run in separate trials. Use `--instances=all` for
the 354 frozen SINTEF instances, after selecting a practical method/seed budget.
Timefold is checked by preflight but remains outside this sealed campaign selector.

Widths **1/2/4/8/16** are supported. `--cpus=...` chooses Linux affinity; other
systems use solver thread caps. The default order selects physical cores before
SMT siblings, without distinguishing P/E cores. Actual CPU use is recorded.
OR-Tools RoutingModel uses one CPU. CBLS lanes use independent seeds; OR-Tools
and GHOST repetition labels do not control their native RNGs.

Create `OUTPUT/STOP_AFTER_TRIAL` to stop after the current sealed trial. Remove
it and repeat the identical command with `--resume=true` to resume. Changed
source, environment or trial settings cannot be mixed into existing evidence.

## Results

The command validates exported solutions and trajectories against the original
problem and produces best/mean/median/spread, feasibility, BKS attainment,
time-to-target, English exact/XKCDMakie figures and an offline solver-selectable
dashboard. Fleet is minimized before unrounded Euclidean distance. Statistics
must compare distance at the same fleet size. SINTEF references provide targets,
not comparable historical runtimes.

```sh
julia --startup-file=no LiLim/scripts/colleague.jl export --output=LiLim/results/local-60s-1t
```

Return the printed evidence archive; keep bulk trials out of source commits.
Never include licenses or credentials.

## Solver details

- **OR-Tools 9.14.6206:** RoutingModel guided local search; integer time scale
  10,000 and distance scale 1,000,000. Original double-precision validation remains authoritative.
- **GHOST:** exclusively GHOST.jl through JuMP/MOI, with lane-owned native
  workers and callback buffers. Its ABI exposes no seed or tabu/reset counters.
- **Hexaly:** existing Optimizer 15.0 Modeler executable and license; Studio is
  unnecessary. Pass `--hexaly=/path/to/hexaly` when needed. The fleet/distance
  search allocation is 5:1, differing from a distance-only vendor model.
- **Timefold:** Community 2.6.0, route-level incremental scorer, independent
  serial solvers; preflight validates its scorer and native output.

Setup, imports and model construction are recorded separately; the common trial
clock includes preparation. Late native incumbents are censored. These are local
comparisons; hardware, versions and modeling differences from published experiments
are recorded in the [protocol](config/hexaly-benchmark-catalog.toml).

Sources: [SINTEF Li-Lim](https://www.sintef.no/projectweb/top/pdptw/li-lim-benchmark/),
[Hexaly PDPTW comparison](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw).
