# Reproducible Li-Lim comparison handoff

This Linux/macOS/Windows kit compares the same original PDPTW instances, a common feasible
insertion start, a shared wall-clock budget, and a fleet-first objective followed
by unrounded Euclidean distance. Every exported solution and every trajectory
point is checked by the original ConstraintModels validator. It is a local
comparison, not an identical reproduction of the vendor's published experiment.

The GHOST wrapper and PDPTW adapter passed 2,413 local assertions, including
exhaustive tiny-instance feasibility checks and actual one- and two-lane searches
with the downloaded native Artifact. OR-Tools GLS has also passed its original
PDPTW model qualification. These functional checks do not establish solver rankings.

Prerequisites: **Julia 1.13.1**, Git, Python 3.12 and, on Linux,
`taskset`/`lscpu`. No private repository, account or token is required. macOS
Intel and Apple Silicon are supported; Windows x86_64 and Linux x86_64/aarch64
have matching native distributions. Functional CI is separate from performance measurement.

```sh
git clone --single-branch --branch bench/lilim-etendu-20261007 https://github.com/JuliaConstraints/Benchmarks.git ~/Gits/JuliaConstraintsBenchmarks
cd ~/Gits/JuliaConstraintsBenchmarks
julia LiLim/scripts/colleague.jl setup
julia LiLim/scripts/colleague.jl qualify
julia LiLim/scripts/colleague.jl run --budget=60 --threads=1 --output=LiLim/results/local-60s-1t
```

Setup clones the twelve public package snapshots into
`~/.julia/dev/JuliaConstraintsBench`, installs the frozen Julia environments and
OR-Tools 9.14.6206 only if absent, downloads the six official
SINTEF archives, and checks all 354 instance hashes. Existing mismatched or dirty
checkouts are preserved and rejected. `workspace-cohort.toml` records public
commit IDs, their original qualified commits, and identical runtime-file hashes.
Public snapshots exclude private history, research logs and bulk artifacts.
The three recovered ICN witness recipes are bundled with their provenance;
their weights are unchanged and were not retrained for this comparison.
Existing OR-Tools installations are reused first. Missing SDKs use checked
upstream wheel Artifacts loaded through PYTHONPATH; setup does not modify an
existing Python environment or reinstall a present solver. HiGHS uses its Julia
JLL. GHOST.jl and GHOST_jll are additional public, pinned Julia source packages;
the latter downloads only a missing matching native Artifact, with GPL source
and license included. A GHOST environment is derived from the frozen core while
checking that every existing dependency version remains identical.

`qualify` runs actual OR-Tools GLS searches on tiny instances, including unit
capacity, pickup precedence with zero travel, nonzero depot service and empty
vehicles; it also checks ICN scoring, hybrid behavior and existing strategies.
The OR-Tools adapter uses conservative integer time scaling (10,000) and
distance scaling (1,000,000). The original double-precision validator remains
authoritative. Rounding is a documented modeling difference.

The default diagnostic uses LC101, LR101 and LRC101 with repetition labels
41/42/43. OR-Tools RoutingModel is **single-threaded**; those labels do not change
its GLS random seed. Its repetitions measure variation in elapsed execution.
CBLS workers use independent seeds. GHOST uses its development C++ engine
through the Julia MOI wrapper, permutation moves, and the same qualified PDPTW
ICN scorer. Each Julia lane owns a native worker and private callback buffers.
Its ABI does not expose RNG seeds or tabu/reset counters; repetition labels
are not passed as seeds. Every returned incumbent is checked independently.
Native subprocess launch/imports, model construction and the common start count
inside each trial budget. Julia packages load once in the campaign process;
solver warmup is measured separately. The exposed trio
is not a held-out confirmation corpus and does not justify general superiority.

For wider comparisons, use `--threads=8` or `--threads=16`. Defaults then include
the historical CBLS profiles, 35 ICN/hybrid variants and four MetaStrategist
portfolios, with partial/full resets, tabu and late acceptance, alongside
HiGHS, OR-Tools, GHOST and available Hexaly. Each method runs serially as a separate
trial. The launcher chooses one logical CPU per physical core before SMT
siblings; on hybrid CPUs this does not distinguish P/E cores. For controlled
affinity pass `--cpus=8,10,0,2,4,6,12,14` (replace with your host's CPU IDs).
OR-Tools always uses just the first selected CPU. CPU time and GC evidence are
reported; requested worker counts are not claimed to be active CPU counts.
Search-phase GC and GHOST's whole-trial GC are reported separately; the latter
also includes parsing, insertion, model construction and original validation.

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
Missing solvers or licenses are explicitly skipped by default; model defects
and invalid routes still fail. Use `--missing-solvers=error` to require all
selected profiles. A local installed Hexaly currently has no usable license,
so native Hexaly search remains unqualified here.

```sh
julia LiLim/scripts/colleague.jl qualify --hexaly=/path/to/hexaly
julia LiLim/scripts/colleague.jl run --budget=60 --threads=8 --hexaly=/path/to/hexaly --methods=hexaly_native,ortools_native,cbls_icn,hybrid_specialized_icn,hybrid_bridged_icn,mixed_balanced --output=LiLim/results/hexaly-60s-8t
```

The Hexaly model minimizes fleet then distance in a documented 5:1 allocation of
the remaining search time, preserving original continuous feasibility. This
differs from a distance-only vendor model. Model setup time counts in the common
budget; late improvements are censored. Native qualification must be run first.
Other Hexaly versions are preserved and explicitly skipped by this 15.0 gate.
Supporting one requires a separate adapter qualification; it must not be
silently described as a 15.0 reproduction.

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

The [coverage catalog](config/hexaly-benchmark-catalog.toml) inventories all 20
Hexaly benchmark pages. This ready-to-run handoff targets Li-Lim first; other
families require their own model and original-validator qualification. Their
presence in the catalog does not imply runnable reproductions.
