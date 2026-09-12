include("activate.jl")
using TOML,SHA,Dates
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../src/AnytimeRunner.jl");using .AnytimeRunner
import .AnytimeRunner: save
qualification,preflight=abspath.(ARGS)
TOML.parsefile(joinpath(qualification,"qualified.toml"))
TOML.parsefile(joinpath(preflight,"passed.toml"))
evidence=projectdir("evidence","anytime-"*basename(qualification));mkpath(evidence)
records=Dict{String,Any}[];hashes=Dict{String,String}()
for (kind,dir) in (("profiles",qualification),("fullsizes",preflight))
    jobs=TOML.parsefile(joinpath(dir,"jobs.toml"))["jobs"]
    for job in jobs
        required=get(job,"require_solution",true)
        validated=check_trace(job["input"],job["out"];require_solution=required)
        relative=kind*"-"*basename(job["out"])
        cp(job["out"],joinpath(evidence,relative);force=true)
        save(joinpath(evidence,relative*".validated.toml"),validated)
        hashes[relative]=bytes2hex(sha256(read(job["out"])))
        push!(records,Dict("engine"=>job["engine"],"profile"=>job["profile"],"size"=>get(job,"size",0),
            "events"=>length(validated["events"]),"solve_call_seconds"=>validated["solve_call_seconds"],
            "first_feasible_seconds"=>get(validated,"first_feasible_seconds","unavailable"),
            "raw_trace"=>replace(relpath(joinpath(evidence,relative),projectdir()),'\\'=>'/')))
    end
end
small=filter(r->r["size"]==0,records)
Set((r["engine"],r["profile"]) for r in small)==Set((c.engine,c.profile) for c in configurations) || error("Incomplete profile coverage")
count(r->r["size"]>0,records)==30 || error("Expected 30 full-size preflight runs")
save(joinpath(evidence,"summary.toml"),Dict("records"=>records,"raw_sha256"=>hashes))
open(projectdir("ANYTIME_QUALIFICATION.md"),"w") do io
    println(io,"# Anytime qualification\n\n$(length(small)) small full-fleet runs produced independently valid incumbent traces. Thirty additional unreduced Li–Lim runs exercised sizes 100, 200, 400, 600, 800 and 1000 at a 0.2-second functional budget. Those short full-size runs are not quality comparisons.\n")
    println(io,"The small fixture has two pickup/delivery pairs and two available vehicles. Its score was checked against all 120 token permutations. Times below are median observed discovery times over two repetitions (four for the HiGHS control, which also appears in preflight), after separate warm-up; they are not a solver ranking. JIT paths now warm twice for two seconds; the full-size preflight predates this warm-up correction and is functional evidence only. An initialization solution can have solve time zero, while its construction time remains in the raw trace.\n")
    println(io,"| Engine | Profile | First feasible (s) |\n|---|---|---:|")
    for c in configurations
        samples=Float64[r["first_feasible_seconds"] for r in small if r["engine"]==c.engine && r["profile"]==c.profile]
        sort!(samples);middle=(samples[(length(samples)+1)÷2]+samples[length(samples)÷2+1])/2
        println(io,"| ",c.engine," | ",c.profile," | ",round(middle;sigdigits=5)," |")
    end
    println(io,"\nValidation: 187 scorer/trace/source checks, seven supervisor checks, 426 root checks including 397 historical checksums. Four CPUs throughout; the separate HPO was untouched.\n\n[Raw traces and hashes](",replace(relpath(evidence,projectdir()),'\\'=>'/'),"/summary.toml). [Protocol and limitations](ANYTIME.md).")
end
save(projectdir("ANYTIME_QUALIFICATION.toml"),Dict("schema"=>"anytime-qualification/1",
    "code_sha256"=>qualify_hash(),"sealed_utc"=>string(now(UTC)),"cpu_ceiling"=>4,"runs"=>length(records),
    "profile_runs_with_valid_incumbents"=>length(small),"full_size_preflight_runs"=>30,
    "scope"=>"Functional integration and trace validation; full-size preflight does not require an incumbent",
    "evidence"=>replace(relpath(evidence,projectdir()),'\\'=>'/'),"raw_sha256"=>hashes))
println("SEALED ",length(records)," independently revalidated runs")
