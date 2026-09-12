# Historical package experiments

397 original files from the four former top-level folders are retained byte for byte.
`inventory.toml` records each file's SHA-256; `scripts/check.jl` at the repository root
verifies the inventory. Generated historical CSV and images remain versioned here.
Their metadata, including original paths, have deliberately not been rewritten.

These scripts are source evidence, not supported entrypoints. In particular, old
PerfChecker version sweeps and VS Code `@profview` scripts must not be launched as
current campaigns. Their package/API versions, resource usage and overwriting output
conventions have not been qualified in the new environment. New Julia diagnostics
live in `src/PackageBenchmarks.jl`, under the root DrWatson project.

No historical measurement is reclassified as a result of the new harness. The
ConstraintLearning folder is a retired environment-only placeholder, unrelated to
the independent live HPO repository. See `docs/method.md` for the retained coverage
and the smaller workloads deliberately chosen for initial qualification.
