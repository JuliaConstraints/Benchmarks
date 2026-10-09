using Test,Random,TOML
include(joinpath(@__DIR__,"../src/TraceCounters.jl"))
const TC=TraceCounters

@testset "Private numeric trace preserves ordinary dictionary observations" begin
    source=Dict{String,Any}("steps"=>1000,"cpu"=>-0.,"label"=>"same","wide"=>big(3),"payload"=>[1,2])
    trace=TC.Trace(source)
    @test isequal(TC.snapshot(trace),source)
    @test trace.integers!==source && length(trace)==length(source)
    @test trace["payload"]===source["payload"]
    @test_throws KeyError trace["absent"]
    @test get(trace,"absent",17)==17
    @test get!(trace,"new",23)==23
    @test haskey(trace,"new") && trace["new"]==23
    delete!(trace,"new");@test !haskey(trace,"new")
    observed=TC.snapshot(trace)
    for (key,amount) in ("steps"=>2,"cpu"=>1.5,"steps"=>0.5,"wide"=>2,"empty"=>0,"empty"=>-5,
            "cpu"=>0,"cpu"=>Inf,"cpu"=>-Inf)
        source[key]=get(source,key,0)+amount
        TC.counter!(trace,key,amount)
        @test isequal(TC.snapshot(trace),source)
    end
    @test observed["steps"]==1000 && isequal(observed["cpu"],-0.)
    @test observed["payload"]===source["payload"]
    for value in (3,2.5,"edited",big(99),nothing,-0.,NaN)
        trace["mixed"]=value;source["mixed"]=value
        @test isequal(TC.snapshot(trace),source)
        @test length(trace)==length(source)
        @test Set(keys(trace))==Set(keys(source))
    end
    clone=copy(trace);@test isequal(TC.snapshot(clone),source)
    clone["steps"]=123;@test trace["steps"]==source["steps"]
    @test clone.values["payload"]===trace.values["payload"]
    deep=deepcopy(trace);push!(deep["payload"],3);@test trace["payload"]==[1,2]
    empty!(clone);@test isempty(clone) && !isempty(trace)
    trace[SubString("substring-key",1,9)]=42
    @test trace["substring"]==42
    plain=TC.snapshot(trace)
    @test isequal(TOML.parse(sprint(io->TOML.print(io,plain))),TOML.parse(sprint(io->TOML.print(io,trace))))
end

@testset "Mixed counter arithmetic and warmed integer updates" begin
    rng=Xoshiro(41);trace=TC.Trace();original=Dict{String,Any}()
    for i in 1:1000
        key="counter_$(rand(rng,1:8))"
        amount=rand(rng,Bool) ? rand(rng,-8:8) : randn(rng)
        original[key]=get(original,key,0)+amount;TC.counter!(trace,key,amount)
        @test isequal(TC.snapshot(trace),original)
    end
    trace["wrapping"]=typemax(Int);TC.counter!(trace,"wrapping")
    @test trace["wrapping"]==typemin(Int)
    function update!(trace,n)
        for _ in 1:n;TC.counter!(trace,"summary_evaluations",3);end
        nothing
    end
    update!(trace,1000)
    @test (@allocated update!(trace,100000))==0
    @test trace["summary_evaluations"]==303000
    retained=TC.snapshot(trace);update!(trace,1000)
    @test retained["summary_evaluations"]==303000
    dynamic_values=Any[mod1(i,3) for i in 1:100000]
    function assign_dynamic!(trace,values)
        for value in values;trace["vnd_neighborhood"]=value;end
        nothing
    end
    assign_dynamic!(trace,dynamic_values)
    @test (@allocated assign_dynamic!(trace,dynamic_values))==0
    @test trace["vnd_neighborhood"]==last(dynamic_values)
end
