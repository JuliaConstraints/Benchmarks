include("activate.jl")
using TOML, SHA, UUIDs
length(ARGS)==1 || error("usage: report.jl <campaign-uuid>")
campaign=datadir("sims",string(UUID(only(ARGS))))
metadata=TOML.parsefile(joinpath(campaign,"started.toml"))
include(joinpath(campaign,"snapshot","vendor","formulations","Benchmarks.jl"))
using .Benchmarks
validated=0
for id in metadata["instances"]
    dir=joinpath(campaign,id)
    isfile(joinpath(dir,"completed.toml")) || continue
    model=TOML.parsefile(joinpath(dir,"model.toml"))
    bytes2hex(sha256(read(joinpath(dir,"instance.txt"))))==model["source_sha256"] || error("input digest mismatch")
    p=read_benchmark(joinpath(dir,"instance.txt"),:li_lim;id=id)
    model["full_source_fleet"]==p.data.vehicles || error("restricted fleet")
    for filename in ("baseline.toml","result.toml")
        record=TOML.parsefile(joinpath(dir,filename))
        get(record,"accepted",false) || continue
        routes=[route.+1 for route in record["routes_source_node_ids"]]
        validation=validate_solution(p,routes)
        validation.valid || error("stored route solution is invalid")
        validation.objective.vehicles==record["vehicles"] || error("fleet objective mismatch")
        isapprox(validation.objective.distance,record["distance"];atol=1e-6,rtol=0) || error("distance objective mismatch")
        global validated+=1
    end
end
println("Revalidated ",validated," stored solutions against original input files.")
reference=Dict("lc101"=>(10,828.94),"lr101"=>(19,1650.80),"lrc101"=>(14,1708.80))
output=joinpath(campaign,"report.md")
ispath(output) && error("report already exists")
open(output,"w") do io
    println(io,"# Essai exploratoire Li–Lim\n")
    println(io,"Quatre CPU (4–7), HiGHS configuré à quatre threads, une instance à la fois, 30 secondes de résolution par instance. Flotte complète et distances Float64. Le HPO concurrent partage mémoire, caches et fréquence.\n")
    println(io,"| Instance | Insertion Julia : véhicules / distance | HiGHS–JuMP : véhicules / distance | Flotte prouvée | Résolution (s) | Référence SINTEF |")
    println(io,"|---|---:|---:|---|---:|---:|")
    for id in metadata["instances"]
        dir=joinpath(campaign,id)
        baseline=isfile(joinpath(dir,"baseline.toml")) ? TOML.parsefile(joinpath(dir,"baseline.toml")) : Dict()
        initial=get(baseline,"accepted",false) ? string(baseline["vehicles"]," / ",round(baseline["distance"];digits=2)) : "aucune solution validée"
        answer="échec/incomplet";proven="non";seconds="—"
        if isfile(joinpath(dir,"completed.toml"))
            digest=bytes2hex(sha256(read(joinpath(dir,"result.toml"))))
            TOML.parsefile(joinpath(dir,"completed.toml"))["result_sha256"]==digest || error("result digest mismatch")
            result=TOML.parsefile(joinpath(dir,"result.toml"))
            answer=result["accepted"] ? string(result["vehicles"]," / ",round(result["distance"];digits=2)) : "aucun incumbent validé"
            proven=result["fleet_optimal"] ? "oui" : "non"
            seconds=string(round(result["solve_seconds"];digits=2))
        end
        println(io,"| ",id," | ",initial," | ",answer," | ",proven," | ",seconds," | ",reference[id][1]," / ",reference[id][2]," |")
    end
    println(io,"\nRéférences relevées le 12 septembre 2026 sur [SINTEF](https://www.sintef.no/projectweb/top/pdptw/100-customers/). Le nombre de véhicules est prioritaire sur la distance ; les références publiées ne sont pas des temps de calcul comparables.\n")
    println(io,"La référence d'insertion est une heuristique Julia dédiée, pas CBLS. HiGHS reçoit cette solution en démarrage et ne minimise la distance qu'après preuve du nombre minimal de véhicules. Les temps du tableau excluent acquisition, construction de la solution initiale et du modèle ; consulter les fichiers baseline/model/supervision pour ces coûts.\n")
    println(io,"Les parcours Li–Lim CBLS/LSS, GHOST, JuLS, Timefold et Hexaly restent non qualifiés. Cet essai ne classe pas ces solveurs.\n")
    for id in metadata["instances"]
        dir=joinpath(campaign,id)
        if isfile(joinpath(dir,"result.toml"))
            result=TOML.parsefile(joinpath(dir,"result.toml"))
            println(io,"- ",id," : ",join([phase["objective"]*"="*phase["status"]*", borne="*string(phase["bound"]) for phase in result["phases"]]," ; "))
        end
    end
end
println("Report: ",output)
