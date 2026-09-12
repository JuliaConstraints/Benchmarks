include("activate.jl")
using TOML, SHA, Dates
include(srcdir("RoutingSmoke.jl"))
using .RoutingSmoke
attempt=abspath(ARGS[1]);p=fixture();opt=oracle(p)
w=[12,7,11,8,9,6,13,5,14,10,3,4];v=[24,13,23,15,16,11,28,9,30,19,5,8];capacity=40
bagopt=maximum(sum(v[i] for i in eachindex(v) if (m>>(i-1))&1==1;init=0)
    for m in 0:(1<<length(v))-1 if sum(w[i] for i in eachindex(w) if (m>>(i-1))&1==1;init=0)<=capacity)
records=Dict{String,Any}[]
function inspect(family,engine,seed)
    path=joinpath(attempt,family,"$engine-$seed.toml")
    isfile(path) || error("Missing required solver record: $path")
    r=TOML.parsefile(path)
    if family=="knapsack"
        x=r["values"]
        valid=length(x)==length(v) && all(in(0:1),x) && sum(w.*x)<=capacity
        valid || error("Invalid knapsack result: $path")
        objective=sum(v.*x);objective<=bagopt || error("Oracle exceeded")
        haskey(r,"objective") && r["objective"]!=objective && error("Objective disagreement")
        gap=bagopt-objective
    else
        if !get(r,"found",true)
            valid=false;objective="no feasible incumbent";gap="unavailable"
        else
            route=Int.(r["route"]);validation=validate(p,route)
            validation.valid || error("Invalid route in $path: $(validation.errors)")
            valid=true;objective=validation.objective.distance;gap=objective-opt["distance"]
            gap>=-1e-8 || error("Oracle exceeded")
            haskey(r,"reported_distance") && !isapprox(r["reported_distance"],objective;atol=1e-8) && error("Native distance mismatch")
        end
        if haskey(r,"final_current_route")
            current_valid=validate(p,Int.(r["final_current_route"])).valid
            current_valid==r["final_current_stored_feasible"] || error("JuLS feasibility bookkeeping mismatch: cannot qualify this adapter")
        end
    end
    push!(records,Dict("family"=>family,"engine"=>engine,"repetition"=>seed,"valid"=>valid,"objective"=>objective,"gap"=>gap,
        "solve_call_seconds"=>r["solve_call_seconds"],"build_seconds"=>r["build_seconds"],"raw_sha256"=>bytes2hex(sha256(read(path)))))
end
bags=["cbls_jump","lss_native","ghost_jump","ghost_native_c","timefold_native","juls_native","highs_control"]
routes=["cbls_jump","timefold_native","ghost_native_cpp","juls_native"]
for engine in bags,seed in 1:3;inspect("knapsack",engine,seed);end
for engine in routes,seed in 1:3;inspect("routing",engine,seed);end
open(io->TOML.print(io,Dict("records"=>records,"checked_at_utc"=>string(now(UTC)));sorted=true),joinpath(attempt,"validation.toml"),"w")
median3(x)=sort(x)[2]
open(joinpath(attempt,"report.md"),"w") do io
    println(io,"# Validation des solveurs — petit pilote\n")
    println(io,"Tentative : `",basename(attempt),"`. Quatre CPU logiques (4–7), exécutions séquentielles. Trois répétitions, deux secondes demandées par résolution, après un échauffement distinct. HPO actif sur CPU 0–3 ; mémoire, cache et fréquence restent partagés.\n")
    println(io,"## ILP : sac à dos à 12 variables binaires\n\nCapacité 40. Optimum **$bagopt**, vérifié par les 4096 affectations. Maximisation ; les colonnes donnent les résultats des trois répétitions.\n")
    println(io,"| Moteur / interface | Objectifs | Valides | Temps résolution médian (s) | Construction médiane (s) |\n|---|---|---:|---:|---:|")
    for engine in bags
        r=filter(x->x["family"]=="knapsack" && x["engine"]==engine,records)
        println(io,"| $engine | ",join([x["objective"] for x in r],", ")," | ",count(x->x["valid"],r),"/3 | ",round(median3([x["solve_call_seconds"] for x in r]);digits=5)," | ",round(median3([x["build_seconds"] for x in r]);digits=6)," |")
    end
    println(io,"\n## Li–Lim : lc101 réduit à trois requêtes, un véhicule\n\nSix clients, paires complètes, distances et fenêtres originales en Float64, sans arrondi des distances. 720 permutations vérifiées indépendamment ; **$(opt["feasible_permutations"]) tournée faisable**, distance **$(opt["distance"])**. Ce cas teste surtout l'obtention d'une tournée valide. Ce n'est pas lc101 complet.\n")
    println(io,"| Moteur / interface | Valides | Distances obtenues | Temps résolution médian (s) |\n|---|---:|---|---:|")
    for engine in routes
        r=filter(x->x["family"]=="routing" && x["engine"]==engine,records)
        println(io,"| $engine | ",count(x->x["valid"],r),"/3 | ",join([x["valid"] ? string(round(x["objective"];digits=6)) : "aucune solution" for x in r],", ")," | ",round(median3([x["solve_call_seconds"] for x in r]);digits=5)," |")
    end
    println(io,"\n## Portée et limites\n")
    println(io,"- CBLS est la façade JuMP du générateur LocalSearchSolvers. Profil par défaut ici, sans HPO ; quatre travailleurs locaux. LSS natif et CBLS/JuMP sont tous deux testés sur l'ILP.")
    println(io,"- GHOST : JuMP et C ABI natif sur l'ILP (même bibliothèque JLL), C++ natif avec permutation sur Li–Lim. Quatre travailleurs. La graine native n'est pas exposée : les numéros sont des répétitions, pas des graines appariées. Le binaire C++ est recompilé avec le compilateur portable consigné ; il ne sert pas à mesurer le surcoût de JuMP.")
    println(io,"- Timefold 2.6.0 Community, Java 21 portable, formulations natives. Un fil de recherche (défaut Community), plafond processus de quatre CPU. Score non incrémental écrit pour cette validation ; ce modèle n'est pas encore qualifié pour une campagne de performance. Pas d'interface JuMP validée.")
    println(io,"- JuLS natif à la révision enregistrée, sous Julia 1.11.9 : chargement amont incompatible avec Julia 1.13 (`eval`). ILP : initialisation gloutonne, voisinage exhaustif de deux variables, choix glouton et filtrage CP, tous par défaut amont. Routage : invariant de tournée, échanges de deux visites, choix glouton, pénalité 10000, filtrage CP désactivé faute de traduction de cet invariant ; pas d'interface JuMP validée. L'erreur du routage est encodée en unités entières (plafond de violation × 10^6), avant pénalité, pour respecter le test de zéro exact de JuLS. Aucune distance n'est arrondie. Les 10800 transitions par échange ont vérifié la cohérence arithmétique de cette pénalité.")
    println(io,"- HiGHS est seulement le contrôle ILP. Hexaly est exclu à ta demande, licence non activée.")
    println(io,"- Les temps sont ceux de l'appel de résolution après échauffement ; chargement, compilation et lancement des processus sont séparés dans les journaux. Une résolution arrêtée à deux secondes ne mesure pas le temps pour atteindre l'optimum. Ces trois répétitions ne démontrent aucun classement, ni un surcoût négligeable de JuMP.")
    println(io,"- Toutes les solutions retenues sont relues depuis les fichiers, puis validées indépendamment. Une absence de solution reste un résultat, jamais une preuve d'infaisabilité. Les contrôles d'oracle, sources et environnements sont conservés dans cette tentative.")
end
println("Validated ",count(x->x["valid"],records)," incumbents out of ",length(records)," runs. Report: ",joinpath(attempt,"report.md"))
