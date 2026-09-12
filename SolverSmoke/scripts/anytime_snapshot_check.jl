include("activate.jl")
using Test,TOML,UUIDs
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../src/AnytimeRunner.jl");using .AnytimeRunner
import .AnytimeRunner: save
out=datadir("anytime-snapshot-check",string(uuid4()));mkpath(out);warm=fixtures(out)
snapshot=joinpath(out,"snapshot","Benchmarks","SolverSmoke");make_snapshot(snapshot)
ENV["ANYTIME_WARMUP_INPUT"]=warm
println("SNAPSHOT_CHECK=",out);flush(stdout)
@test qualify_hash(source_root=snapshot)==qualify_hash()
results=Dict{String,Any}[]
for c in filter(c->c.profile=="default" || c.engine in ("ghost_native_cpp","juls_native","highs_control"),configurations)
    job=Dict("input"=>warm,"engine"=>c.engine,"profile"=>c.profile,"budget"=>1.,"seed"=>1,"out"=>joinpath(out,c.engine*".toml"))
    println("START ",c.engine);flush(stdout)
    process=execute(command(job,warm;worker_root=snapshot),job["out"]*".log";wall=180.)
    @test process["exitcode"]==0
    result=check_trace(warm,job["out"];require_solution=true)
    @test result["independently_validated"]
    push!(results,merge(Dict("engine"=>c.engine),process))
end
save(joinpath(out,"passed.toml"),Dict("source_sha256"=>qualify_hash(),"results"=>results))
println("SNAPSHOT_PASSED=",out)
