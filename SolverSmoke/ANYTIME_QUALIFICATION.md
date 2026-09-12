# Anytime qualification

32 small full-fleet runs produced independently valid incumbent traces. Thirty additional unreduced Li–Lim runs exercised sizes 100, 200, 400, 600, 800 and 1000 at a 0.2-second functional budget. Those short full-size runs are not quality comparisons.

The small fixture has two pickup/delivery pairs and two available vehicles. Its score was checked against all 120 token permutations. Times below are median observed discovery times over two repetitions (four for the HiGHS control, which also appears in preflight), after separate warm-up; they are not a solver ranking. JIT paths now warm twice for two seconds; the full-size preflight predates this warm-up correction and is functional evidence only. An initialization solution can have solve time zero, while its construction time remains in the raw trace.

| Engine | Profile | First feasible (s) |
|---|---|---:|
| lss_native | default | 0.00030135 |
| lss_native | assignment | 0.00026295 |
| lss_native | juls_greedy_like | 0.0002645 |
| lss_native | ghost_assignment_like | 0.00030205 |
| lss_native | timefold_late_acceptance_like | 0.0003622 |
| cbls_jump | default | 0.0004078 |
| cbls_jump | assignment | 0.0003633 |
| cbls_jump | juls_greedy_like | 0.0021466 |
| cbls_jump | ghost_assignment_like | 0.0003462 |
| cbls_jump | timefold_late_acceptance_like | 0.00042275 |
| timefold_native | default | 0.0025 |
| timefold_native | late_acceptance_400 | 0.002 |
| ghost_native_cpp | default_permutation | 0.0008835 |
| juls_native | greedy_swap | 0.0 |
| highs_control | compact_mip | 0.0071098 |

Validation: 187 scorer/trace/source checks, seven supervisor checks, 426 root checks including 397 historical checksums. Four CPUs throughout; the separate HPO was untouched.

[Raw traces and hashes](evidence/anytime-bf3f81e3-e1f5-4c03-86d3-c3664d61b034/summary.toml). [Protocol and limitations](ANYTIME.md).
