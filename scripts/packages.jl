include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
include("activate.jl")
using TOML, Test
include(srcdir("Evidence.jl"))
include(srcdir("PackageBenchmarks.jl"))

length(ARGS) == 1 && only(ARGS) in ("smoke", "measure") || error("usage: packages.jl smoke|measure")
mode = only(ARGS)
config = TOML.parsefile(projectdir("config", "packages.toml"))
config["schema"] == "package-diagnostics/2" || error("unsupported schema")
config["evals"] == 1 || error("mutable inputs require evals=1")
!config["performance_claims"] || error("this pilot cannot qualify comparative performance")
settings = config[mode]
1 <= settings["samples"] <= 50 || error("sample budget exceeded")
0 < settings["seconds_per_case"] <= 0.1 || error("time budget exceeded")
cases = PackageBenchmarks.cases(config["seed"])
allunique(c.id for c in cases) || error("duplicate case ids")
Set(c.family for c in cases) == Set(config["families"]) || error("family catalogue mismatch")

attempt = Evidence.start("packages", Dict("mode" => mode, "seed" => config["seed"],
    "cpus" => COMPARISON_CPUS, "affinity" => string(COMPARISON_AFFINITY; base=16),
    "julia_threads" => Threads.nthreads(), "performance_claims" => false,
    "concurrency_note" => get(ENV, "SOLVER_COMPARISON_CONCURRENCY_NOTE", "not_recorded"),
    "config_sha256" => Evidence.digest(projectdir("config", "packages.toml"))))
try
    rows = Dict{String,Any}[]
    @testset "Package diagnostic semantics" begin
        for c in cases
            @test PackageBenchmarks.check(c)
            push!(rows, PackageBenchmarks.measure(c;
                samples=settings["samples"], seconds=settings["seconds_per_case"],
                operations=config[c.id == "domains.explore" ? "exploration_operations_per_sample" : "operations_per_sample"]))
        end
    end
    Evidence.complete(attempt, Dict("schema" => config["schema"], "mode" => mode,
        "performance_claims" => false, "cases" => rows))
    println("Evidence: ", attempt)
catch err
    Evidence.fail(attempt, err)
    rethrow()
end
