# Pilot outcome — 12 September 2026

Campaign `f6c75ba8-3020-498d-b88d-541808a99667`, 11:42:08–11:45:10 UTC,
Julia 1.13.0, HiGHS.jl 1.25.2 / HiGHS 1.15.1, JuMP 1.31.2. Supervisor PID 50136;
children 43304, 38904, 33388, all restricted to CPUs 4–7 (0xF0). One Julia thread,
four configured HiGHS threads, one child at a time. HPO remained on CPUs 0–3.

| Instance | Requests | Insertion reference | HiGHS incumbent | Phase status |
|---|---:|---|---|---|
| lc101 | 53 | 10 vehicles / 828.9368669428341 | 10 / 828.9368669428343 | Fleet and distance OPTIMAL |
| lr101 | 53 | 22 / 1890.8785015920193 | 22 / 1890.8785015920193 | Fleet TIME_LIMIT, lower bound about 19 |
| lrc101 | 53 | 19 / 2231.969908612279 | 19 / 2231.969908612279 | Fleet TIME_LIMIT, lower bound about 10 |

The 30-second HiGHS budget excludes loading, construction and the insertion reference.
The measured solver-call duration also includes Julia overhead; the whole children took
40.78, 69.31 and 70.87 seconds, respectively. Peak private memory sampled by the supervisor
was 934.7, 1041.2 and 1047.1 MiB, below the 3 GiB watchdog threshold. All exited normally.
No watchdog timeout or memory kill occurred. No additional HPO was launched.

The compact model passed 21 tiny-case assertions against exhaustive route partitions.
Both all-in-one and split-route feasible cases, a one-vehicle infeasible case, zero
distance cycles, capacities, precedence and noninteger distances were exercised. The
model still needs broader formulation qualification before formal solver comparisons.

Each insertion result passed the independent ConstraintModels semantic validator. Its
MIP start also passed every algebraic constraint before HiGHS ran. Every stored baseline
and HiGHS solution was subsequently read back from original node IDs and independently
revalidated against the raw instance file: all six passed, including recomputed objectives.

The preceding campaign `a63c8d16-3bce-4a79-b586-178b65633055` remains archived as failed:
solving ran, but a call to an undefined version-reporting helper prevented final result
serialization. The helper was replaced with the actual installed wrapper version, and
all three failed attempts were rerun in fresh directories. Those failed records are not
treated as completed benchmark results.

The successful campaign's `report.md` links the SINTEF best-known results and distinguishes
the insertion reference from the warm-started HiGHS run. HiGHS did not improve that initial
reference within this budget. In particular, the latter two runs did not prove their fleet
optimum and therefore did not enter the distance-minimization phase. These observations
are not evidence of CBLS, GHOST, JuLS, Timefold or Hexaly performance: their specialized
Li–Lim adapters were not run. Shared memory/cache/frequency also prevent an isolated
performance interpretation of this small diagnostic run.
