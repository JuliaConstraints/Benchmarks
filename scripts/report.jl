# Summarize one explicit attempt; never pool different revisions or resources.
include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
include("activate.jl")
using TOML, UUIDs
include(srcdir("Evidence.jl"))
length(ARGS) == 1 || error("usage: report.jl <package-attempt-uuid>")
id = string(UUID(only(ARGS)))
source = datadir("sims", "packages", id)
isfile(joinpath(source, "completed.toml")) || error("attempt is not complete")
isfile(joinpath(source, "failed.toml")) && error("attempt is marked failed")
completion = TOML.parsefile(joinpath(source, "completed.toml"))
digest = Evidence.digest(joinpath(source, "result.toml"))
completion["result_sha256"] == digest || error("result digest mismatch")
metadata = TOML.parsefile(joinpath(source, "started.toml"))
result = TOML.parsefile(joinpath(source, "result.toml"))
result["schema"] in ("package-diagnostics/1", "package-diagnostics/2") || error("unsupported result schema")
for (relative, sha) in metadata["source_sha256"]
    Evidence.digest(joinpath(source, "snapshot", split(relative, '/')...)) == sha || error("source snapshot mismatch")
end
for file in ("project", "manifest")
    Evidence.digest(joinpath(source, "snapshot", uppercasefirst(file) * ".toml")) == metadata[file * "_sha256"] || error("environment snapshot mismatch")
end
parent = datadir("exp_pro", "packages")
mkpath(parent)
output = joinpath(parent, string(uuid4()))
mkdir(output)
open(joinpath(output, "report.md"), "w") do io
    println(io, "# Package diagnostics — ", id)
    println(io, "\nSingle-attempt diagnostic measurements; no solver ranking or isolated performance claim.")
    println(io, "\nMode: `", metadata["mode"], "`; Julia ", metadata["julia_version"],
        "; threads: ", metadata["julia_threads"], "; CPUs: ", join(metadata["cpus"], ", "),
        "; seed: ", metadata["seed"], ".")
    println(io, "\nConcurrency: ", metadata["concurrency_note"], "\n")
    println(io, "| Case | Samples | Operations/sample | Median ns/op | Min–max ns/op | Min bytes/op | Min allocations/op |")
    println(io, "|---|---:|---:|---:|---:|---:|---:|")
    for row in result["cases"]
        row["validated"] || error("unvalidated case")
        times = sort(row["times_ns"])
        n = length(times)
        n > 0 || error("empty trial")
        median = isodd(n) ? times[(n+1)÷2] : (times[n÷2] + times[n÷2+1]) / 2
        unresolved = get(row, "timing_status", any(t -> t <= 0.001, times) ? "below_timer_resolution" : "measured") == "below_timer_resolution"
        central = unresolved ? "unresolved" : string(round(median; digits=2))
        spread = unresolved ? "below timer resolution" : string(round(first(times); digits=2), "–", round(last(times); digits=2))
        println(io, "| ", row["id"], " | ", n, " | ", get(row, "operations_per_sample", 1), " | ", central, " | ",
            spread, " | ", row["minimum_memory_bytes"], " | ", row["minimum_allocations"], " |")
    end
    println(io, "\nSetup, warmup and correctness checks are outside timing; evals=1 batch. Each operation has its own input and every result is retained. Timings include batch loop/result storage overhead and describe amortized throughput, not isolated latency. Raw batch samples are retained. See each row for the operation scope.")
    println(io, "\nInput result SHA-256: `", digest, "`.")
end
Evidence.atomic_toml(joinpath(output, "provenance.toml"), Dict("source_attempt" => id,
    "source_result_sha256" => digest, "report_sha256" => Evidence.digest(joinpath(output, "report.md")),
    "report_script_sha256" => Evidence.digest(@__FILE__)))
println("Report: ", joinpath(output, "report.md"))
