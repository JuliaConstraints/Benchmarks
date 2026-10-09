using Test, TOML
include("../src/PanelPlotStyles.jl")
include("../src/StrategyPanel.jl")
include("../src/RoutingPanel.jl")

@testset "Li-Lim panel styles preserve references and distinguish profiles" begin
    config=TOML.parsefile(joinpath(@__DIR__,"../config/strategy-variants.toml"))
    order=PanelPlotStyles.profile_order(config,RoutingPanel.methods(),StrategyPanel.methods())
    @test allunique(order)
    current=filter(m->!startswith(m,"xp_"),order)
    @test Set(RoutingPanel.methods()) ⊆ Set(current)
    @test length(current)<=length(PanelPlotStyles.COLORS)*length(PanelPlotStyles.MARKERS)
    styles=PanelPlotStyles.styles(current,order)
    @test allunique([(s.color,s.marker) for s in values(styles)])
    full=PanelPlotStyles.styles(order,order)
    @test allunique([(s.color,s.marker,s.linestyle) for s in values(full)])

    # The retained native/reference positions must not move when panels expand.
    for (method,index) in ("cbls_icn"=>2,"highs_native"=>8,"ortools_native"=>13)
        @test styles[method]==PanelPlotStyles.style(index)
    end
    # A width/subset change must not change a profile's visual identity.
    for methods in (RoutingPanel.methods(),reverse(current),current[1:2:end])
        subset=PanelPlotStyles.styles(methods,order)
        @test all(subset[m]==styles[m] for m in methods)
    end

    # SVG and static plots must preserve all four distinct line patterns.
    @test PanelPlotStyles.html_dash(:solid)==""
    @test PanelPlotStyles.html_dash(:dash)=="9 3"
    @test PanelPlotStyles.html_dash(:dot)=="2 3"
    @test PanelPlotStyles.html_dash(:dashdot)=="7 3 2 3"
    @test_throws ArgumentError PanelPlotStyles.html_dash(:unknown)
end
