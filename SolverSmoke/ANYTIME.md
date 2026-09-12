# Li–Lim anytime diagnostics

This extension keeps the original 33-run functional pilot and its evidence intact.
It adds accepted-incumbent traces, full-fleet formulations, five generated LSS
profiles through both native and CBLS/JuMP paths, and a resumable Julia campaign.
It is a diagnostic baseline, not a final ranking or a claim of optimal native modeling.

## Measurement contract

- Every feasible strict improvement retains the complete assignment, monotonic
  observation time, solve time, initialization/search phase and objective.
- The Julia validator independently checks every recorded solution: all visits,
  pair precedence and same vehicle, capacity, time windows and depot return.
- The objectives are lexicographic: used vehicles, then unrounded Euclidean
  distance. Scalar engines use `M * vehicles + distance`, where
  `M = 2 * customers * maximum_pairwise_distance + 1`; this strictly exceeds
  every complete route collection's distance. Timefold uses separate hard,
  medium (fleet) and soft (distance) scores.
- First feasible, first attainment of a common target, best discovery time,
  API duration, model construction and subprocess wall duration are different
  quantities. A solve duration is never substituted for a missing discovery time.
- Traces retain budget overruns, but only events within the solve budget can
  reach a comparison target. Initialization cost remains visible in end-to-end
  times. A future all-inclusive deadline comparison must use those times instead.
- Timefold records its native millisecond event clock and wrapper monotonic time.
  LSS observes pool admissions, GHOST observes search-unit best snapshots, and
  JuLS observes its accepted best solution (including feasible initialization).
  Candidate objective evaluations are not incumbent events.
- HiGHS uses its improving-MIP-solution callback. Optimal termination provides
  an upper bound on proof time, separately from discovery. If presolve returns
  a solution without a callback, its final routes are kept and discovery time is
  explicitly missing.
- Callbacks serialize only incumbent records, not candidate evaluation. Their
  overhead has not been quantified; native/JuMP overhead equivalence is not claimed.
- JIT paths use two separate two-second warm-up solves on the synthetic fixture.
  The first development attempt used 0.05 seconds, which could expire during
  compilation before reaching a move. Its timing evidence is superseded.
- `anytime_report.jl` uses the best eligible observed quality per instance as a
  shared **post-hoc** target. That target is not asserted optimal and may change
  when additional results arrive. Preserve each report for provenance. Unreached
  targets are censored; do not average only successful runs to rank engines.

## Profiles and fidelity

| Generated LSS profile (native and CBLS) | Implemented composition | Comparison boundary |
|---|---|---|
| `default` | Existing worst-variable / assignment+swap / compatibility acceptance / default tabu and universal restart | LSS reference, not the whole generator |
| `assignment` | Default profile restricted to assignment depth zero | LSS ablation |
| `juls_greedy_like` | Greedy acceptance, assignment+swap proposals, no tabu or random restart | Partial analogue only: JuLS routing evaluates its whole swap neighborhood; LSS selects a variable first and additionally allows assignments |
| `ghost_assignment_like` | Remaining-worst selector, assignment, 10% plateau rejection, accepted-move tabu, exhaustion reset | GHOST scalar adaptive-search parameters; **not** an equivalence to the permutation-native routing path |
| `timefold_late_acceptance_like` | History length 400, greedy/late acceptance, no tabu or random restart | Acceptance-family analogue; different move generation, initialization, history and tie semantics |

GHOST parameter reference: local source revision
`4627927003f062bd9a5c0bcdbd0a7a0f377312b8`; local tenure
`max(min(5,n-1), n÷5)+1`, selected tenure 0, reset threshold equal to local
tenure, reset count `max(2,ceil(0.1n))`, full reset every `n` resets. Best-of-10
initialization is not reproduced in the LSS analogue. The exact instrumented
source hashes, rather than a resemblance label, identify the tested implementation.

Native paths: Timefold 2.6.0 default plus explicitly configured late acceptance
400 / accepted-count limit 1; GHOST default permutation search; JuLS greedy swap
with no CP filter; HiGHS compact MIP control. Five LSS profiles paired across two
frontends plus these five native/control configurations give 15 configurations.
Timefold's default is not asserted to equal the explicit late-acceptance profile.

The native routing models use lists (Timefold) or customer/separator permutations
(GHOST, JuLS). LSS/CBLS currently use finite integer assignments with explicit
permutation and routing errors. Initializers and neighborhoods therefore differ.
Full-route recomputation is still used; distance matrices are cached. JuLS's
error is `ceil(total violation)` before its 10000 penalty, keeping zero exact;
this changes its search landscape while leaving feasible-route objectives intact.
Incremental scoring, route-aware LSS decisions and stronger native routing
neighborhoods must precede a company-facing performance ranking.

Not available in this full-routing campaign: GHOST/JuMP's custom route objective,
Timefold/JuMP and JuLS/JuMP. The old GHOST/JuMP ILP qualification remains available.
Hexaly and an asserted Hexaly-like profile are excluded: no license activation
or information about undisclosed internal strategies is assumed.

## Run and resume (Julia only)

All entry points require `SOLVER_COMPARISON_CPUS=4,5,6,7`,
`SOLVER_COMPARISON_CPU_LIMIT=4`, and at most four Julia threads. Use
`--startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1
--project=SolverSmoke`. JuLS's child process uses its own Julia 1.11 environment.
No Python orchestration is used.

1. `scripts/instrument.jl` patches only private vendor copies, with checked
   insertion anchors and optional observers disabled by default. Run this after
   the existing setup. Shared packages and the other HPO are not modified.
2. Rebuild with `scripts/build_timefold.jl` and
   `scripts/build_ghost_portable.jl anytime`.
3. `scripts/anytime_checks.jl` tests scorer/validator agreement and concurrent
   incumbent collection. `scripts/anytime_qualify.jl` tests generated profiles on
   a small exhaustive-oracle fixture. `scripts/anytime_preflight.jl` checks
   actual unreduced instances from all six Li–Lim sizes and the HiGHS callback.
4. `scripts/anytime_prepare.jl --plan-only` reads only the catalogue;
   `scripts/anytime_prepare.jl` explicitly opts into acquiring all 354 instances
   through COPInstances's checksum and receipt protocol. No data redistribution
   right is inferred; raw files remain ignored by Git.
5. After successful qualification, `scripts/anytime_seal.jl QUALIFICATION_DIR
   PREFLIGHT_DIR` verifies and archives evidence and seals the tested code/runtime
   hash. Commit and push to private GitLab before launch.
6. `scripts/anytime_campaign.jl` starts a new UUID campaign. Passing its directory
   resumes the identical committed, qualified revision. One process runs at a time
   under the shared benchmark lock; affinity 0xF0 is checked in the controller and
   each worker. The other HPO's CPUs 0–3 remain untouched.
   Workers execute their archived source/environment/binary snapshot, so later
   edits to the working checkout cannot silently alter an ongoing campaign.
7. Creating `STOP` in the campaign directory stops between jobs. Remove it before
   resuming. Completed jobs are retained. A failed/censored attempt is also retained;
   rerunning failures requires a new campaign, never overwriting old evidence.
8. `scripts/anytime_report.jl CAMPAIGN_DIR` produces the independent timing report.

Each budget is a fresh run: 30, 60, 120 and 240 seconds, with seeds/repetitions
1, 2 and 3. These are not four truncations of a single long trajectory; algorithms
can depend on their termination budget. GHOST's seed is not controlled and its
repetitions cannot be paired by RNG with other engines. Parallel scheduling and
wall-time termination also prevent strict seed reproducibility elsewhere.

The full grid is **63,720 runs**, representing **82.97 days of sequential search
budgets**, plus startup/initialization, less early terminations. Budgets increase
in order; sizes are interleaved and the principal native engines get early slots.
The process-wall watchdog is budget + 180 seconds, including runtime startup and
warm-up. A watchdog termination is recorded as resource censoring, not a failed
solution-quality comparison. Solver time overruns remain separately visible.

Current resource envelope: four logical CPUs globally, Timefold Community's
single search thread, one-GiB JVM heap, serial GC, helper libraries limited to one
thread. A worker exceeding four GiB RSS, or a host falling below 512 MiB free RAM,
is stopped and explicitly resource-censored. These limits must accompany every
comparison; a memory-censored run is not counted as a solver-quality loss.
Co-running HPO still shares memory/cache/frequency; this is not an isolated
machine performance measurement. Raw traces and inputs, source snapshots, hashes,
status markers, process times and logs remain in DrWatson data directories.

## Primary API references

- [Timefold 2.6.0 incumbent event and elapsed time](https://raw.githubusercontent.com/TimefoldAI/timefold-solver/v2.6.0/core/src/main/java/ai/timefold/solver/core/api/solver/event/BestSolutionChangedEvent.java)
- [Timefold explicit late acceptance configuration](https://raw.githubusercontent.com/TimefoldAI/timefold-solver/v2.6.0/core/src/main/java/ai/timefold/solver/core/config/localsearch/decider/acceptor/LocalSearchAcceptorConfig.java)
- JuLS incumbent hook: pinned vendor `src/model/model.jl`, upstream
  `5033406449e48b7aae1cf5ac45ac12cf8a26ff02`, plus recorded observer patch.
- HiGHS.jl 1.25.2 `CallbackFunction` and generated `HighsCallbackDataOut` API;
  callback behavior is exercised by the local qualification.
