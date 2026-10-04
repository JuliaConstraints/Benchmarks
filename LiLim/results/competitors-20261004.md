# First Timefold Integration and Hexaly Preparation

On 4 October 2026, Timefold 2.6.0 Community was added to Li-Lim with a native
list model and incremental route scoring. A Hexaly model and launch/audit
contract are prepared, but no Hexaly result is reported. The
[protocol and limits](../COMPETITORS.md) are saved with the sources.

## Short comparison from a shared starting point

The time-aligned batch contains 90 Timefold trials: three instances, three
seeds, 1/2/4/8/16 workers and late acceptance sizes of 400 or 1,000. The 45
CBLS/ICN controls were rerun with the current kernel and workspaces at the same
five-second total budget. Shared preparation and model costs count against the
declared budget; loading and warmups are reported separately. Every final
solution and accepted incumbent is revalidated against the original problem.

Lexicographic medians across the three seeds:

| Instance | Published BKS | CBLS ICN, 1/2/4/8 workers | CBLS ICN, 16 workers | Timefold, 1/2/4/8/16 workers, LA 400 or 1,000 |
|---|---:|---:|---:|---:|
| LC101 | 10 / 828.94 | 10 / 828.937 | 10 / 828.937 | 10 / 828.937 |
| LR101 | 19 / 1650.80 | 20 / 1695.138 | 19 / 1685.959 | 21 / 1813.936 |
| LRC101 | 14 / 1708.80 | 17 / 1797.545 | 17 / 1793.425 | 19 / 2143.503 |

The best CBLS trial in this batch on LRC101 reaches 16 vehicles / 1790.489.
With a distance tolerance of `1e-6`, CBLS wins all 60 paired LR101/LRC101
comparisons against the two Timefold profiles and ties in all 30 LC101 cells.
LC101 already starts at its reference, so that success does not come from
solver discovery. No trial reaches the LR101 or LRC101 BKS. The few-unit
floating-point rounding differences in Timefold's LR101 values are not a useful
improvement over insertion.

## What these results support

The CBLS controller with complete-request reinsertion improves on insertion in
the two harder cases. The tested Timefold model, despite its incremental score
and active solver threads, makes little progress with its native moves at these
short budgets. Changing late acceptance from 400 to 1,000 is not enough here.
This points to neighborhoods and diversification as the next areas to examine;
it does not establish superiority over all Timefold formulations, the
Enterprise edition or an industrial confirmation corpus.

Timefold 2.6.0's default configuration can already be resolved with late
acceptance 400 and one accepted candidate per step. The explicit 400 profile is
therefore not counted as a distinct strategy. Earlier `timefold-default-*`
captures qualify the adapter before common-cost accounting was connected; they
are not used in this table or the five-second comparison figures.

At 16 workers, Timefold receives the same CPU affinity and runs sixteen
independent serial solvers in one JVM, with serial GC and a declared 2 GB maximum
heap. This is not its internal Enterprise parallelism. Median native-process
use is about 13.6–14.3 CPUs, depending on case and profile. All workers entered
search in the 81 instrumented trials, totalling 813,115,001 score calculations.
Native counters are retained so that this activity can be checked rather than
inferred from the requested thread count. Global Micrometer metrics warn about
a shared name across solvers; the retained work counters are thread-local.

Median Timefold process occupancy, with ranges across the three cases and two
profiles: 0.999–1.000 CPU at one worker, 1.934–1.971 at two, 3.717–3.808 at
four, 7.156–7.369 at eight, and 13.597–14.298 at sixteen. These clocks cover the
complete native call; they are not search time per worker.

CBLS and Timefold use different neighborhoods and different guidance errors
for infeasible states, but target the same original feasible solutions and
quality order. This compares the complete tested solvers and formulations.
Timefold's model, heap and hyperparameters have not yet been tuned by HPO. The
corpus is already exposed, execution order is not counterbalanced, and there
are only three seeds. Treat this as a pilot, not final commercial evidence.

## Hexaly and reference runtimes

The [pdptw.hxm model](../native/hexaly/pdptw.hxm) reads the same exchange format,
enforces the original constraints and optimizes fleet before unrounded distance.
Julia contract tests reject invalid routes, inconsistent scores and ambiguous
CPU allocations. The executable is absent, so native compilation, zero-time
injection, empty-route handling, construction/search clocks and anytime
callbacks still need qualification. The trial license is not activated.

The [SINTEF table](https://www.sintef.no/projectweb/top/pdptw/100-customers/)
provides solution quality, provenance and dates, but no uniform compute times or
comparable platforms. The figures show that quality alongside our locally
measured time to target. The 60- and 600-second Hexaly benchmark budgets are not
historical runtimes for the SINTEF BKS values.

## Sources and validation

Captures retain hashed sources, instances and JARs, budgets, preparation,
warmups, CPU use, seeds and trajectories. Exact measured adapter revisions are
in Git history: `9285fa8`, `12b8013`, `511e6aa` and `1314994`. The extension to
2/4/8 workers uses `b066616`. The CBLS controller uses the `8d0b329` kernel
cohort and the unchanged fingerprint of the recovered ICN functions. No data
from the earlier 369-trial campaign was replaced.

Qualification includes 480 exhaustive partitions with a separate oracle, four
Timefold FULL_ASSERT searches confirmed to start, change/cancellation checks on
all three instances, eleven Julia exchange/audit tests, and a new 16-thread
qualification of CBLS scores, workspaces and portfolios.

Comparative captures: `competitor-cbls-{1,2,4,8,16}t-*`,
`timefold-late-{1,2,4,8,16}t-*` and
`timefold-late1000-{1,2,4,8,16}t-*`. Exact-style and XKCD figures in PNG/PDF
are under `figures-20261004/competitors-quality*` and
`competitors-anytime*`. They show fleet, distance, reference-attainment rate
and the three-seed progression; rates of 0/33/67/100% are not statistical
extrapolations.
