include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
include("activate.jl")
using Test
using SHA, TOML
@testset "DrWatson root project" begin
    @test projectname() == "JuliaConstraintsBenchmarks"
    @test samefile(projectdir(), normpath(joinpath(@__DIR__, "..")))
    @test datadir("sims") == joinpath(projectdir(), "data", "sims")
    @test srcdir() == joinpath(projectdir(), "src")
    @test scriptsdir() == @__DIR__
    @test isfile(projectdir("Manifest.toml"))
    @test pkgversion(DrWatson) == v"2.19.1"
end

include(srcdir("Evidence.jl"))
@testset "Attempt persistence" begin
    attempt = Evidence.start("checks", Dict("cpus" => COMPARISON_CPUS, "performance_claims" => false))
    @test isfile(joinpath(attempt, "snapshot", "Project.toml"))
    @test Evidence.digest(joinpath(attempt, "snapshot", "src", "Evidence.jl")) == Evidence.digest(srcdir("Evidence.jl"))
    @test !ispath(joinpath(attempt, "completed.toml"))
    Evidence.complete(attempt, Dict("validated" => true))
    @test TOML.parsefile(joinpath(attempt, "completed.toml"))["result_sha256"] == Evidence.digest(joinpath(attempt, "result.toml"))
    @test_throws ErrorException Evidence.complete(attempt, Dict("validated" => false))
    @test TOML.parsefile(joinpath(attempt, "result.toml"))["validated"]
    failed = Evidence.start("checks", Dict("cpus" => COMPARISON_CPUS, "purpose" => "deliberate failure-path test"))
    Evidence.fail(failed, ErrorException("expected test failure"))
    @test isfile(joinpath(failed, "failed.toml"))
    @test !ispath(joinpath(failed, "completed.toml"))
end

@testset "Historical evidence integrity" begin
    archive = projectdir("archive", "legacy")
    inventory = TOML.parsefile(joinpath(archive, "inventory.toml"))
    for (family, files) in inventory["files"], (relative, digest) in files
        @test bytes2hex(sha256(read(joinpath(archive, family, split(relative, '/')...)))) == digest
    end
end

@testset "Catalogue entrypoints" begin
    catalogue = TOML.parsefile(projectdir("config", "catalogue.toml"))
    @test catalogue["max_logical_cpus"] == 2
    @test catalogue["max_concurrent_runs"] == 1
    for study in catalogue["studies"]
        if haskey(study, "entrypoint")
            @test endswith(study["entrypoint"], ".jl")
            @test isfile(projectdir(study["entrypoint"]))
        else
            @test study["status"] in ("archived", "retired")
        end
    end
end
