using ConstraintModels, TOML, SHA, Statistics, Printf
using ConstraintModels.Benchmarks
length(ARGS)==1 || error("usage: all_variants_report.jl output-summary.toml")
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=abspath(ARGS[1])
const METHODS=["cbls_naive","cbls_icn","cbls_direct","cbls_mix_strategy","hybrid_specialized_icn","hybrid_bridged_icn",
    "highs_native","highs_portfolio","mixed_balanced","mixed_ls_heavy","timefold_late","timefold_late1000","ghost","juls_greedy","juls_annealing"]
const LABELS=["CBLS naïf","CBLS ICN","CBLS direct","CBLS mix politiques","Hybride spécialisé ICN","Hybride bridgé ICN",
    "HiGHS natif","HiGHS multi-départ","MetaStrategist équilibré","MetaStrategist priorité CBLS","Timefold LA 400","Timefold LA 1 000","GHOST natif","JuLS greedy / 64 swaps","JuLS annealing / 64 swaps"]
const CONFIG=TOML.parsefile(joinpath(ROOT,"config/icn-threads.toml"));const TARGETS=TOML.parsefile(joinpath(ROOT,"config/diagnostic-targets.toml"))
const CASES=Dict(id=>read_benchmark(joinpath(ROOT,"data/raw/pdp_100",id*".txt"),:li_lim;id) for id in CONFIG["instances"])
const RECORDS=Any[];const CAPTURES=Any[]
digest(p)=bytes2hex(sha256(read(p)))
function capture(file)
    path=joinpath(ROOT,"results",file);c=TOML.parsefile(path);get(c,"complete",false) || error("unfinished capture $file")
    c["budget_seconds"]==5. || error("unequal budget")
    push!(CAPTURES,Dict("path"=>file,"sha256"=>digest(path),"benchmarks_commit"=>c["benchmarks_commit"]))
    c
end
function appendtrial(r,id,method,width,file,initial,metrics=r)
    r["original_validation"] || error("unvalidated trial")
    p=CASES[id];v=validate_solution(p,r["routes"])
    v.valid && v.objective.vehicles==r["vehicles"] && isapprox(v.objective.distance,r["distance"];atol=1e-7,rtol=1e-12) || error("result audit")
    events=Any[]
    for e in r["trajectory"]
        0<=e["seconds"]<=5. || error("late observation")
        q=validate_solution(p,e["routes"]);q.valid && q.objective.vehicles==e["vehicles"] && isapprox(q.objective.distance,e["distance"];atol=1e-7,rtol=1e-12) || error("trajectory audit")
        push!(events,Dict("seconds"=>e["seconds"],"vehicles"=>q.objective.vehicles,"distance"=>q.objective.distance))
    end
    isempty(events) && error("empty trajectory")
    record=Dict{String,Any}("instance"=>id,"method"=>method,"threads"=>width,"vehicles"=>v.objective.vehicles,"distance"=>v.objective.distance,
        "initial_vehicles"=>initial.vehicles,"initial_distance"=>initial.distance,"trajectory"=>events,"capture"=>file,
        "seed_or_repetition"=>get(r,"seed",get(r,"repetition",0)),"mean_active_cpus"=>get(metrics,"mean_active_cpus",metrics["process_cpu_seconds"]/metrics["wall_seconds"]))
    if haskey(r,"workers")
        record["pair_candidates_per_second"]=sum(get(w["trace"],"pair_candidates",0) for w in r["workers"])/5
        record["search_gc_seconds"]=r["search_gc_seconds"]
        record["repair_build_seconds"]=sum(get(repair["trace"],"build_seconds",0.) for w in r["workers"] for repair in get(w["trace"],"repairs",Any[]);init=0.)
        record["repairs"]=sum(length(get(w["trace"],"repairs",Any[])) for w in r["workers"])
    end
    push!(RECORDS,record)
end
for width in CONFIG["thread_counts"]
    file="all-variants-core-$(width)t-20261004.toml";c=capture(file)
    for r in c["trials"];appendtrial(r,r["instance"],r["method"],width,file,(vehicles=r["initial_vehicles"],distance=r["initial_distance"])) end
    for (method,pattern) in (("timefold_late","timefold-late"),("timefold_late1000","timefold-late1000"),("ghost","all-variants-ghost"),("juls_greedy","all-variants-juls-greedy"),("juls_annealing","all-variants-juls-annealing"))
        file="$(pattern)-$(width)t-20261004.toml";c=capture(file)
        for instance in c["instances"]
            initial=validate_solution(CASES[instance["id"]],instance["initial_routes"]).objective
            for (index,r) in enumerate(instance["qualified_trials"])
                metrics=startswith(method,"timefold") ? instance["native"]["trials"][index] : r
                appendtrial(r,instance["id"],method,width,file,initial,metrics)
            end
        end
    end
end
subset(id,m,w)=filter(r->r["instance"]==id&&r["method"]==m&&r["threads"]==w,RECORDS)
for id in CONFIG["instances"],m in METHODS,w in CONFIG["thread_counts"]
    rows=subset(id,m,w);expected=startswith(m,"mixed_")&&w<4 ? 0 : 3
    length(rows)==expected || error("missing/duplicate cell $id $m $w")
end
hit(r,id)=r["vehicles"]<TARGETS[id]["vehicles"]||(r["vehicles"]==TARGETS[id]["vehicles"]&&r["distance"]<=TARGETS[id]["distance"]+1e-6)
improved(r)=(r["vehicles"],r["distance"])<(r["initial_vehicles"],r["initial_distance"]-1e-6)
summary=Dict("schema"=>"li-lim-all-variants-summary/1","budget_seconds"=>5.,"records"=>RECORDS,"captures"=>CAPTURES,
    "methods"=>METHODS,"labels"=>LABELS,"instances"=>CONFIG["instances"],"widths"=>CONFIG["thread_counts"],"targets"=>TARGETS)
open(io->TOML.print(io,summary;sorted=true),OUT,"w")
open(splitext(OUT)[1]*".md","w") do io
    println(io,"# Réévaluation de toutes les variantes — 4 octobre 2026\n")
    println(io,"$(length(RECORDS)) essais validés : 414 nouveaux essais cœur, 135 nouveaux essais GHOST/JuLS et 90 captures Timefold de cinq secondes. Trois instances déjà exposées, trois seeds ou répétitions, 1/2/4/8/16 workers. Les deux allocations MetaStrategist mixtes commencent à quatre. Les captures de dix secondes ne sont pas utilisées.\n")
    println(io,"Optimisation lexicographique : flotte puis distance. Médiane = deuxième essai dans cet ordre, sans assembler deux solutions différentes. La réussite BKS est descriptive ; LC101 démarre déjà à la référence. Pas de temps de référence homogène dans la table SINTEF. GHOST n'offre pas de seed contrôlée, ses répétitions ne sont pas appariées. Les profils concurrents utilisent des représentations et mouvements distincts ; ces petits diagnostics ne prouvent pas une supériorité commerciale.\n")
    println(io,"## Qualité à seize workers\n\n| Profil | LC101 | LR101 | LRC101 |\n|---|---:|---:|---:|")
    for (m,label) in zip(METHODS,LABELS)
        cells=[begin r=sort(subset(id,m,16);by=r->(r["vehicles"],r["distance"]))[2];@sprintf("%d / %.3f",r["vehicles"],r["distance"]) end for id in CONFIG["instances"]]
        println(io,"| $label | ",join(cells," | ")," |")
    end
    println(io,"\n## Réussite et progrès à seize workers\n\n| Profil | LR101 BKS | LRC101 BKS | LR101 amélioré | LRC101 amélioré | CPU moyen (3 cas) | GC recherche médian |\n|---|---:|---:|---:|---:|---:|---:|")
    for (m,label) in zip(METHODS,LABELS)
        lr=subset("lr101",m,16);lrc=subset("lrc101",m,16);rows=filter(r->r["method"]==m&&r["threads"]==16,RECORDS)
        gc=all(r->haskey(r,"search_gc_seconds"),rows) ? @sprintf("%.4f s",median(r["search_gc_seconds"] for r in rows)) : "—"
        println(io,@sprintf("| %s | %d/3 | %d/3 | %d/3 | %d/3 | %.2f | %s |",label,count(r->hit(r,"lr101"),lr),count(r->hit(r,"lrc101"),lrc),count(improved,lr),count(improved,lrc),mean(r["mean_active_cpus"] for r in rows),gc))
    end
    println(io,"\n## Buffers et préparation\n\nScores naïf/direct/ICN, décodage de routes et réinsertions : workspaces privés par voie. Groupes de réparation réutilisables, programmes de bridge mis en cache par domaine dans chaque resolver, plans MetaStrategist préchargés. Les snapshots restent possédés. Les modèles JuMP/HiGHS sont reconstruits pour chaque fragment et ne partagent pas de handles ; leur coût reste dans le budget RO. Le nouveau mix CBLS combine meilleure/première amélioration, rejets de plateau 10/100/75 %, et réinsertion toutes les 1/4 étapes. À un worker il reproduit le profil ICN standard.\n")
    println(io,"Le CPU CBLS inclut toute la préparation dans le chrono commun. Le CPU des moteurs externes concerne leur processus natif, construction incluse ; le court préfixe Julia commun est chargé au budget mais son CPU n'est pas fusionné. Les warmups et audits finaux sont séparés. Seize workers comprennent 8 cœurs P, 4 E et 4 frères SMT : pas seize cœurs identiques.\n")
    println(io,"Dans le mix équilibré LC101 à quatre workers, seed 41, la voie HiGHS termine vers 0,93 seconde et prouve la flotte et la distance optimales. Les trois autres voies vont jusqu'à cinq secondes. Une moyenne d'environ 3,15 CPU découle donc aussi d'une voie terminée dans cette allocation statique, et ne mesure pas un plafond du débit CBLS. Une redistribution ou un arrêt sur certificat exigerait une nouvelle variante de coordination ; les résultats présents conservent la fusion finale indépendante annoncée.\n")
    println(io,"Hexaly : modèle et lancement préparés, exécutable absent, aucune mesure inventée. GHOST/JuLS : paramètres détaillés dans [COMPETITORS.md](../COMPETITORS.md). Sources, hashes, versions et trajets complets dans les captures listées ci-dessous.\n\n## Captures\n")
    for c in CAPTURES;println(io,"- [",c["path"],"](",c["path"],") — SHA-256 `",c["sha256"],"`") end
end
println("Validated ",length(RECORDS)," trials from ",length(CAPTURES)," captures")
