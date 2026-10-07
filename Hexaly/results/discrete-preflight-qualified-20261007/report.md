# Hexaly benchmark preflight

Source: [Hexaly benchmark page](https://www.hexaly.com/benchmarks)

Checked: 2026-10-07T16:29:24.542. Catalogue entries: 20. Overall status: **incomplete_published_reproduction**.

This checks host readiness and original model qualification. It starts no comparative campaign. Unavailable optional solvers are skipped; unavailable models, data or validators are blockers.

## Host

OS: Linux, architecture: x86_64, Julia: 1.13.1, available CPU IDs: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, RAM: 31.1 GiB.

## Solver availability

| Solver | Status | Detail |
|---|---|---|
| cbls | available | PDPTW_functional_suite_passed |
| cplex | not_detected | CLI_not_found_API_installation_not_ruled_out |
| cpoptimizer | not_detected | CLI_not_found_API_installation_not_ruled_out |
| ghost | available | installation_probe_passed |
| gurobi | not_detected | CLI_not_found_API_installation_not_ruled_out |
| hexaly | skipped | license_unavailable |
| highs | available | PDPTW_functional_suite_passed |
| icn | available | PDPTW_functional_suite_passed |
| metastrategist | available | PDPTW_functional_suite_passed |
| ortools | available | installation_probe_passed |

## All benchmark entries

| Benchmark | Status | Checks still required |
|---|---|---|
| [CVRP](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-capacitated-vehicle-routing-problem-cvrp) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [CVRPTW](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-capacitated-vehicle-routing-problem-with-time-windows-cvrptw) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [RCPSP](https://www.hexaly.com/benchmarks/hexaly-vs-or-tools-on-the-resource-constrained-project-scheduling-problem-rcpsp) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [FJSP](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-flexible-job-shop-scheduling-problem-fjsp) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [SALBP](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-vs-cpo-simple-assembly-line-balancing-problem-salbp) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Aircraft landing](https://www.hexaly.com/benchmarks/hexaly-on-the-aircraft-landing-problem) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [PDPTW / Li-Lim](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw) | ready_available_solvers |  |
| [TSP](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-traveling-salesman-problem-tsp) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Team orienteering](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-team-orienteering-problem-top) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [Large CVRP](https://www.hexaly.com/benchmarks/large-scale-instances-capacitated-vehicle-routing-problem-cvrp) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Large JSSP](https://www.hexaly.com/benchmarks/hexaly-vs-cp-optimizer-vs-or-tools-on-the-job-shop-scheduling-problem-jssp) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [Vector bin packing](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-on-the-vector-bin-packing-problem-vbp) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [Bin packing with conflicts](https://www.hexaly.com/benchmarks/hexaly-gurobi-or-tools-bin-packing-problem-with-conflicts-bppc) | prepared_models_published_corpus_pending | model_not_qualified:ortools; original_corpus_and_references_unqualified |
| [Inventory routing](https://www.hexaly.com/benchmarks/hexaly-establishes-new-records-for-the-inventory-routing-problem-irp) | deferred_continuous |  |
| [Bin packing](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-bin-packing-problem) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Minimum sum-of-squares clustering](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-k-means-clustering-mssc) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [RCPSP records](https://www.hexaly.com/benchmarks/hexaly-breaks-records-for-the-resource-constrained-project-scheduling-problem-rcpsp) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Quadratic assignment](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-quadratic-assignment-problem) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Car sequencing with paint-shop batching](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-on-the-car-sequencing-problem-with-paint-shop-batching-constraints) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |
| [Maintenance scheduling](https://www.hexaly.com/benchmarks/hexaly-vs-gurobi-maintenance-scheduling-problem) | prepared_models_published_corpus_pending | no_published_solver_available; original_corpus_and_references_unqualified |

## Preparation and qualification

- ICN_bank: passed ()
- environment:Manifest.toml: passed ()
- environment:Project.toml: passed ()
- host: passed (prerequisites_present)
- setup: not_run (prepare_false)
- source:CBLS: passed ()
- source:CompositionalNetworks: passed ()
- source:ConstraintCommons: passed ()
- source:ConstraintDomains: passed ()
- source:ConstraintModels: passed ()
- source:ConstraintProgrammingExtensions: passed ()
- source:Constraints: passed ()
- source:LocalSearchSolvers: passed ()
- source:MetaStrategist: passed ()
- source:PatternFolds: passed ()
- source:QUBOConstraints: passed ()
- source:XCSP3Bridges: passed ()
- test:campaign_catalog.jl: passed (exit_code_0)
- test:cohort_checkout.jl: passed (exit_code_0)
- test:competitors.jl: passed (exit_code_0)
- test:ghost_frontend.jl: passed (exit_code_0)
- test:ghost_native.jl: passed (exit_code_0)
- test:hexaly_preflight.jl: passed (exit_code_0)
- test:hybrid.jl: passed (exit_code_0)
- test:icn_resources.jl: passed (exit_code_0)
- test:native_solvers.jl: passed (exit_code_0)
- test:ortools_native.jl: passed (exit_code_0)
- test:search_policies.jl: passed (exit_code_0)

The machine-readable report records asset hashes, corpus checks and per-solver qualification. A generic license probe does not qualify any unsupported benchmark family. Hexaly 15.0 is the local target; published experiments may use different versions, models or settings.

## Discrete toolkit qualification

Active entries: 19. IRP is deferred because original delivery quantities are continuous. Classical model/validator tests: **passed**. The committed instance selection is a functional smoke set, not the exact published cohorts. Complete published selections and reference records remain mandatory before claiming reproduction.

| Original input | Scope | Bytes |
|---|---|---|
| cvrp_A_n32_k5 | functional_smoke | verified |
| cvrptw_R101_25 | functional_smoke | verified |
| fjsp_Mk01 | functional_smoke | verified |
| jssp_ft06 | functional_smoke | verified |
| bpp_t60_00 | functional_smoke | verified |
| qap_esc32c | functional_smoke | verified |
| aircraft_airland1 | functional_smoke | verified |
| mssc_ruspini_k2 | functional_smoke | verified |
| rcpsp_Pat1 | functional_smoke | verified |
| salbp_n20_52 | functional_smoke | verified |
| carseq_035 | functional_smoke | verified |
| bppc_5_0_1 | functional_smoke | verified |
| vbp_a1_1 | functional_smoke | verified |
| top_p4_2_a | functional_smoke | verified |
| maintenance_example1 | functional_smoke | verified |

| Native adapter | Qualification | Scope |
|---|---|---|
| core | passed | see machine-readable evidence |
| ghost | passed | Julia_wrapper_BPP_direct_and_ICN_callbacks_only |
| hexaly | skipped | license_unavailable |
| original_samples | passed | format_and_error_zero_set_not_complete_published_corpus |
| ortools | passed | small_exact_integer_original_validator_qualification_not_performance |
