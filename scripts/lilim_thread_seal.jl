include(joinpath(@__DIR__,"..","SolverSmoke","scripts","activate.jl"))
using TOML,SHA,Dates
include(projectdir("src","Anytime.jl"));using .Anytime
include(projectdir("src","AnytimeValidation.jl"));using .AnytimeValidation
include(projectdir("src","AnytimeRunner.jl"));using .AnytimeRunner
include(joinpath(@__DIR__,"..","src","LiLimSchedule.jl"));using .LiLimSchedule
import .AnytimeRunner: save
qualification,history=abspath.(ARGS)
passed=TOML.parsefile(joinpath(qualification,"passed.toml"))
passed["code_sha256"]==qualify_hash() || error("Qualification source/runtime mismatch")
rows=passed["results"]
expected=Set((c.engine,c.profile,c.threads,s) for c in thread_configurations(configurations).ready for s in 1:3)
Set((r["engine"],r["profile"],r["threads"],r["seed"]) for r in rows)==expected || error("Incomplete thread matrix")
length(rows)==length(expected) || error("Duplicate qualification rows")
evidence=projectdir("evidence","threads-"*basename(qualification));mkpath(evidence)
hashes=Dict{String,String}()
for r in rows
    raw=r["out"];bytes2hex(sha256(read(raw)))==r["raw_sha256"] || error("Raw qualification changed")
    trace=check_trace(r["input"],raw;require_solution=true)
    trace["within_budget_feasible"] && trace["threads"]==r["threads"] || error("Qualification contract failed")
    name=basename(raw);cp(raw,joinpath(evidence,name);force=true)
    save(joinpath(evidence,name*".validated.toml"),trace);hashes[name]=r["raw_sha256"]
end
for name in ("passed.toml","jobs.toml","two-pairs.txt")
    cp(joinpath(qualification,name),joinpath(evidence,name);force=true)
end
for name in filter(n->endswith(n,".process.toml"),readdir(qualification))
    cp(joinpath(qualification,name),joinpath(evidence,name);force=true)
end
historyresult=TOML.parsefile(joinpath(history,"result.toml"))
length(historyresult["rows"])==45 && all(r->r["feasible"],historyresult["rows"]) || error("Historical check incomplete")
historical=projectdir("evidence","historical-"*basename(history));mkpath(historical)
for name in filter(n->endswith(n,".toml") || n in ("report.md","instance.txt","check-source.jl"),readdir(history))
    cp(joinpath(history,name),joinpath(historical,name);force=true)
end
seal=Dict("schema"=>"thread-qualification/1","code_sha256"=>passed["code_sha256"],"configurations"=>41,"runs"=>123,
    "sealed_utc"=>string(now(UTC)),"cpu_ceiling"=>4,"evidence"=>replace(relpath(evidence,projectdir()),'\\'=>'/'),
    "raw_sha256"=>hashes,"scope"=>passed["scope"],"historical_check"=>replace(relpath(historical,projectdir()),'\\'=>'/'))
save(projectdir("THREAD_QUALIFICATION.toml"),seal)
open(projectdir("THREAD_QUALIFICATION.md"),"w") do io
    println(io,"# Qualification des configurations à 1, 2 et 4 threads\n\n123 résolutions sur 41 configurations, trois répétitions de deux secondes : toutes ont livré une solution réalisable dans le budget, vérifiée indépendamment. Les déclarations de threads correspondent au plan et les affinités des processus ont été contrôlées.\n\nInstance de qualification : deux requêtes, deux véhicules. Ce résultat qualifie les chemins d'exécution et l'instrumentation, pas la qualité sur les grandes instances ni l'utilisation constante de tous les threads natifs.")
    println(io,"\nLe contrôle séparé sur les six visites historiques de lc101 a réussi 45/45 résolutions avec les nouveaux modèles de la première campagne, avant cette modification des threads. Il ne doit pas être présenté comme une mesure des nouveaux réglages à 1/2 threads.")
    println(io,"\n[Traces de qualification](",seal["evidence"],"/passed.toml) · [Contrôle historique](",seal["historical_check"],"/report.md).")
end
println("SEALED=",projectdir("THREAD_QUALIFICATION.toml"))
