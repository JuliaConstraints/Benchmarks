using Test
include(joinpath(@__DIR__,"..","scripts","colleague.jl"))

@testset "Qualification worker caps respect the allocated CPUs" begin
    for test in ("ortools_parallel.jl","icn_resources.jl","classical_strategy_panel")
        @test qualification_width(Dict("cpus"=>"8"),test)==1
        @test qualification_width(Dict("cpus"=>"8,9,10,11"),test)==2
    end
    @test qualification_width(Dict("cpus"=>"8,9"),"strategy_panel.jl")==1
end

@testset "Frozen checkout bytes survive a global CRLF policy" begin
    mktempdir() do directory
        global_config = joinpath(directory,"global.gitconfig")
        global_bytes = "[core]\n\tautocrlf = true\n[user]\n\tname = Checkout qualification\n\temail = qualification@example.invalid\n"
        write(global_config,global_bytes)
        withenv("GIT_CONFIG_GLOBAL"=>global_config,"GIT_CONFIG_NOSYSTEM"=>"1") do
            source = joinpath(directory,"source")
            run(`git init --quiet --initial-branch=fixture $source`)
            bytes = "name = \"CheckoutFixture\"\nversion = \"0.1.0\"\n"
            write(joinpath(source,"Project.toml"),bytes)
            run(`git -C $source add Project.toml`)
            run(`git -C $source commit --quiet -m fixture`)
            checkout = joinpath(directory,"checkout")
            clone_cohort(source,"fixture",checkout)
            @test read(joinpath(checkout,"Project.toml"),String)==bytes
            @test strip(read(`git -C $checkout config --local core.autocrlf`,String))=="false"
            @test strip(read(`git -C $checkout rev-parse HEAD`,String))==strip(read(`git -C $source rev-parse HEAD`,String))
            @test read(global_config,String)==global_bytes
            existing = joinpath(checkout,"user-file.txt")
            write(existing,"preserve this existing file")
            @test_throws ProcessFailedException clone_cohort(source,"fixture",checkout)
            @test read(existing,String)=="preserve this existing file"
        end
    end
end

@testset "One-command Hexaly host preparation fails closed" begin
    stages=String[]
    prepare=opts->push!(stages,"setup")
    function qualification(opts; require_hexaly=false)
        @test opts["hexaly"]=="resolved-hexaly"
        @test require_hexaly
        push!(stages,"qualified")
    end
    unavailable=name->throw(NativeSolvers.UnavailableSolver("hexaly_native","license_unavailable"))
    function broken_qualification(opts; require_hexaly=false)
        push!(stages,"invalid-model")
        error("invalid original solution")
    end
    mktemp() do path, output
        redirect_stdout(output) do
            @test_throws NativeSolvers.UnavailableSolver check(Dict{String,String}();
                hexaly_resolver=unavailable,setup_runner=prepare,qualification_runner=qualification)
            @test isempty(stages)
            @test_throws ErrorException check(Dict{String,String}();hexaly_resolver=name->"resolved-hexaly",
                setup_runner=prepare,qualification_runner=broken_qualification)
            @test stages==["setup","invalid-model"]
        end
        flush(output)
        @test !occursin("READY:",read(path,String))
        empty!(stages)
        redirect_stdout(output) do
            check(Dict{String,String}();hexaly_resolver=name->"resolved-hexaly",
                setup_runner=prepare,qualification_runner=qualification)
        end
        flush(output)
        @test stages==["setup","qualified"]
        @test occursin("READY:",read(path,String))
    end
end
