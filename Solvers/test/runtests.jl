include("../scripts/resources.jl")
include("../scripts/activate.jl")
include(srcdir("SolverComparison.jl"))
using .SolverComparison, Test, TOML, SHA, Dates
const ROOT = projectdir()
const MANIFEST = joinpath(ROOT, "campaigns", "ilp-functional.toml")
const RESULTS = Dict{String,Any}("kind" => "infrastructure_checks", "solver_runs" => 0,
    "checks_started_utc" => string(now(UTC)), "pid" => getpid(),
    "cpus" => COMPARISON_CPUS, "affinity" => string(COMPARISON_AFFINITY; base=16),
    "concurrency_note" => get(ENV, "SOLVER_COMPARISON_CONCURRENCY_NOTE", "not_recorded"),
    "performance_claims" => false)

@testset "ILP functional pilot infrastructure" begin
    @test projectname() == "SolverComparisonBenchmarks"
    @test samefile(ROOT, normpath(joinpath(@__DIR__, "..")))
    @test datadir("checks") == joinpath(ROOT, "data", "checks")
    @test isfile(projectdir("Manifest.toml"))
    @test pkgversion(DrWatson) == v"2.19.1"
    spec = load_campaign(MANIFEST)
    cases = load_cases(joinpath(ROOT, "fixtures", "ilp.toml"))
    @test length(cases) == 6
    @test length(spec["paths"]) == 19
    oracles = Dict{String,Any}()
    for p in cases
        ref = exact_oracle(p; max_assignments=spec["oracle_max_assignments"])
        oracles[p["id"]] = ref
        @test ref["status"] == p["expected_status"]
        if ref["status"] == "optimal"
            @test ref["objective_exact"] == p["expected_objective"]
            @test validate_primal(p, ref["primal"]).status == :validated
            @test validate_primal(p, ref["primal"]; reported_objective=999).status == :invalid_objective
        else
            @test isempty(ref["primal"])
        end
        @test validate_primal(p, nothing).status == :no_primal
        @test validate_primal(p, []).status == :invalid_dimension
    end
    p = first(cases)
    @test validate_primal(p, [0.5, 1, 0, 0]).status == :invalid_integrality
    @test validate_primal(p, [NaN, 1, 0, 0]).status == :invalid_integrality
    @test validate_primal(p, [2, 1, 0, 0]).status == :invalid_domain
    @test validate_primal(p, [0, 0, 0, 0]).status == :invalid_constraint
    @test validate_primal(p, [1.0, 1.0, 0.0, 0.0]; reported_objective=3.0).status == :validated
    @test_throws ArgumentError exact_oracle(p; max_assignments=1)
    plan = pilot_plan(MANIFEST)
    @test length(plan["planned_runs"]) == 228
    @test all(row -> row["execution"] == "not_run", plan["planned_runs"])
    @test !plan["performance_claims"]
    ids = Set((row["path"], row["case"], row["threads"]) for row in plan["planned_runs"])
    @test length(ids) == 228
    exercised = zeros(Int, Threads.nthreads())
    Threads.@threads :static for i in eachindex(exercised)
        exercised[i] = Threads.threadid()
    end
    @test length(unique(exercised)) == Threads.nthreads()
    RESULTS["julia_workers_exercised"] = length(unique(exercised))
    RESULTS["oracles"] = oracles
    RESULTS["manifest_sha256"] = plan["manifest_sha256"]
    RESULTS["fixture_sha256"] = plan["fixture_sha256"]
    RESULTS["checks_before_archive_utc"] = string(now(UTC))
    first_path = write_attempt(datadir("checks"), RESULTS)
    original = read(joinpath(first_path, "result.toml"))
    second_path = write_attempt(datadir("checks"), RESULTS)
    @test first_path != second_path
    @test read(joinpath(first_path, "result.toml")) == original
    completion = TOML.parsefile(joinpath(second_path, "completed.toml"))
    @test completion["result_sha256"] == bytes2hex(sha256(read(joinpath(second_path, "result.toml"))))
    @test TOML.parsefile(joinpath(second_path, "result.toml"))["solver_runs"] == 0
    metadata = TOML.parsefile(joinpath(second_path, "started.toml"))["provenance"]
    @test metadata["project_name"] == "SolverComparisonBenchmarks"
    @test haskey(metadata, "gitcommit")
    @test metadata["source_sha256"]["src/SolverComparison.jl"] == bytes2hex(sha256(read(srcdir("SolverComparison.jl"))))
    @test metadata["manifest_sha256"] == bytes2hex(sha256(read(projectdir("Manifest.toml"))))
    @test metadata["source_sha256"]["src/SolverComparison.jl"] == bytes2hex(sha256(read(joinpath(second_path, "snapshot", "src", "SolverComparison.jl"))))
    println("Evidence: ", second_path)
end
