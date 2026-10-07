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
    evidence = Dict("ortools"=>Dict("status"=>"passed","qualified_families"=>["rcpsp","jssp","vbp","bppc"],
        "scope"=>"small_original_models_only"))
    merged = Dict("benchmarks"=>deepcopy(rows))
    HexalyPreflight.discrete_evidence!(merged,evidence;core_state="passed")
    scheduling = only(filter(row->row["id"]=="large_jssp",merged["benchmarks"]))
    native = only(filter(row->row["solver"]=="ortools",scheduling["solvers"]))
    @test native["qualification"]=="functional_passed"
    @test native["qualification_scope"]=="small_original_models_only"
    @test !("model_not_qualified:ortools" in scheduling["issues"])
    @test "published_instance_qualification_pending:ortools" in scheduling["issues"]
    @test "original_corpus_and_references_unqualified" in scheduling["issues"]
    @test scheduling["status"]=="prepared_models_published_corpus_pending"
    routing = only(filter(row->row["id"]=="cvrp",merged["benchmarks"]))
    @test "model_not_qualified:ortools" in routing["issues"]
    @test only(filter(row->row["id"]=="irp",merged["benchmarks"]))["status"]=="deferred_continuous"
    @test only(filter(row->row["id"]=="pdptw",merged["benchmarks"]))==only(filter(row->row["id"]=="pdptw",rows))
    HexalyPreflight.discrete_evidence!(merged,evidence;core_state="passed")
    @test count(==("published_instance_qualification_pending:ortools"),scheduling["issues"])==1
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
