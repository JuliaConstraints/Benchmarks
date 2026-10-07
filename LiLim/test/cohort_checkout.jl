using Test
include(joinpath(@__DIR__,"..","scripts","colleague.jl"))

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
