# DrWatson migration qualification — 12 September 2026

Environment: Windows, Julia 1.13.0, DrWatson 2.19.1. Sequential checks used CPU 4
(one Julia thread) and CPUs 4–5 (two Julia threads). The coordinated HPO PID 16236
remained on CPUs 0–3 (affinity 0xF); no files in its repository were modified.

| Scope | Verified outcome | Evidence relative to repository root |
|---|---|---|
| Root project and persistence, one thread | 420 checks: activation, immutable completion/failure, catalogue, 397 historical file hashes | `data/sims/orchestration/8c9b7177-d7ba-4155-8f6d-8bea1ae3f8a5/step-1.log` |
| Root project and persistence, two threads | Same 420 checks pass | `data/sims/orchestration/9939bbd9-fd0a-4cb6-b506-f540fa6c4de0/step-1.log` |
| ILP infrastructure | 61 checks pass with one and two threads; zero external solver runs | [Solver qualification](../Solvers/docs/qualification.md) |
| Final package batch smoke, one thread | 15/15 scenario checks; scalar and batched output validation | `data/sims/packages/2a8b61cd-c272-4f11-ae10-1644b1f967e0` |
| Final package batch measurements, two threads | 15/15 scenario checks, 50 samples each; 14 resolved timing rows, one explicitly unresolved | `data/sims/packages/05eb0230-f6fe-4ea9-a00b-02a9a2faf29a` |
| Package report | Completion/result/source/environment digests verified before summarizing that single attempt | `data/exp_pro/packages/a6107e20-e5c2-40ba-900e-ec936bc1e908/report.md` |
| ILP plan | 228 combinations, zero solves | `Solvers/data/plans/3b944b99-f97c-475c-aafe-a3f7ea475cbe` |

The unresolved `domains.empty` kernel is retained as a semantic check; its timing is
not presented as zero-cost evidence. Initial schema-1 measurements exposed the timer
floor and remain archived. Final schema-2 timing uses batches with independent inputs
and retained results; [method.md](method.md) defines the normalization and its limits.
No before/after performance claim is made between these different measurement schemas.

All scripts are Julia. Setup resolved only the root and Solvers environments offline
from the existing cache, without automatic precompilation. Shared package source
checkouts, HPO environments, Git branches/index and campaign artifacts were untouched.
Each scientific environment has its own pinned Manifest; Julia 1.10 is not yet tested.

The archive migration preserved all 397 original files byte for byte. The empty
ConstraintLearning placeholder and historical version/IDE campaigns are excluded from
the active launcher. They are not claimed to have been ported or qualified. Current
package diagnostics are new, smaller workloads, not reproductions of the old CSV rows.

The local branch remains `feat/solver-comparison-ilp`. No commit or push was made.
Private GitLab publication is still pending after the earlier SSH read returned
`Internal API unreachable`; no GitLab project existence or visibility is assumed.

These checks qualify infrastructure and bounded diagnostics only. They do not qualify
the pending solver adapters, native/JuMP equivalence, solver multithreading, a solver
ranking, a performance regression, or an HPO campaign. Shared cache/memory/frequency
prevent an isolated-performance interpretation of this session.
