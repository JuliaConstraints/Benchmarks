using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
include(joinpath(@__DIR__,"..","competitors","Permutation.jl"))
function permutations!(f,values,i=1)
    i>length(values) && return f(values)
    for j in i:length(values)
        values[i],values[j]=values[j],values[i];permutations!(f,values,i+1);values[i],values[j]=values[j],values[i]
    end
end
@testset "Native permutation zero sets and GHOST full score" begin
    binary=joinpath(homedir(),".cache/juliaconstraints/ghost-pdptw")
    for capacity in (1,2),tight in (false,true)
        data=PickupDeliveryProblem(3,capacity,[0. 0.;1 1;2 1;-1 1;-2 1],
            [0,1,-1,1,-1],zeros(5),tight ? [20.,1.5,3.,1.5,3.] : fill(20.,5),zeros(5),[(2,3),(4,5)])
        p=BenchmarkInstance("native-zero-set",data)
        # Export needs a valid start even for the deliberately infeasible tight fixture.
        mktempdir() do exchange
            input=joinpath(exchange,"input.txt");candidates=joinpath(exchange,"candidates.txt");output=joinpath(exchange,"scores.txt")
            loose=BenchmarkInstance("loose",PickupDeliveryProblem(3,capacity,data.coordinates,data.demand,data.earliest,fill(20.,5),data.service,data.pairs))
            open(io->CompetitorAdapters.export_common_start(io,loose,[[2,3],[4,5]]),input,"w")
            if tight
                rows=readlines(input)
                for i in 1:5;r=split(rows[i+1]);r[6]=string(data.latest[i]);rows[i+1]=join(r,' ') end
                write(input,join(rows,'\n')*"\n")
            end
            d=PermutationRoutes.read_common(input);scores=Any[]
            open(candidates,"w") do io
                permutations!(collect(2:7)) do values
                    q=PermutationRoutes.evaluate(d,values);routes=PermutationRoutes.decode(d,values);original=validate_solution(p,routes)
                    @test iszero(q.error)==original.valid
                    if original.valid
                        @test q.vehicles==original.objective.vehicles
                        @test q.distance≈original.objective.distance atol=1e-10
                    end
                    push!(scores,q);println(io,join(values,' '))
                end
            end
            run(`$binary evaluate $input $candidates $output`)
            for (q,row) in zip(scores,readlines(output))
                error,fleet,distance=parse.(Float64,split(row))
                @test error≈q.error atol=1e-10
                @test fleet==q.vehicles
                @test distance≈q.distance atol=1e-10
            end
            @test length(readlines(output))==720
        end
    end
end
