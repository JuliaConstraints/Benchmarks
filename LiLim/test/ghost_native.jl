using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))
const ROOT = normpath(joinpath(@__DIR__,"..",".."))
const READY = try
    NativeSolvers.resolve_ghost(;root=ROOT)
catch exception
    exception isa NativeSolvers.UnavailableSolver || rethrow()
    println("Skipped ",exception.method,": ",exception.reason)
    nothing
end
@testset "GHOST.jl wrapper and original PDPTW qualification" begin
    if READY === nothing
        @test_skip false
    else
        @eval using GHOST
        # These exercise the actual installed Artifact, not a native stand-in.
        include(joinpath(pkgdir(GHOST),"test","runtests.jl"))
        for source in ("Pilot","MetaRepair","ICNScoring","GHOSTNative")
            include(joinpath(ROOT,"LiLim/src",source*".jl"))
        end
        mktempdir() do directory
            path = joinpath(directory,"tiny.txt")
            write(path,"3 1 1\n0 0 0 0 0 20 0 0 0\n1 1 1 1 0 20 0 0 2\n2 2 1 -1 0 20 0 1 0\n3 -1 1 1 0 20 0 0 4\n4 -2 1 -1 0 20 0 3 0\n")
            p = read_benchmark(path,:li_lim;id="tiny")
            bank = ICNScoring.load_backend(:icn)
            e = GHOSTNative.RouteError(p,bank,Pilot.distances(p.data),ones(Int,4))
            # Exhaustive permutations check separators, empty vehicles,
            # pair order, route assignment and the original feasibility set.
            function visit(prefix,remaining)
                if isempty(remaining)
                    result = Base.invokelatest(GHOSTNative.score,e,prefix)
                    routes = MetaRepair.routes_from_successors(p,e.successors)
                    checked = validate_solution(p,routes)
                    @test iszero(result.error) == checked.valid
                    return
                end
                for node in remaining
                    visit([prefix;node],filter(!=(node),remaining))
                end
            end
            visit(Int[],collect(2:7))
            policy = Dict("insertion_starts"=>1,"insertion_seed"=>41)
            # Preheat on this synthetic problem before the bounded test clock.
            GHOSTNative.warmup(path,policy;threads=1,id="tiny")
            first = GHOSTNative.run_case(path,3.,41,policy;threads=1,id="tiny")
            result = GHOSTNative.run_case(path,0.2,42,policy;threads=1,id="tiny")
            for trial in (first,result)
                @test trial["original_validation"]
                @test trial["objective_evaluations"] > 0
                @test !trial["seed_applied_to_search"]
                @test all(e->e["seconds"] <= trial["budget_seconds"],trial["trajectory"])
                @test all(e->validate_solution(p,e["routes"]).valid,trial["trajectory"])
                @test validate_solution(p,trial["routes"]).valid
            end
        end
    end
end
