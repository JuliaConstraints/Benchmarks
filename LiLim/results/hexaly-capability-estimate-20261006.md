# Expected Hexaly Performance on Our Li-Lim Comparisons

**Status: evidence-based estimate, not a local Hexaly result.** No Hexaly trial is included in the local cohorts below. Public vendor results provide a useful scale estimate; they do not establish how Hexaly compares with our current CBLS/MetaStrategist profiles on this machine.

## Closest published comparison: Li-Lim PDPTW

Hexaly's published PDPTW benchmark uses Li-Lim instances with 100 to 1,000 customers. It reports Hexaly Optimizer 15.0 and OR-Tools 9.14, default parameters, Guided Local Search for OR-Tools, 60-second and 600-second limits, and an AMD Ryzen 7 7700 system with 32 GB RAM. The published distance gaps to SOTA are:

| Customers | Hexaly 1 min | Hexaly 10 min | OR-Tools 1 min | OR-Tools 10 min |
|---:|---:|---:|---:|---:|
| 100 | 0.0% | 0.0% | 1.3% | 0.1% |
| 200 | 0.1% | 0.0% | 8.1% | 3.1% |
| 400 | 0.6% | 0.3% | 17.6% | 12.7% |
| 600 | 1.0% | 0.3% | 26.9% | 17.6% |
| 800 | 1.2% | 0.4% | 40.2% | 20.7% |
| 1,000 | 1.8% | 0.6% | 47.0% | 22.0% |

These are Hexaly's own reported averages by instance size, not independent replications. The trend is still clear: on this dataset, Hexaly reports a substantial quality advantage over OR-Tools from 200 customers onward, widening sharply on the largest instances.

There is an important objective caveat. The page says the literature objective minimizes fleet size first and distance second, but its table reports distance gaps only. Its model discussion also describes a soft-lateness phase followed by distance. The page does not publish per-instance fleet gaps, so its percentages cannot be treated as a complete replication of our fleet-then-distance score. We must validate the exact model and objective used in any new run.

## Our machine and the published machine

The Hexaly page names a Ryzen 7 7700 with 8 cores, 3.8 GHz base frequency, and 32 GB RAM. AMD specifies that chip as 8 cores / 16 hardware threads. Our host is an Intel Core i7-12700 with 8 Performance cores, 4 Efficient cores, 12 total cores, and 20 hardware threads; this machine has about 31 GiB RAM. The count of fast physical cores is comparable (8 vs. 8), and memory capacity is effectively similar, but the CPU topology is different: the Ryzen has eight uniform Zen 4 cores with SMT, while the Intel mixes Performance and Efficient cores.

The published Hexaly page does not state its actual thread count or CPU affinity. Hexaly documentation says the default `hxNbThreads=0` adapts to the machine and model, uses at least four threads by default, and may use more than an explicitly requested count. We therefore cannot infer that the published benchmark used exactly eight solver threads. Setting the parameter to eight is a request, not a strict cap. A controlled local comparison should test automatic and requested-eight-thread settings with CPU affinity restricted to the eight physical P-cores, and record actual CPU consumption.

The current campaign affinity policy fills eight physical P-cores first, then the four E-cores, then P-core SMT siblings. Consequently, its existing 16-worker setting means eight P-core lanes, four E-core lanes and four P-core SMT lanes. It is not equivalent to the Ryzen's 16 logical CPUs on eight uniform cores. A separate 16-lane P-core-only mask can measure SMT on our eight P-cores, while the full 20-lane mask measures the whole hybrid CPU. Equal core counts or clock frequencies alone cannot provide a reliable runtime conversion between the two machines.

Official hardware references: [AMD Ryzen 7 7700 specifications](https://www.amd.com/en/products/processors/desktops/ryzen/7000-series/amd-ryzen-7-7700.html), [Intel Core i7-12700 specifications](https://www.intel.com/content/www/us/en/products/sku/134591/intel-core-i7-12700-processor-25m-cache-up-to-4-90-ghz/specifications.html), and [Hexaly thread parameter documentation](https://www.hexaly.com/docs/last/modelerreference/standardlibrary/builtinfunctions.html).

## Cross-checks on other published benchmark families

The following are also vendor-reported results at one minute, not local runs:

| Family and size | Hexaly | OR-Tools | Metric |
|---|---:|---:|---|
| CVRP, 100–200 customers | 0.1% | 3.6% | Mean distance gap to BKS |
| CVRP, 800–1,000 customers | 0.9% | 5.4% | Mean distance gap to BKS |
| CVRPTW, 100 customers | 0.2% | 1.5% | Mean distance gap to BKS |
| CVRPTW, 1,000 customers | 4.7% | 14.4% | Mean distance gap to BKS |
| RCPSP, 300 tasks | 90% | 66% | Instances with makespan gap below 5% |

[CVRP source](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-capacitated-vehicle-routing-problem-cvrp), [CVRPTW source](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-capacitated-vehicle-routing-problem-with-time-windows-cvrptw), [RCPSP source](https://www.hexaly.com/benchmarks/hexaly-vs-or-tools-on-the-resource-constrained-project-scheduling-problem-rcpsp).

These checks support treating Hexaly as a strong incumbent-quality competitor. OR-Tools uses RoutingModel for routing and CP-SAT for RCPSP; the new local adapter covers Li-Lim RoutingModel only. The published Gurobi comparisons use particular MILP formulations, so their poor results cannot be transferred numerically to HiGHS or to our reduced hybrid subproblems. Ratios between optimality gaps are not runtime speedup factors.

## What our existing local runs show

The completed local cohorts currently cover only three 100-customer representatives (`lc101`, `lr101`, and `lrc101`), with three repetitions per method. They are useful for choosing the next experiment, not for claiming broad superiority.

| Local setting | CBLS ICN BKS hit rate | Specialized hybrid BKS hit rate | MetaStrategist balanced BKS hit rate |
|---|---:|---:|---:|
| 1 thread, 30 s | 33.3% | 44.4% | — |
| 8 threads, 30 s | 33.3% | 55.6% | 66.7% |
| 16 threads, 30 s | 33.3% | 66.7% | 66.7% |
| 8 threads, 60 s | 33.3% | 55.6% | 66.7% |
| 16 threads, 60 s | 33.3% | 66.7% | 66.7% |

The 8-thread and 16-thread hybrid runs reached an average best fleet gap of about one-third of a vehicle across the three instances. This gives us an encouraging small-instance baseline. It does not tell us how our methods scale to 400–1,000 customers, where the vendor's OR-Tools gaps become large and Hexaly reports sub-2% distance gaps.

The detailed 60-second, 16-worker comparison is more informative than a single aggregate. Each cell below uses the mean of three repetitions; distance gaps are shown alongside fleet gaps because fleet has priority.

| Profile | `lc101`: fleet / distance gap | `lr101`: fleet / distance gap | `lrc101`: fleet / distance gap |
|---|---|---|---|
| Reference fleet | 10 | 19 | 14 |
| CBLS learned ICN | 10 / 0.00% | 19 / +2.20% | 16.67 / +4.94% |
| Specialized ICN hybrid | 10 / 0.00% | 19 / 0.00% | 15 / +1.57% |
| Bridged ICN hybrid | 10 / 0.00% | 19 / +0.07% | 15.67 / +2.22% |
| MetaStrategist balanced | 10 / 0.00% | 19 / 0.00% | 16 / +1.57% |
| HiGHS native | 10 / 0.00% | 20.33 / +10.08% | 19 / +25.44% |

Source: [completed 60-second cohort](sintef-campaign-60s-16t-trio-bdc0c48-20261005/summary.toml). The `lc101` reference is already reached by the common insertion start, so it supplies no evidence of a search advantage. On `lrc101`, the specialized hybrid needs one extra vehicle (7.1% above the reference fleet); its 1.57% distance gap alone understates the lexicographic shortfall. CBLS learned ICN uses 16–17 vehicles there, versus 14 in the reference.

The [completed 300-second cohort](sintef-campaign-300s-16t-trio-bdc0c48-20261005/summary.toml) retains exactly the same three-instance means for CBLS learned ICN, the specialized hybrid and MetaStrategist balanced. Longer runs of the present policies have not closed those gaps. The immediate algorithmic target is fleet elimination on the mixed-location instance and better search diversity; additional CPU throughput alone is not demonstrated to solve that problem. This observation does not identify the underlying cause of the plateau.

The campaign now has a selectable OR-Tools 9.14.6206 adapter using Guided Local Search. The RoutingModel profile is one search thread, even when the surrounding campaign allocates a wider CPU envelope. It shares our insertion start and fleet-first objective, with integer-scaled costs and conservative time discretization; these choices mean it is a local competitor profile rather than an exact reproduction of the vendor's published OR-Tools model. Repetition labels do not change OR-Tools' random state, so those runs measure repeated timings of the same search configuration. OR-Tools is not installed in the current Python environment, so the adapter has not yet produced a measured trial. The pinned dependency is recorded in `LiLim/native/ortools/requirements.txt`.

## Expected ranking and confidence

- **Hexaly vs. OR-Tools on Li-Lim:** high confidence that Hexaly will be materially stronger from medium to large instances, because the vendor reports this directly on the same benchmark family. Our local reproduction still needs to check the objective, model, and hardware details.
- **Hexaly vs. our present CBLS/MetaStrategist:** medium confidence that Hexaly is ahead on 400–1,000-customer instances at 1–10 minutes; low confidence about the size of the gap. There is no full-corpus local CBLS result yet, and the current three-instance sample contains only 100-customer cases.
- **At 100 customers:** the specialized hybrid matches the reference on two of our three cases and remains one vehicle above it on the mixed-location case. Parity is plausible on a subset; a general Hexaly-parity claim is premature. One case is already solved by the common insertion start, and the vendor does not publish its fleet counts.
- **OR-Tools vs. CBLS:** the vendor's OR-Tools gaps at 400+ customers leave room for a strong multi-thread CBLS portfolio to compete, but this is a hypothesis. The local OR-Tools baseline will be single-threaded, and its BKS success, objective, and time-to-target must be measured on our validators.

The practical expectation is that Hexaly is a demanding target and likely wins on larger routing instances today. That does not imply the entire CBLS roadmap is required before a funding discussion: the decisive question is whether a small tuned CBLS/MetaStrategist portfolio can match Hexaly on a representative subset while clearly outperforming OR-Tools under a disclosed CPU budget.

## What Hexaly discloses about its techniques

The evidence below distinguishes current vendor documentation, historical descriptions and proposals for Julia Constraints. A general explanation of VNS or LNS on Hexaly's website is not proof that a specific operator runs in its current PDPTW benchmark. Papers hosted on its academic-citations page are not automatically descriptions of Hexaly internals.

- **Current structural modeling:** Hexaly exposes lists, sets and intervals, encourages deriving intermediate values instead of adding redundant decisions, and distinguishes structural constraints from high-priority violation objectives. [Official modeling principles](https://www.hexaly.com/docs/last/modelingprinciples/modelingprinciples.html).
- **Historical evaluation and search:** the LocalSolver 1.x paper describes feasibility-oriented structured moves, ejection-like paths/cycles, dependency-DAG incremental evaluation with commit/rollback, adaptive move sampling based on acceptance/improvement, and parallel seeded searches exchanging incumbents. These are public historical mechanisms, not a specification of Hexaly 15.0. [Authors' paper, sections 4.1–4.2 and search description](https://www.fredgardi.com/downloads/LocalSolver_4OR_2010.pdf).
- **Current hybrid engine:** the documentation names propagation, local search, branch-and-bound, automatic Dantzig–Wolfe reformulation and column/row generation among the techniques combined internally. It does not disclose their allocation to a particular Li-Lim run. [Official engine description](https://www.hexaly.com/docs/last/modelingprinciples/index.html).
- **Concrete structural repair:** a 2024 presentation describes detecting scheduling non-overlap structures and repairing infeasible moves with non-backtracking propagation. Another presentation describes detecting collection structures and obtaining lower bounds through extended MILP reformulations and branch-cut-and-price. These substantiate repair and decomposition capabilities; they do not establish their contribution to PDPTW primal quality. [SOAK 2024 technical abstracts](https://www.hexaly.com/events/hexaly-soak-2024).
- **What remains unknown:** current PDPTW move families, destroy sizes, adaptive weights, acceptance schedule, population coordination and cache layout are not identified in the sources above. Pair swaps, route-elimination ejection chains, regret insertion and adaptive LNS are useful candidate experiments for us, not confirmed Hexaly implementation details. Historical simulated-annealing controls should not be treated as current tuning advice: the LocalSolver 10.0 API already marked their influence insignificant and the parameter deprecated. [Historical API](https://www.hexaly.com/docs/10_0_20200709/java/localsolver/LSParam.html).

### Specific implications for our pilot

The inspected `LiLim/src/Hybrid.jl` sets `guide_infeasible=false`, uses a greedy plateau acceptance policy and disables random restarts (`rp=0`, `reset_fraction=0`). Its structured relocation reinserts one complete request and retains only immediately improving feasible results. This is a deliberately narrow baseline. `LiLim/src/MetaRepair.jl` repairs unions of whole routes with at most 20 visits, rebuilds the reduced MILP and currently supplies no MIP start. These are concrete source observations; their share of the measured performance gap still needs ablations.

| Priority | Proposed experiment | Connection to the current evidence | Acceptance condition |
|---|---|---|---|
| 1 | Route-elimination destroy/repair: empty a selected route, reinsert whole requests with regret-2/3 ordering, and permit bounded ejection chains | Directly targets the missing vehicle on `lrc101`; one-request improving relocation can miss compound improvements | Original-validator-approved fleet improvement; repeat on held-out mixed-location cases |
| 2 | Controlled diversification: perturbation/restarts, limited non-improving exploration, and bounded ICN-guided repair | Current controller disables restarts and infeasible guidance; current long runs stagnate | Better mean fleet/distance and time-to-target under the same wall/CPU budget |
| 3 | Worker-local incremental route/ICN state with trial/commit/rollback, reusable buffers and fused learned kernels | Historical dependency evaluation suggests a direction for our full-route score path; existing workspaces are a starting point | Differential identity to the frozen learned functions; measured lower allocations/GC and more useful moves per second |
| 4 | Adaptive MetaStrategist allocation by improvement per CPU-second, with diverse move policies and bounded incumbent exchanges | Historical adaptive move selection motivates an inexpensive alternative to fixed balanced allocations | Outperform the fixed portfolio across repeated seeds without exceeding its CPU budget |
| 5 | Improved RO repairs: MIP starts, safe per-worker model/workspace reuse where profitable, and fragments selected for fleet reduction | Existing whole-route meta-variable repair fits a hybrid design; rebuild overhead and fragment utility require measurement | Lower build share and more accepted global improvements; specialized/bridged semantic agreement |
| Later | Pool independently validated routes and solve a bounded set-partitioning master in HiGHS | Inspired by decomposition capabilities; this is our proposal rather than a disclosed Hexaly PDPTW recipe | Beat the simpler repair portfolio before committing to full column generation |

Preserve structural metadata until the neighborhood generator and RO planner have used it; lower to XCSP3Bridges only on its qualified perimeter. Keep the learned ICNs as the scored reference: optimize their execution through semantics-preserving fusion/incremental state, and use their residuals for repair guidance. A feasible final incumbent must always pass the original problem validator. No new strategy above has been implemented or benchmarked by this research pass.

## Next comparable experiment

1. Install the pinned OR-Tools version in an isolated Python environment and run `--methods=all,ortools_native` on 100-, 200-, 400-, 600-, 800-, and 1,000-customer representatives at 60 seconds, followed by 600 seconds on the hardest cases.
2. Run CBLS ICN, the best measured hybrid, and the best MetaStrategist allocation at 1, 8, and 16 threads with repeated independent seeds. Keep OR-Tools at its standard single-thread profile and report its one-core CPU use explicitly.
3. If a Hexaly license is available on this host, run the same instances at 60 and 600 seconds with default automatic threads and with the eight-thread request, each under recorded CPU affinity and measured CPU use. Use the eight physical P-cores for the controlled comparison; qualify a separate P-core-only 16-lane mask before interpreting SMT scaling. If it must run on the colleague's host, keep that result labeled as a remote machine comparison and use the shared original-problem validator.
4. Compare best, mean, median, spread, feasibility, fleet count, raw distance, BKS attainment, and time-to-target. Publish results only after every final solution and stored trajectory point passes the original Li-Lim validator.

## Sources

- [Hexaly vs. Google OR-Tools on Li-Lim PDPTW](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw)
- [Hexaly, Gurobi, and OR-Tools on Solomon/Gehring/Homberger CVRPTW](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-capacitated-vehicle-routing-problem-with-time-windows-cvrptw) — a different benchmark family that provides a separate directional check, not a direct Li-Lim comparison.
- [Hexaly, Gurobi, and OR-Tools on CVRPLIB CVRP](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-capacitated-vehicle-routing-problem-cvrp)
- [Hexaly and OR-Tools CP-SAT on RCPSP RG300](https://www.hexaly.com/benchmarks/hexaly-vs-or-tools-on-the-resource-constrained-project-scheduling-problem-rcpsp)
- [Google OR-Tools routing options](https://developers.google.com/optimization/routing/routing_options) — documents Guided Local Search and routing time limits.
- [AMD Ryzen 7 7700 specifications](https://www.amd.com/en/products/processors/desktops/ryzen/7000-series/amd-ryzen-7-7700.html)
- [Intel Core i7-12700 specifications](https://www.intel.com/content/www/us/en/products/sku/134591/intel-core-i7-12700-processor-25m-cache-up-to-4-90-ghz/specifications.html)
- [Hexaly `hxNbThreads` documentation](https://www.hexaly.com/docs/last/modelerreference/standardlibrary/builtinfunctions.html)
