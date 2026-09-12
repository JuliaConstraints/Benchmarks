# Diagnostic protocol and migration decisions

## Retained studies

The first objective is functioning, reproducible infrastructure at a two-CPU ceiling.
These package kernels support diagnosis of solver costs; they are not representative
solver workloads or evidence of which solver wins. Future rankings need separate
instance selection, warmup/time accounting, tuning/test split, seeds, stopping criteria,
hardware isolation and per-solver optimized native modelling.

| Historical family | Active cases | Decision |
|---|---|---|
| ConstraintCommons automata and MDD | Acceptance queries with known accepted/rejected inputs | Retain for constraint evaluation diagnostics |
| ConstraintCommons dictionaries and extrema | Fresh Dict updates and fixed-vector extrema | Retain; third-party Dictionary variant remains historical |
| ConstraintCommons nothing, symbols, parameter reflection | None | Retire from default benchmarks: narrow utility checks better kept in package correctness tests |
| ConstraintCommons oversampling | None | Defer: a representative stochastic input/distribution protocol is needed |
| ConstraintDomains | Empty construction, continuous/discrete membership, mutation, exhaustive 4-variable exploration | Retain and bound the space (256 assignments, exactly 24 all-different solutions) |
| PatternFolds | Construction, collection, unfolding, reverse, interval collection, seeded sampling | Retain; split operations formerly mixed in a single timed block |
| IDE profiling / historical version sweeps | None | Archive, no automatic launch or claim of functional migration |
| ConstraintLearning placeholder | None | Retire: no original experiment existed |

The new 15 scenarios target pinned registered versions: ConstraintCommons 0.3.0,
ConstraintDomains 0.4.0, PatternFolds 0.2.6 and BenchmarkTools 1.8.0. No checkout of a
shared dependency is modified. These are deliberately small, newly specified workloads;
they cannot be compared numerically with the old mixed-operation CSV rows.

## Measurement contract

Julia builds each input outside timing and resets mutable input/RNG for every sample.
Schema `package-diagnostics/2` executes one batch per sample (`evals=1`), with 256
independent inputs and output slots (8 inputs for exhaustive exploration). An independent
expected answer/invariant is checked for the scalar operation and the entire warmup
batch before timing. Every output is retained to avoid discarding unused work. No
mutable input is reused across operations within a batch. BenchmarkTools receives explicit limits
from `config/packages.toml`; raw batch times and GC times are retained, together with
BenchmarkTools' minimum allocation/memory estimates and values divided by batch size.
Normalized timing includes loop/result-storage overhead: it is amortized throughput,
not isolated call latency. Timings at the timer floor are labelled unresolved in reports.
The initial schema-1 single-operation attempt is retained as historical diagnostic
evidence: it exposed inadequate timer resolution for several short kernels and must
not be compared directly with schema-2 batches. No single minimum time is used
as a solver performance result. Setup, warmup, correctness checks and dependency
loading are excluded from the measured operation, and the scope is stored per case.

The common launcher runs one Julia child at a time; its waiting parent uses the same
CPU affinity. The total allocation stays at one or two logical CPUs, including child
runtime threads. One- and two-thread checks test infrastructure operation; individual
package kernels are not claimed to parallelize. No worker is launched by source import.

Completed results require `completed.toml` and a matching `result_sha256`. Failed and
incomplete attempts remain visible. Reports must group only comparable configurations,
including inputs, source/environment revisions, thread and resource settings. Different
native/JuMP models or strategy profiles must retain separate identities. A profile
called GHOST-like or JuLS-like must document known differences and fidelity explicitly.

The versioned `archive/legacy/inventory.toml` proves conservation during this migration,
not the correctness or reproducibility of the original experiments. Existing archives
are not retroactively given the new metadata. New attempts snapshot their own inputs.
