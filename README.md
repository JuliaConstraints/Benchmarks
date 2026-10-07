# Julia Constraints Benchmarks

Comparison kit for CBLS/ICN, LocalSearchSolvers, MetaStrategist, HiGHS, OR-Tools,
GHOST.jl, Timefold and optional commercial solvers. Public text and reports are in English.

## Start here

Requires Julia **1.13.1** and Git. Python **3.12** enables OR-Tools; Java **21**
with its compiler module enables Timefold. Linux also requires `taskset` and `lscpu`.

```sh
git clone --config core.autocrlf=false --single-branch --branch main https://github.com/JuliaConstraints/Benchmarks.git ~/Gits/JuliaConstraintsBenchmarks
cd ~/Gits/JuliaConstraintsBenchmarks
julia --startup-file=no scripts/colleague.jl preflight
```

The preflight checks **all kit solvers**, prepares missing permitted dependencies,
runs bounded functional tests and writes `report.md`/`report.toml`. Existing
installations are reused. Missing optional solvers are skipped. Installed solvers
without a qualified adapter are reported separately. Hexaly is optional.
No comparison campaign starts during preflight.

| Solver | Functional coverage |
|---|---|
| CBLS / LocalSearchSolvers / ICN | Li-Lim and 16 discrete model families; existing tabu/reset/acceptance policies |
| MetaStrategist | Independent lanes and mixed HiGHS repair portfolios |
| HiGHS / OR-Tools | Li-Lim; eight classical integer models (OR-Tools CP-SAT) |
| GHOST.jl | Julia JuMP/MOI wrapper; Li-Lim and BPP direct/ICN callbacks |
| Timefold 2.6 Community | Li-Lim incremental scoring and native search |
| Hexaly 15.0 | Existing licensed installation; native qualification runs when available |
| JuLS, Gurobi, CPLEX, CP Optimizer | Inventory; current public adapters remain unqualified |

## Run and inspect

- [Li-Lim guide](LiLim/PUBLIC.md): first comparison, resume, plots and evidence export.
- [Discrete catalogue guide](Hexaly/README.md): other families and explicit instance selection.
- [Published protocols](LiLim/config/hexaly-benchmark-catalog.toml): 20 entries; 19 active, continuous IRP deferred.
- [Local functional checks](LiLim/results/solver-preflight-20261007/report.md): available solvers, skipped solvers and remaining gaps.

Exit codes: **0** ready for available kit solvers (or inventory completed),
**1** failed check, **2** incomplete solver/input coverage.
Li-Lim is qualified with available solvers. Complete published selections and
reference records for the other families remain pending; see the generated report.

```sh
julia --startup-file=no scripts/colleague.jl preflight --prepare=false --qualify=false
julia --startup-file=no scripts/colleague.jl lilim --instances=lc101 --methods=cbls_icn,ortools_native,ghost_icn,hexaly_native --budget=8 --threads=1 --seeds=41 --output=LiLim/results/local-8s
```

Raw data and trials stay outside Git. Source cohorts, instance hashes, original
validators and sealed results identify every run. Existing study code and historical
reports remain in their directories.

Earlier package studies remain in [ConstraintCommons](archive/legacy/ConstraintCommons),
[ConstraintDomains](archive/legacy/ConstraintDomains), [ConstraintLearning](archive/legacy/ConstraintLearning)
and [PatternFolds](archive/legacy/PatternFolds).
