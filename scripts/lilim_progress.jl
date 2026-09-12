# Read-only analysis of completed campaign jobs; immutable, timestamped reports.
include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
using TOML, Dates, SHA, Statistics, Printf

function observations(campaign)
    rows = Dict{String,Any}[]
    sources = Dict{String,Any}[]
    pending = String[]
    for dir in sort(readdir(joinpath(campaign, "runs"); join=true))
        isdir(dir) || continue
        if !isfile(joinpath(dir, "status.toml"))
            push!(pending, basename(dir)); continue
        end
        row = Dict{String,Any}("run" => basename(dir))
        for file in ("job.toml", "process.toml", "validated.toml", "status.toml")
            path = joinpath(dir, file)
            isfile(path) || continue
            bytes = read(path)
            push!(sources, Dict("path" => relpath(path, campaign), "sha256" => bytes2hex(sha256(bytes))))
            merge!(row, TOML.parse(String(copy(bytes))))
        end
        # Routes remain in the hashed raw/validated files; aggregation needs only quality and time.
        for e in get(row,"events",[]);delete!(e,"values");end
        row["eligible_events"] = filter(e -> get(e,"within_solve_budget",false), get(row,"events",[]))
        push!(rows, row)
    end
    rows, sources, pending
end

function statistics(rows)
    events = [r["eligible_events"] for r in rows]
    feasible = filter(!isempty, events)
    firsts = [first(e)["solve_seconds"] for e in feasible]
    ends = [first(e)["elapsed_seconds"] for e in feasible]
    Dict("completed"=>length(rows), "feasible"=>length(feasible),
        "no_feasible"=>count(r->r["state"]=="no_observed_feasible_incumbent",rows),
        "late_only"=>count(r->r["state"]=="feasible_only_after_budget",rows),
        "errors"=>count(r->r["state"]=="execution_error",rows),
        "censored"=>count(r->r["state"]=="resource_censored",rows),
        "median_first_seconds"=>isempty(firsts) ? "unavailable" : median(firsts),
        "median_first_end_to_end_seconds"=>isempty(ends) ? "unavailable" : median(ends))
end

function targets!(rows)
    targets=Dict{String,Tuple{Int,Float64}}()
    for r in rows, e in r["eligible_events"]
        key=(e["vehicles"],e["distance"])
        targets[r["instance"]]=min(get(targets,r["instance"],(typemax(Int),Inf)),key)
    end
    for r in rows
        haskey(targets,r["instance"]) || continue
        v,d=targets[r["instance"]]
        r["target_vehicles"]=v; r["target_distance"]=d
        i=findfirst(e->e["vehicles"]==v && e["distance"]<=d+1e-8,r["eligible_events"])
        r["target_reached"]=i!==nothing
        if i!==nothing
            r["time_to_target_seconds"]=r["eligible_events"][i]["solve_seconds"]
        end
    end
end

fmt(x::Real)=@sprintf("%.4g",x)
fmt(x)=x=="unavailable" ? "—" : string(x)
function report(campaign)
    campaign=abspath(campaign)
    rows,sources,pending=observations(campaign);targets!(rows)
    started=TOML.parsefile(joinpath(campaign,"started.toml"))
    total=started["instances"]*started["configurations"]*length(started["budgets"])*length(started["seeds"])
    stamp=Dates.format(now(UTC),"yyyymmddTHHMMSSsss")
    out=joinpath(campaign,"reports",stamp);mkpath(out)
    attempts=Dict{String,Any}[]
    archive_root=joinpath(campaign,"attempts")
    if isdir(archive_root)
        for (dir,_,files) in walkdir(archive_root)
            "archive.toml" in files || continue
            path=joinpath(dir,"archive.toml");bytes=read(path)
            a=TOML.parse(String(copy(bytes)));a["directory"]=relpath(dir,campaign)
            push!(attempts,a)
            push!(sources,Dict("path"=>relpath(path,campaign),"sha256"=>bytes2hex(sha256(bytes))))
        end
    end
    group(r)=(r["engine"],r["profile"],string(get(r,"threads","unreported")),r["budget"],r["nominal_tasks"])
    groups=sort(unique(group.(rows)))
    summaries=[merge(Dict("engine"=>e,"profile"=>p,"threads"=>t,"budget"=>b,"nominal_tasks"=>n),
        statistics(filter(r->group(r)==(e,p,t,b,n),rows))) for (e,p,t,b,n) in groups]
    data=Dict("schema"=>"lilim-progress/1","reported_utc"=>string(now(UTC)),"campaign"=>campaign,
        "campaign_revision"=>started["revision"],"report_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "completed"=>length(rows),"total"=>total,"pending_status"=>pending,"summary"=>summaries,"archived_attempts"=>attempts,
        "rows"=>[filter(p->!(first(p) in ("events","eligible_events","final_routes")),r) for r in rows],
        "source_files"=>sources,"target_origin"=>"best observed eligible quality in this report, post-hoc, not proven optimal")
    open(io->TOML.print(io,data;sorted=true),joinpath(out,"report.toml"),"w")
    open(joinpath(out,"report.md"),"w") do io
        adaptive=get(started,"schema","")=="lilim-adaptive/1"
        println(io,"# Li–Lim : comparaison provisoire\n\nÉtat au ",data["reported_utc"]," UTC. **",length(rows)," exécutions terminées**. Grille de base 30–240 s : ",total," exécutions.")
        if adaptive
            println(io,"\nCette grille peut s'arrêter à 120 s uniquement si toutes les observations de cet échelon sont réalisables. Sinon, 240 s est obligatoire, puis doublement pour les instances encore sans aucune solution. Le nombre final d'exécutions n'est donc pas fixé à l'avance.")
        end
        println(io,"\nRévision de campagne : `",started["revision"],"`. Quatre cœurs partagés au maximum ; autres HPO actifs. Hexaly exclu. Données originales, sans réduction des instances.")
        println(io,"\nSans résultat définitif au moment de la lecture : ",isempty(pending) ? "aucun" : join(pending,", "),". Ce constat ne prouve pas que le processus est actif.")
        if !isempty(attempts)
            println(io,"\n## Tentatives antérieures conservées\n\n",length(attempts)," tentative(s) archivée(s) avant reprise, en plus des observations du tableau. Ces incidents ne sont pas effacés par une réussite ultérieure et ne constituent pas des défaites de qualité du solveur.\n")
            for a in attempts
                println(io,"- `",a["run"],"` : ",a["reason"]," ; archive `",a["directory"],"`.")
            end
        end
        println(io,"\n## Faisabilité et temps de découverte\n\nLes médianes portent uniquement sur les succès dans le budget : elles ne constituent pas un classement. Les groupes n'ont pas encore nécessairement testé les mêmes instances/répétitions ; comparer les lignes détaillées avant de conclure. Le temps total inclut la construction mesurée par l'adaptateur, mais pas le démarrage du processus ni les échauffements.")
        println(io,"\n| Solveur / profil | Threads | Budget (s) | Taille nominale | Terminés | Réalisables | Sans solution | Hors budget seuls | Erreurs | Censurés | Médiane 1re solution (s) | Avec construction (s) |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for s in summaries
            fields=[s["engine"]*" / "*s["profile"],s["threads"],s["budget"],s["nominal_tasks"],s["completed"],s["feasible"],s["no_feasible"],s["late_only"],s["errors"],s["censored"],s["median_first_seconds"],s["median_first_end_to_end_seconds"]]
            println(io,"| ",join(fmt.(fields)," | ")," |")
        end
        println(io,"\n## Observations détaillées\n\nObjectif lexicographique : véhicules puis distance euclidienne non arrondie. La cible commune est la meilleure qualité observée dans ce rapport pour l'instance, tous budgets confondus, sans garantie d'optimalité ; elle peut changer au rapport suivant. « — » signifie indisponible/non atteint, jamais zéro. Les erreurs et censures de ressources ne sont pas des défaites de qualité.")
        details=sort(rows;by=r->get(r,"completed_utc",""),rev=true)
        if length(details)>200
            println(io,"\nLes 200 observations les plus récentes sont affichées ci-dessous ; le fichier report.toml contient toutes les observations de ce rapport.")
            details=details[1:200]
        end
        println(io,"\n| Instance | Visites | Solveur / profil | Threads | Budget | Répétition | État | Véhicules | Distance | 1re solution (s) | Cible commune (s) |\n|---|---:|---|---:|---:|---:|---|---:|---:|---:|---:|")
        for r in details
            es=r["eligible_events"]
            fields=[r["instance"],get(r,"actual_customers","—"),r["engine"]*" / "*r["profile"],get(r,"threads","unreported"),r["budget"],r["seed"],r["state"],
                isempty(es) ? "—" : last(es)["vehicles"],isempty(es) ? "—" : last(es)["distance"],
                isempty(es) ? "—" : first(es)["solve_seconds"],get(r,"time_to_target_seconds","—")]
            println(io,"| ",join(fmt.(fields)," | ")," |")
        end
        availability=joinpath(campaign,"availability.toml")
        if isfile(availability)
            println(io,"\n## Configurations indisponibles\n")
            for c in TOML.parsefile(availability)["unavailable"]
                println(io,"- ",c["engine"]," / ",c["profile"]," / ",c["threads"]," threads : ",c["reason"],".")
            end
        end
        println(io,"\nCe diagnostic ne qualifie pas les formulations comme optimales pour chaque solveur. Les profils « like » sont des analogues partiels. Les interfaces JuMP absentes sont indiquées dans ANYTIME.md. Le fichier TOML conserve les observations et empreintes des sources pour reproduire cet état.")
    end
    cp(@__FILE__,joinpath(out,"report-source.jl"))
    println(joinpath(out,"report.md"))
    out
end

function selftest()
    e(t,v,d)=Dict("solve_seconds"=>t,"elapsed_seconds"=>t+1,"vehicles"=>v,"distance"=>d)
    rows=[Dict{String,Any}("instance"=>"x","state"=>"feasible_incumbent","eligible_events"=>[e(2.,2,10.)]),
          Dict{String,Any}("instance"=>"x","state"=>"feasible_only_after_budget","eligible_events"=>[]),
          Dict{String,Any}("instance"=>"x","state"=>"resource_censored","eligible_events"=>[])]
    s=statistics(rows)
    @assert s["feasible"]==1 && s["late_only"]==1 && s["censored"]==1 && s["median_first_seconds"]==2.
    targets!(rows)
    @assert rows[1]["time_to_target_seconds"]==2. && !rows[2]["target_reached"] && !rows[3]["target_reached"]
    @assert statistics(rows[2:3])["median_first_seconds"]=="unavailable"
    mktempdir() do tmp
        dir=joinpath(tmp,"runs","finished");mkpath(dir)
        mkpath(joinpath(tmp,"runs","still-writing"))
        eligible=merge(e(2.,2,10.),Dict("within_solve_budget"=>true))
        late=merge(e(31.,1,5.),Dict("within_solve_budget"=>false))
        for (name,value) in (("job",Dict("instance"=>"x")),
                ("validated",Dict("events"=>[eligible,late])),
                ("status",Dict("state"=>"feasible_incumbent")))
            open(io->TOML.print(io,value),joinpath(dir,name*".toml"),"w")
        end
        loaded,proof,pending=observations(tmp)
        @assert length(loaded)==1 && pending==["still-writing"] && length(proof)==3
        @assert length(only(loaded)["eligible_events"])==1
        targets!(loaded)
        @assert only(loaded)["target_vehicles"]==2
        job=Dict("instance"=>"x","engine"=>"fixture","profile"=>"default","threads"=>1,"budget"=>30,
            "seed"=>1,"nominal_tasks"=>100,"actual_customers"=>6)
        open(io->TOML.print(io,job),joinpath(dir,"job.toml"),"w")
        open(io->TOML.print(io,Dict("instances"=>1,"configurations"=>1,"budgets"=>[30],"seeds"=>[1],"revision"=>"fixture")),joinpath(tmp,"started.toml"),"w")
        prior=joinpath(tmp,"attempts","finished","prior");mkpath(prior)
        open(io->TOML.print(io,Dict("run"=>"finished","reason"=>"host free memory below 512 MiB")),joinpath(prior,"archive.toml"),"w")
        artifact=report(tmp);generated=TOML.parsefile(joinpath(artifact,"report.toml"))
        @assert length(generated["archived_attempts"])==1
        @assert generated["completed"]==1 && only(generated["summary"])["feasible"]==1
    end
    println("Progress report semantic checks passed")
end

if abspath(PROGRAM_FILE)==@__FILE__
    only(ARGS)=="--self-test" ? selftest() : report(only(ARGS))
end
