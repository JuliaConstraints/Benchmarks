include("activate.jl")
using TOML,Dates,UUIDs
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../src/AnytimeRunner.jl");using .AnytimeRunner
import .AnytimeRunner: save
out=datadir("anytime-qualification",string(uuid4()));mkpath(out);warm=fixtures(out)
ENV["ANYTIME_WARMUP_INPUT"]=warm
println("QUALIFICATION=",out);flush(stdout)
jobs=Dict{String,Any}[]
for config in configurations,seed in 1:2
    push!(jobs,Dict("input"=>warm,"engine"=>config.engine,"profile"=>config.profile,
        "budget"=>2.,"seed"=>seed,"out"=>joinpath(out,"$(config.engine)-$(config.profile)-$seed.toml")))
end
save(joinpath(out,"jobs.toml"),Dict("jobs"=>jobs))
lssjobs=filter(j->j["engine"] in ("lss_native","cbls_jump"),jobs)
batch=joinpath(out,"lss-batch.toml");save(batch,Dict("jobs"=>lssjobs))
base=`$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1 --project=$(projectdir())`
process=execute(`$base $(scriptsdir("anytime_lss.jl")) $batch`,joinpath(out,"lss.log");wall=600.)
save(joinpath(out,"lss-process.toml"),process)
process["exitcode"]==0 || error("LSS qualification failed; $out")
for job in filter(j->!(j["engine"] in ("lss_native","cbls_jump")),jobs)
    println("START ",job["engine"]," ",job["profile"]," seed=",job["seed"]);flush(stdout)
    native_process=execute(command(job,warm),job["out"]*".log";wall=180.)
    save(job["out"]*".process.toml",native_process)
    native_process["exitcode"]==0 || error("Native qualification failed: $(job["out"])")
end
results=Dict{String,Any}[]
for job in jobs
    validated=check_trace(warm,job["out"];require_solution=true)
    save(job["out"]*".validated.toml",validated)
    push!(results,Dict("engine"=>job["engine"],"profile"=>job["profile"],"seed"=>job["seed"],
        "events"=>length(validated["events"]),"first_feasible_seconds"=>validated["first_feasible_seconds"]))
end
save(joinpath(out,"qualified.toml"),Dict("code_sha256"=>qualify_hash(),"completed_utc"=>string(now(UTC)),"results"=>results,"scope"=>"30 full-fleet synthetic runs; independently checked accepted incumbents; two two-second warm-up solves per JIT path"))
println("QUALIFIED=",out)
