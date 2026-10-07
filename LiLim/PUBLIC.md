# Reproducible Li-Lim comparison handoff

This Linux kit compares the same original PDPTW instances, a common feasible
insertion start, a shared wall-clock budget, and a fleet-first objective followed
by unrounded Euclidean distance. Every exported solution and every trajectory
point is checked by the original ConstraintModels validator. It is a local
comparison, not an identical reproduction of the vendor's published experiment.

Prerequisites: **Julia 1.13.1**, Git, Python 3.12 with `venv`, `unzip`, and Linux
`taskset`/`lscpu`. No private repository, account or token is required.

```sh
git clone --single-branch --branch bench/lilim-20261007 https://github.com/JuliaConstraints/Benchmarks.git ~/Gits/JuliaConstraintsBenchmarks
cd ~/Gits/JuliaConstraintsBenchmarks
julia LiLim/scripts/colleague.jl setup
julia LiLim/scripts/colleague.jl qualify
julia LiLim/scripts/colleague.jl run --budget=60 --threads=1 --output=LiLim/results/local-60s-1t
```

Setup clones the twelve public package snapshots into
`~/.julia/dev/JuliaConstraintsBench`, installs the frozen Julia environments and
OR-Tools 9.14.6206 in a dedicated Python environment, downloads the six official
SINTEF archives, and checks all 354 instance hashes. Existing mismatched or dirty
checkouts are preserved and rejected. `workspace-cohort.toml` records public
commit IDs, their original qualified commits, and identical runtime-file hashes.
Public snapshots exclude private history, research logs and bulk artifacts.
The three recovered ICN witness recipes are bundled with their provenance;
their weights are unchanged and were not retrained for this comparison.

`qualify` runs actual OR-Tools GLS searches on tiny instances, including unit
capacity, pickup precedence with zero travel, nonzero depot service and empty
vehicles; it also checks ICN scoring, hybrid behavior and existing strategies.
The OR-Tools adapter uses conservative integer time scaling (10,000) and
distance scaling (1,000,000). The original double-precision validator remains
authoritative. Rounding is a documented modeling difference.

The default diagnostic uses LC101, LR101 and LRC101 with repetition labels
41/42/43. OR-Tools RoutingModel is **single-threaded**; those labels do not change
its GLS random seed. Its repetitions measure variation in elapsed execution.
CBLS workers use independent seeds. Import/model/common-start time is included
inside each trial budget; Julia warmup is measured separately. The exposed trio
is not a held-out confirmation corpus and does not justify general superiority.

For wider comparisons, use `--threads=8` or `--threads=16`. Defaults then include
CBLS strategy mix and two MetaStrategist portfolios alongside ICN, specialized
and XCSP3 hybrids, HiGHS and OR-Tools. Each method runs serially as a separate
trial. The launcher chooses one logical CPU per physical core before SMT
siblings; on hybrid CPUs this does not distinguish P/E cores. For controlled
affinity pass `--cpus=8,10,0,2,4,6,12,14` (replace with your host's CPU IDs).
OR-Tools always uses just the first selected CPU. CPU time and GC evidence are
reported; requested worker counts are not claimed to be active CPU counts.

```sh
julia LiLim/scripts/colleague.jl run --budget=8 --threads=1 --output=LiLim/results/smoke-8s-1t
julia LiLim/scripts/colleague.jl run --budget=60 --threads=8 --output=LiLim/results/local-60s-8t
julia LiLim/scripts/colleague.jl run --budget=600 --threads=8 --output=LiLim/results/local-600s-8t
```

Use `--methods=...`, `--instances=...` (or `all`) and `--seeds=...` to choose a
bounded cohort. Do not start the full solver/instance/seed/width grid blindly.
To stop after the current trial, create `OUTPUT/STOP_AFTER_TRIAL`; remove that
file and repeat the exact command with `--resume=true`. Seals and the campaign
fingerprint prevent mixing sources, budgets or earlier evidence.

## Licensed Hexaly host

Target: Hexaly Optimizer **15.0**, with its **Modeler command-line executable**
(`hexaly`, accepting `.hxm` files); Studio is not required. Install and activate
the colleague's license through Hexaly's own distribution. No binary or license
is redistributed here. The model and exchange audit are prepared, but native
Hexaly compilation/search are **not yet qualified on our machine**.
The supplied native test is a gate: failures must be fixed and requalified
before comparative Hexaly results can be reported.

```sh
julia LiLim/scripts/colleague.jl qualify --hexaly=/path/to/hexaly
julia LiLim/scripts/colleague.jl run --budget=60 --threads=8 --hexaly=/path/to/hexaly --methods=hexaly_native,ortools_native,cbls_icn,hybrid_specialized_icn,hybrid_bridged_icn,mixed_balanced --output=LiLim/results/hexaly-60s-8t
```

The Hexaly model minimizes fleet then distance in a documented 5:1 allocation of
the remaining search time, preserving original continuous feasibility. This
differs from a distance-only vendor model. Model setup time counts in the common
budget; late improvements are censored. Native qualification must be run first.
On a different Hexaly version, retain the version and qualify again rather
than silently describing it as a 15.0 reproduction.

## Return independently verifiable results

`run` produces fleet-first best, mean, median, standard deviation/range, BKS
attainment and time-to-target, English exact and XKCDMakie figures, and an
offline interactive dashboard with solver selection and fixed reference marks.
The SINTEF BKS table supplies a target, not a comparable historical runtime.

```sh
julia LiLim/scripts/colleague.jl export --output=LiLim/results/local-60s-1t
```

Return the printed `.tar.gz` file. It contains manifest, sealed route evidence,
summaries, logs and figures for an independent audit. Keep this bulk evidence
out of source commits. Never include a Hexaly license or credentials.

Official references: [SINTEF data and objective](https://www.sintef.no/projectweb/top/pdptw/li-lim-benchmark/),
[Hexaly's published PDPTW comparison](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw).
