# CBLS, ICNs, and MetaStrategist: Throughput and Preparation

Diagnostic from 4 October 2026 on an Intel i7-12700, Julia 1.13.1. Garbage
collection was a real bottleneck. Private buffers and a corrected search kernel
now keep nearly all CPU time available to the 16 LC101 trajectories. The three
recovered ICN decoders remain in the learned profile; their functions and weights
were not changed.

## Learned ICN functions used by the route scorer

The scorer loads witness entries 4, 2, and 52 from the frozen
`ConstraintLearningBenchmarks/.../weights.toml` bank. Each witness is built with
`learnable_composition(...; max_depth=1)` and checked against its saved schema
hash and valid-weight predicate. These are recovered, manually selected
compositions; this campaign does not retrain them.

| Witness | Learned decoded function | Li-Lim constraint mapping |
|---:|---|---|
| 4 | `condition_residual(sum(x))`, parameterized by the relation and bound | Fleet limit, each time-window limit, prefix-load bounds, and return-load equality |
| 2 | `sum(elementwise_sum([count_great_left(x), count_less_left(x)]))` | Pickup and delivery route labels must be equal; this counts pairwise disagreements |
| 52 | `sum(count_great_left(x))`, with the witness's nondecreasing, no-offset restriction | Pickup position must precede delivery; the two positions are distinct, so nondecreasing is strict order |

The baseline `cbls_icn` profile calls these decoders inside the candidate scorer.
`cbls_icn_fused_scalar` keeps the learned route-equality and order decoders but
groups scalar residuals through the learned sum-condition decoder.
`cbls_icn_fused_all` additionally bypasses the two per-pair decoders and feeds
direct pair-violation indicators into that aggregate decoder. The exhaustive
small-domain checks in `test/icn_resources.jl` establish equality with the direct
score on that qualified domain; they do not replace the baseline learned profile.
These two fused profiles are not present in any result capture currently
published under `LiLim/results`; no throughput or solution-quality gain is
claimed for them yet. The full-corpus campaign configuration includes both so
their effect can be measured against the unfused ICN scorer.

The source gives a concrete decoder-call hypothesis to test. For a valid
successor assignment with `N` customer nodes, `V` routes and `P` pickup-delivery
pairs, the baseline makes `1 + 3N + 2V + 2P` learned-composition calls per score:
one fleet check, three scalar checks per customer, two return checks per route,
and two pair checks per request. Scalar fusion reduces this to `1 + 2P`; full
fusion reduces it to one aggregate call. At 100 requests (`N = 200`, `P = 100`),
that is `801 + 2V`, 201 and 1 calls respectively. These are source-derived call
counts, not elapsed-time or throughput results; route decoding and residual
accumulation remain, and the campaign must establish whether fusion helps.

## Result at 16 threads

Three seeds, five seconds per trial, same instance, moves and ICN bank, Julia
`-O1`, GC/BLAS/OMP limited to one thread, fixed affinity. Medians:

| Stage | Active CPUs / 16 | Reinsertion candidates per second | Allocated bytes per call | Call GC time |
|---|---:|---:|---:|---:|
| Before optimization | 6.41 | 2.00 million | 36.09 GB | 3.328 s |
| ICN and move buffers | 14.74 | 23.07 million | 3.66 GB | 0.490 s |
| Typed kernel and route buffers | 15.97 | 26.59 million | 0.256 GB | 0.171 s |

Throughput increased by 13.3× and allocations fell by about 141×. The published
GC time includes a forced full collection inside `run_case`, before its search
timer; it is not just hot-loop pauses. CPU occupancy uses worker and process CPU
clocks rather than Julia profiler utilization, which can include GC waiting.
The runs used 97.4–100% of each worker at 16 threads.

The additional `throughput-hot-gc-16t-20261004.toml` capture instruments the
global GC counter immediately around the same search interval. Across three
seeds it records **zero GC seconds during search**, 15.985–15.986 active CPUs,
254–256 MB allocated and 26.35–26.59 million candidates per second. The full
call's 0.165–0.167 seconds of GC occur outside that interval. These are
five-second trials; remaining allocations may trigger collection in longer runs.
This instrumentation is saved in commit `80fd298` and does not change the score,
moves or acceptance policy.

LC101 is a throughput control: the insertion start already has the best-known
quality. This gain demonstrates speed, not improved solutions or a solver win.

## Scaling

| Threads | Active CPUs, first batch | Candidates/s | Allocations, first batch |
|---|---:|---:|---:|
| 1 | 1.00 | 2.60 million | 49 MB |
| 2 | 1.99 | 4.83 million | 68 MB |
| 4 | 3.91 | 9.85 million | 1.61 GB |
| 8 | 7.99 | 19.87 million | 197 MB |
| 16 | 15.97 | 26.59 million | 256 MB |

At four threads, a second batch with the same sources records 3.997 active CPUs
and 113–116 MB allocated. Both batches are retained in the plot. The first
batch's allocation spike does not recur in the next capture; its cause remains
unknown. ConstraintModels loading fell from 4.4 to 1.6 seconds between sessions,
showing that available compilation-cache state changed. That alone does not
prove the cache caused the allocation spike.

The first eight lanes use eight distinct P-cores. At sixteen, four E-cores and
four SMT lanes are added; 100% occupancy does not guarantee throughput to scale
with logical lanes.

## Changes already measured

- Successor, position, route and ICN argument arrays belong to each worker. They
  are reused without mutable sharing between trajectories.
- Reinsertion candidates use buffers; only a retained improvement gets an
  independent copy.
- Current-route decoding uses a workspace. Snapshots passed to meta-variables
  and retained solutions still own their data.
- The LocalSearchSolvers kernel separates the concrete iterator from the choice
  between moves and swaps. Iteration results were not correctly typed in the
  shared loop and previously allocated once per candidate.
- A structurally invalid neighbor now returns its infeasibility score without
  constructing an exception and backtrace.

The first kernel correction alone did not reduce global GC at sixteen threads.
The intermediate `throughput-iterators-*` captures document that result; reusable
route decoding removed the next measured cost.

## 5 October: ICN scorer allocation correction

The zero-allocation unit check exposed 3,216 bytes per baseline ICN score on its
small route fixture. Allocation profiling attributed the cost to repeated
learned scalar-composition calls through the scorer's generic dispatch path.
Inlining `ICNScoring.scalar` lets Julia specialize those calls; the same fixture
then measures zero bytes per score for the baseline ICN, naïve, direct, scalar-
fused and fully fused backends. The complete resource test passes, including its
stale-world worker regression. This qualifies the scorer-level fix; the next
campaign must still measure allocations and GC during full Li-Lim searches.

## PerfChecker and SnoopCompile runs

PerfChecker 1.0.0-rc1, commit `1cc09a98db569b382f91dc10f6a569c1c728b6aa`,
collects CPU, wall-time and allocation profiles in isolated workers. The three
complete captures are retained: baseline, first buffers and final. The large
allocations for positions, small ICN arguments and route copies disappear from
the profiles. The latest capture still detects a small allocation while
iterating the depth plan; these samples are not an exhaustive byte inventory.
The user's pre-existing PerfChecker development checkout remains untouched.
The controller uses a separate pinned source and does not alter the solver
environment.

### 5 October post-fix capture

The first PerfChecker pass after inlining `ICNScoring.scalar` used Benchmarks
`acc5cf95` and the fixed scorer source hash recorded in
[`perfchecker-cbls-icn-postfix-20261005.toml`](perfchecker-cbls-icn-postfix-20261005.toml).
It ran on one Julia/GC thread with the original frozen solver and controller
environments. The CPU profiler exported 202 stack rows over 9.095 seconds and
the wall profiler exported 79 stack rows over 6.502 seconds; both show the
learned `ErrorBackend` in the active search path.

The third, allocation-profile collector exited with `Allocation profiler found
no target source sites`. PerfChecker 1.0.0-rc1 therefore saved no allocation
table and did not set `complete = true`. This is an incomplete capture, not a
zero-allocation result. The collector's sampling/filter behavior needs a
separate investigation before a future capture; this pass did not change its
sampling rate, budget, controller, or solver environment. The partial record
and process resource envelopes are retained for provenance.

SnoopCompile 3.2.9 / SnoopCompileCore 3.1.3 instrumented a sixteen-thread
session. Decoding the bank induced about 4,067 method instances; the first naive
CBLS preparation about 14,406, then ICN 739 and bridges 3,218. On the second
pass, ICN, both hybrids, HiGHS and portfolios induced no new instances; naive
CBLS induced 80. Compilation durations from multiple threads add together and
are not wall time. Published Snoop totals use exclusive per-method durations;
recursively summing inclusive durations would double-count nested inference.

After warmup, preparing a parent takes about 0.5 ms, preparing a MetaStrategist
plan 0.2 ms and reusing its kernel with a new context about 0.2 ms. On the small
qualified fragment, hot repairs cost about 17 ms specialized and 60 ms bridged,
with no new inference. Modules are not reloaded on every repair. Building a new
JuMP/HiGHS model remains a real cost to measure and potentially reuse, depending
on fragment shape.

The two-second warmups also contain two seconds of search; they must not be
described as two seconds of compilation. Part of the very first load depends on
existing package caches, so this observation does not attribute a cold-start
gain to the buffers.

Keep packages and the ICN bank loaded once, prepare only the needed variants,
retain workers, reuse immutable plans with private contexts and lane-owned
buffers. No sysimage or AOT precompilation of the dynamic model has been
installed.

## Qualification, processes and next comparison

ICN scores and distances are exhaustively compared against the original
validator and direct score on the qualified domains. Tests also check zero
allocations in hot scoring and decoding, isolation of all sixteen workspaces,
owned snapshots, reinsertions and portfolios. LocalSearchSolvers passes 10,432
strategy contracts and 782 performance contracts after the kernel correction.

CBLS/LocalSearchSolvers also supports `Distributed` workers and
`process_threads_map`, with separate garbage collectors. The current
MetaStrategist pilot uses threads and does not yet implement a distributed
phase. The process comparison follows the multithread correction, using a warm
pool and the same CPU ceiling while publishing launch, serialization, memory
and GC costs.

The [competitor protocol](../config/competitors.toml) adds Timefold Community
with incremental route scoring and prepares Hexaly with original constraints,
fleet first and unrounded distance second. The
[SINTEF table](https://www.sintef.no/projectweb/top/pdptw/100-customers/) does
not guarantee per-instance reference runtimes: time to the published target
must be measured locally. Rounded BKS values remain quality targets, not time
or optimality certificates.

Measured sources: Benchmarks `972fa7859dfa1c89c8874275168f9e3dad21e63d`,
LocalSearchSolvers `8d0b3291420f49950cfda4e890899f384b8b7239`. Each capture records
the rest of the cohort and solver fingerprints. The initial 369-trial campaign
retains its cohort and [quality report](icn-threads-20261004.md).

Essential captures: `throughput-final-*`, `throughput-final-repeat-4t-*`,
`throughput-hot-gc-16t-*`, `perfchecker-final-*` and
`snoop-startup-exclusive-16t-*` in this directory.
Exact-style and XKCD figures are produced by `icn_performance_plots.jl`. The
success, anytime and time-to-BKS plots remain in `figures-20261004`, separate
from this throughput diagnostic.
