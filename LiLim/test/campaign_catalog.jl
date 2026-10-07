using Test, TOML
include(joinpath(@__DIR__,"..","src","CampaignCatalog.jl"))
@testset "Historical selectors and expanded comparison panel" begin
    for width in (1,2,4,8,16)
        historical=CampaignCatalog.select_methods(width,"all")
        @test historical==CampaignCatalog.available_methods(width)
        @test !("ortools_native" in historical)
        @test !("hexaly_native" in historical)
        panel=CampaignCatalog.select_methods(width,"panel")
        @test allunique(panel)
        @test all(m->m in panel,historical)
        @test all(m->m in panel,["ortools_native","hexaly_native","ghost_icn","cbls_icn_reset_best_full",
            "cbls_icn_tabu_random_partial","hybrid_specialized_icn_full_reset","mixed_restart_diverse"])
        strategies=CampaignCatalog.select_methods(width,"strategies")
        @test length(strategies)==39
        @test Set(CampaignCatalog.select_methods(width,"all,strategies"))==Set(vcat(historical,strategies))
    end
    @test_throws ArgumentError CampaignCatalog.select_methods(1,"")
    @test_throws ArgumentError CampaignCatalog.select_methods(1,"absent")
    @test_throws ArgumentError CampaignCatalog.select_methods(1,"cbls_icn,")
    @test_throws ArgumentError CampaignCatalog.select_methods(0,"panel")
    coverage=TOML.parsefile(joinpath(@__DIR__,"..","config","hexaly-benchmark-catalog.toml"))
    @test length(coverage["benchmarks"])==coverage["entry_count"]==20
    @test allunique(getindex.(coverage["benchmarks"],"published_benchmark_url"))
    @test count(row->row["priority"]==1,coverage["benchmarks"])==1
end
