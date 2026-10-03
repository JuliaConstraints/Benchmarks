module CurrentReport
using TOML, SHA, Dates, Statistics, ConstraintModels
using ConstraintModels.Benchmarks

digest(path) = bytes2hex(sha256(read(path)))
quality(record) = (record["vehicles"],record["distance"])
const REFERENCE_URL = "https://www.sintef.no/projectweb/top/pdptw/100-customers/"
const PUBLISHED_REFERENCES = Dict("lc101"=>(10,828.94),"lr101"=>(19,1650.80),"lrc101"=>(14,1708.80))
function compare(a,b)
    a[1]!=b[1] && return a[1]<b[1] ? -1 : 1
    abs(a[2]-b[2])<=1e-8 && return 0
    a[2]<b[2] ? -1 : 1
end
function validate_campaign(path)
    isfile(joinpath(path,"completed.toml")) || error("incomplete campaign")
    metadata = TOML.parsefile(joinpath(path,"started.toml"))
    config = metadata["config"]
    config["schema"]=="li-lim-meta-pilot/1" || error("unknown schema")
    for (relative,expected) in metadata["source_sha256"]
        digest(joinpath(path,"snapshot",relative))==expected || error("snapshot digest mismatch: $relative")
    end
    for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
        digest(joinpath(path,"snapshot",file))==metadata[key] || error("environment snapshot changed")
    end
    cm = pkgdir(ConstraintModels)
    strip(read(`git -C $cm rev-parse HEAD`,String))==config["cohort"]["ConstraintModels"] || error("validator revision mismatch")
    isempty(strip(read(`git -C $cm status --porcelain --untracked-files=no`,String))) || error("validator checkout changed")
    rows = Dict{String,Any}[]
    runtime = Dict{String,Any}()
    for id in config["instances"]
        dir = joinpath(path,id)
        isfile(joinpath(dir,"completed.toml")) || error("incomplete instance: $id")
        supervision = TOML.parsefile(joinpath(dir,"supervision.toml"))
        supervision["exitcode"]==0 && supervision["reason"]=="normal_exit" || error("censored instance: $id")
        source = joinpath(dir,"instance.txt")
        digest(source)==config["source_sha256"][id] || error("source bytes changed: $id")
        p = read_benchmark(source,:li_lim;id)
        runtime[id] = Dict("runtime"=>TOML.parsefile(joinpath(dir,"runtime.toml")),"supervision"=>supervision)
        for file in sort(filter(name->endswith(name,".result.toml"),readdir(dir)))
            resultpath = joinpath(dir,file)
            marker = replace(file,".result.toml"=>".completed.toml")
            isfile(joinpath(dir,marker)) || error("unsealed result: $file")
            expected = TOML.parsefile(joinpath(dir,marker))["result_sha256"]
            digest(resultpath)==expected || error("result digest mismatch: $file")
            row = TOML.parsefile(resultpath)
            row["instance"]==id && row["source_sha256"]==config["source_sha256"][id] || error("result identity mismatch")
            row["threads"]==1 || error("resource identity mismatch")
            validated = validate_solution(p,row["routes"])
            validated.valid || error("invalid original solution: $file")
            checked = (validated.objective.vehicles,validated.objective.distance)
            compare(checked,quality(row))==0 || error("reported objective mismatch: $file")
            [[p.provenance["source_node_ids"][i] for i in route] for route in row["routes"]] == row["routes_source_node_ids"] || error("source-id mismatch")
            previous_time = 0.
            previous_quality = (typemax(Int),Inf)
            for event in row["trajectory"]
                previous_time<=event["seconds"]<=row["budget_seconds"] || error("invalid event timestamp")
                compare(quality(event),previous_quality)<=0 || error("nonmonotone incumbent")
                previous_time = event["seconds"];previous_quality = quality(event)
            end
            row["eligible"] == (row["initial_seconds"]<=row["budget_seconds"]) || error("initial eligibility mismatch")
            if row["eligible"]
                !isempty(row["trajectory"]) && compare(quality(last(row["trajectory"])),quality(row))==0 || error("missing eligible final evidence")
            else
                isempty(row["trajectory"]) || error("ineligible start has events")
            end
            for event in get(row["trace"],"trajectory",Any[])
                v = validate_solution(p,event["routes"])
                v.valid && compare((v.objective.vehicles,v.objective.distance),quality(event))==0 || error("invalid owned CBLS snapshot")
            end
            row["raw_result_sha256"] = expected
            row["raw_result_relative"] = joinpath(id,file)
            push!(rows,row)
        end
    end
    expected = Set((id,method,budget,seed) for id in config["instances"],method in config["methods"],
        budget in config["budgets_seconds"],seed in config["seeds"])
    keys = [(row["instance"],row["method"],row["budget_seconds"],row["seed"]) for row in rows]
    length(keys)==length(expected) && allunique(keys) && Set(keys)==expected || error("campaign matrix incomplete or duplicated")
    (; metadata,rows,runtime)
end

function summarize(qualified)
    rows,config = qualified.rows,qualified.metadata["config"]
    groups = Any[]
    for id in config["instances"],budget in config["budgets_seconds"],method in config["methods"]
        selected = filter(row->row["instance"]==id && row["method"]==method && row["budget_seconds"]==budget,rows)
        usable = filter(row->row["eligible"],selected)
        qualities = sort(quality.(usable))
        repairs = [repair for row in selected for repair in get(row["trace"],"repairs",Any[])]
        status_counts = Dict{String,Int}()
        for repair in repairs
            status = repair["status"]
            status_counts[status] = get(status_counts,status,0)+1
        end
        group = Dict{String,Any}("instance"=>id,"budget_seconds"=>budget,"method"=>method,
            "jobs"=>length(selected),"eligible"=>length(usable),"repair_statuses"=>status_counts,
            "repairs"=>length(repairs),"useful_repairs"=>get(status_counts,"improved",0),
            "max_wall_overrun_seconds"=>max(0.,maximum(row->row["wall_seconds"]-budget,selected)),
            "median_wall_seconds"=>median([row["wall_seconds"] for row in selected]))
        target = PUBLISHED_REFERENCES[id]
        target_times = Float64[]
        for row in usable
            reached = findfirst(event->event["vehicles"]<target[1] ||
                (event["vehicles"]==target[1] && round(event["distance"];digits=2)<=target[2]),row["trajectory"])
            reached===nothing || push!(target_times,row["trajectory"][reached]["seconds"])
        end
        group["published_target_reached"] = length(target_times)
        isempty(target_times) || (group["median_target_seconds_among_successes"] = median(target_times))
        if !isempty(qualities)
            middle = qualities[cld(length(qualities),2)]
            merge!(group,Dict("median_vehicles"=>middle[1],"median_distance"=>middle[2],
                "best_vehicles"=>first(qualities)[1],"best_distance"=>first(qualities)[2],
                "worst_vehicles"=>last(qualities)[1],"worst_distance"=>last(qualities)[2]))
        end
        for phase in ("build_seconds","solve_seconds","validation_seconds")
            samples = Float64[repair["trace"][phase] for repair in repairs if haskey(repair["trace"],phase)]
            isempty(samples) || (group["median_fragment_"*phase] = median(samples))
        end
        push!(groups,group)
    end
    comparisons = Any[]
    for method in ("hybrid_specialized","hybrid_bridged"),reference in ("cbls","highs")
        wins=ties=losses=0
        for row in filter(row->row["method"]==method && row["eligible"],rows)
            other = only(filter(candidate->candidate["instance"]==row["instance"] &&
                candidate["budget_seconds"]==row["budget_seconds"] && candidate["seed"]==row["seed"] &&
                candidate["method"]==reference,rows))
            other["eligible"] || continue
            relation = compare(quality(row),quality(other))
            wins += relation<0;ties += relation==0;losses += relation>0
        end
        push!(comparisons,Dict("method"=>method,"reference"=>reference,"wins"=>wins,"ties"=>ties,"losses"=>losses))
    end
    Dict("groups"=>groups,"comparisons"=>comparisons)
end

function write_report(campaign,base)
    qualified = validate_campaign(campaign)
    summary = summarize(qualified)
    for suffix in (".toml",".md")
        ispath(base*suffix) && error("report destination exists")
    end
    mkpath(dirname(base))
    record = Dict("schema"=>"li-lim-meta-pilot-report/1","campaign"=>abspath(campaign),
        "audited_utc"=>string(now(UTC)),"metadata"=>qualified.metadata,"runtime"=>qualified.runtime,
        "summary"=>summary,"cases"=>qualified.rows)
    record["published_reference"] = Dict("url"=>REFERENCE_URL,"consulted_date"=>"2026-10-04",
        "scope"=>"best known quality, displayed to two decimals; not comparable runtime or a general optimality proof",
        "rows"=>[Dict("instance"=>id,"vehicles"=>q[1],"distance_two_decimals"=>q[2]) for (id,q) in sort!(collect(PUBLISHED_REFERENCES);by=first)])
    open(io->TOML.print(io,record;sorted=true),base*".toml","w")
    open(base*".md","w") do io
        println(io,"# Premier pilote Li-Lim CBLS–HiGHS — 4 octobre 2026\n")
        println(io,"Les ",length(qualified.rows)," exécutions ont été auditées : empreintes, matrice, budgets des événements, routes originales et identifiants source. Le protocole est [CURRENT_PILOT.md](../CURRENT_PILOT.md). Les résultats complets et les traces essentielles sont dans [le fichier TOML](",basename(base),".toml).\n")
        println(io,"Référence des sources mesurées : `",qualified.metadata["benchmarks_commit"],"`. Une ligne décrit la médiane lexicographique de trois graines ; la distance se compare après la flotte.\n")
        println(io,"| Instance | Budget | Méthode | Admissibles | Flotte médiane | Distance médiane | Réparations utiles / appels |\n|---|---:|---|---:|---:|---:|---:|")
        for group in summary["groups"]
            println(io,"| ",group["instance"]," | ",Int(group["budget_seconds"])," s | ",group["method"]," | ",group["eligible"],"/",group["jobs"]," | ",get(group,"median_vehicles","—")," | ",round(get(group,"median_distance",NaN);digits=3)," | ",group["useful_repairs"],"/",group["repairs"]," |")
        end
        println(io,"\nComparaisons appariées par instance, budget et graine. Ce comptage ne constitue pas un test statistique de supériorité.\n")
        println(io,"| Variante | Référence | Meilleurs | Égaux | Moins bons |\n|---|---|---:|---:|---:|")
        for comparison in summary["comparisons"]
            println(io,"| ",comparison["method"]," | ",comparison["reference"]," | ",comparison["wins"]," | ",comparison["ties"]," | ",comparison["losses"]," |")
        end
        println(io,"\nLes [meilleures valeurs connues publiées par SINTEF](",REFERENCE_URL,") consultées le 4 octobre 2026 sont ci-dessous. Les distances publiées sont affichées à deux décimales ; nos calculs conservent la précision originale. Aucune solution externe n'a été injectée dans l'initialisation.\n")
        println(io,"| Instance | Flotte publiée | Distance publiée |\n|---|---:|---:|")
        for id in qualified.metadata["config"]["instances"]
            q = PUBLISHED_REFERENCES[id]
            println(io,"| ",id," | ",q[1]," | ",q[2]," |")
        end
        println(io,"\nAtteinte de cette cible à deux décimales : la médiane de temps porte uniquement sur les réussites. Les autres exécutions sont censurées au budget, sans temps de réussite inventé.\n")
        println(io,"| Instance | Budget | Méthode | Cible atteinte | Temps médian parmi réussites |\n|---|---:|---|---:|---:|")
        for group in summary["groups"]
            seconds = haskey(group,"median_target_seconds_among_successes") ? string(round(group["median_target_seconds_among_successes"];digits=4)," s") : "—"
            println(io,"| ",group["instance"]," | ",Int(group["budget_seconds"])," s | ",group["method"]," | ",group["published_target_reached"],"/",group["jobs"]," | ",seconds," |")
        end
        println(io,"\nLes quatre méthodes disposent du même CPU et du même point de départ, dont la construction est comptée. Les solutions intermédiaires HiGHS sont observées et validées dans le budget. Les résultats CBLS proviennent de snapshots validés dans une horloge commune. Les validations d'audit et l'archivage sont postérieurs à la recherche.\n")
        println(io,"| Instance | Chargement | Échauffement | RSS maximale | Temps mural enfant |\n|---|---:|---:|---:|---:|")
        for id in qualified.metadata["config"]["instances"]
            runtime = qualified.runtime[id]
            println(io,"| ",id," | ",round(runtime["runtime"]["loading_seconds"];digits=2)," s | ",round(runtime["runtime"]["warmup_seconds"];digits=2)," s | ",round(runtime["supervision"]["peak_rss_bytes"]/1024^3;digits=2)," Gio | ",round(runtime["supervision"]["wall_seconds"];digits=2)," s |")
        end
        println(io,"\nLimites : trois instances déjà exposées, trois graines, exécutions échauffées, profil CBLS minimal à score direct sans ICN, fragments plafonnés à vingt visites, et formulation HiGHS précise sur un CPU. Les DAG de bridge sont des égalités à poids manuels, avec temps et charges continus explicites. MetaStrategist adaptatif, Timefold et Hexaly ne sont pas comparés. Les trajectoires des deux hybrides peuvent sélectionner des fragments différents. Une supériorité générale et une parité statistique ne découlent pas de ce diagnostic.\n")
        println(io,"Les traces publient les dépassements coopératifs, statuts et coûts des réparations. Aucun incumbent tardif n'entre dans la qualité annoncée. Le fichier TOML préserve les solutions, programmes de bridge et versions nécessaires pour reprendre les expériences.")
    end
    summary
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: current_report.jl campaign-directory output-base")
    result = CurrentReport.write_report(abspath(ARGS[1]),abspath(ARGS[2]))
    println("Audited report: ",abspath(ARGS[2]),".md")
    for row in result["comparisons"]
        println(row)
    end
end
