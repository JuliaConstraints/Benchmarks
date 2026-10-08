using Test
include(joinpath(@__DIR__,"..","scripts","colleague.jl"))

@testset "Qualification worker caps respect the allocated CPUs" begin
    for test in ("ortools_parallel.jl","icn_resources.jl","classical_strategy_panel","structured_routing.jl")
        @test qualification_width(Dict("cpus"=>"8"),test)==1
        @test qualification_width(Dict("cpus"=>"8,9,10,11"),test)==2
    end
    @test qualification_width(Dict("cpus"=>"8,9"),"strategy_panel.jl")==1
end

@testset "Colleague matrix defaults to four CPU slots; local eight-slot scheduling is explicit" begin
    for cpus in (collect(0:3),collect(0:6),[8,10,0,2,4,6,12,14])
        waves=matrix_waves(cpus)
        @test [job.width for wave in waves for job in wave]==[1,2,4]
        for wave in waves
            used=reduce(vcat,(j.cpus for j in wave))
            @test allunique(used) && length(used)<=4
            @test all(j->length(j.cpus)==j.width,wave)
        end
    end
    @test length(matrix_waves(collect(0:7)))==2
    @test [[job.width for job in wave] for wave in matrix_waves(collect(0:7))]==[[1,2],[4]]
    @test length(matrix_waves(collect(0:7);slots=8))==1
    @test_throws ArgumentError matrix_waves([0,1])
    @test_throws ArgumentError matrix_waves([0,0,1,2])
    @test_throws ArgumentError matrix_waves(collect(0:7),[1,8])
    @test_throws ArgumentError matrix_waves(collect(0:8);slots=9)
    nested=Dict("waves"=>[[Dict("width"=>j.width,"cpus"=>j.cpus) for j in w] for w in matrix_waves(collect(0:7))])
    io=IOBuffer();TOML.print(io,nested)
    @test TOML.parse(String(take!(io)))==nested
end

@testset "Available native preflight records accept structured profile evidence" begin
    row=available_solver_record("ortools",Dict("ortools_version"=>"9.14.6206"))
    row["profiles"]=Dict("routing_gls"=>Dict("status"=>"passed"))
    @test row isa Dict{String,Any}
    @test row["version"]=="9.14.6206" && row["profiles"]["routing_gls"]["status"]=="passed"
    @test available_solver_record("timefold",Dict("version"=>"1.21.0"))["version"]=="1.21.0"
    @test available_solver_record("hexaly","unused";fingerprint=_ ->"fixture")["executable_sha256"]=="fixture"
    io=IOBuffer();TOML.print(io,row)
    @test TOML.parse(String(take!(io)))==row
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
