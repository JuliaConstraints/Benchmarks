using Test, TOML, SHA
include(joinpath(@__DIR__,"..","src","HexalyPreflight.jl"))
const ROOT = normpath(joinpath(@__DIR__,"..",".."))
const CATALOG = HexalyPreflight.catalogue(joinpath(ROOT,"LiLim/config/hexaly-benchmark-catalog.toml"))

@testset "Complete catalogue and honest readiness" begin
    @test length(CATALOG["benchmarks"])==20
    @test all(row->!isempty(row["published_solvers"]),CATALOG["benchmarks"])
    solvers = Dict("hexaly"=>Dict("status"=>"available"),"ortools"=>Dict("status"=>"available"))
    rows = HexalyPreflight.coverage(ROOT,joinpath(homedir(),".julia/dev/JuliaConstraintsHandoff"),CATALOG;
        solvers,qualification=Dict{String,String}(),environment_ok=true)
    @test length(rows)==20
    @test all(row->row["status"]=="blocked",filter(row->row["id"]!="irp",rows))
    @test only(filter(row->row["id"]=="irp",rows))["status"]=="deferred_continuous"
    @test all(row->"original_corpus_and_references_unqualified" in row["issues"],filter(row->!(row["id"] in ("pdptw","irp")),rows))
    @test !any(row->row["status"]=="ready_available_solvers",rows)
    mktempdir() do root
        @test_throws ErrorException HexalyPreflight.asset(root,root,"../outside")
        @test HexalyPreflight.asset(root,root,"")["status"]=="missing"
        manifest=joinpath(root,"data.toml")
        @test HexalyPreflight.pdptw_data(root,manifest)["status"]=="missing"
        fake=Dict("archive_sha256"=>Dict{String,String}(),"instances"=>Dict{String,Any}(),
            "instance_sha256"=>Dict{String,String}())
        open(io->TOML.print(io,fake),manifest,"w")
        audited=HexalyPreflight.pdptw_data(root,manifest)
        @test audited["status"]=="blocked"
        @test "original_instance_count_mismatch" in audited["issues"]
        @test "original_archive_count_mismatch" in audited["issues"]
        report=Dict("source"=>CATALOG["source"],"checked_at_utc"=>"2026-10-07", "entry_count"=>20,
            "status"=>"blocked","host"=>Dict("os"=>"Linux","architecture"=>"x86_64","julia"=>"1.13.1",
                "cpus"=>[0],"ram_gib"=>32.),"solvers"=>solvers,"checks"=>Dict{String,Any}(),"benchmarks"=>rows)
        output=joinpath(root,"report")
        HexalyPreflight.save_report(output,report)
        @test length(TOML.parsefile(joinpath(output,"report.toml"))["benchmarks"])==20
        markdown=read(joinpath(output,"report.md"),String)
        @test all(row->occursin(row["published_benchmark_url"],markdown),rows)
        @test_throws ErrorException HexalyPreflight.save_report(output,report)
    end
end
