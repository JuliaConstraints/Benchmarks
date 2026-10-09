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

@testset "Disjoint screening families and effective four-worker features" begin
    methods=CampaignCatalog.select_methods(4,"extended-panel,routing-panel")
    expected=Dict(:cbls=>220,:cbls_highs=>72,:meta_cbls_ro=>180,:cbls_qubo=>24,
        :routing=>36,:meta_routing=>16)
    @test length(methods)==sum(values(expected))==548
    for (family,count) in expected
        @test sum(m->CampaignCatalog.family(m)==family,methods)==count
    end
    @test count(m->:interior_point in CampaignCatalog.features(m,4),methods)==124
    @test :interior_point in CampaignCatalog.features("xp_hybrid_tabu_short_light_rins_ipx",4)
    @test !(:interior_point in CampaignCatalog.features("xp_hybrid_tabu_short_light_rins_simplex",4))
    @test :tabu in CampaignCatalog.features("xp_cbls_icn_late_h32_t4",4)
    @test :reset in CampaignCatalog.features("xp_cbls_naive_reset_p0p01_f0p05_best",4)
    @test :qubo in CampaignCatalog.features("xp_qubo_absolute_d2_e16_x0p25",4)
    order=CampaignCatalog.screening_order(methods,20261010)
    @test order==CampaignCatalog.screening_order(reverse(methods),20261010)
    @test Set(order)==Set(methods) && allunique(order)
    @test Set(CampaignCatalog.family.(order[1:6]))==Set(keys(expected))
    deferred=order[1:7]
    replay=CampaignCatalog.screening_order(methods,20261010;deferred,priority=[first(deferred)])
    @test first(deferred) in replay[1:6]
    @test Set(replay[end-5:end])==Set(deferred[2:end])
    @test_throws ArgumentError CampaignCatalog.screening_order(methods,1;priority=["absent"])
end
