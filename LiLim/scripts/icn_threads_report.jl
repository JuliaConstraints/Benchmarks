using TOML, SHA, Statistics, Printf
using ConstraintModels
using ConstraintModels.Benchmarks
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
include(joinpath(ROOT,"LiLim","src","Pilot.jl"))
include(joinpath(ROOT,"LiLim","src","MetaRepair.jl"))
include(joinpath(ROOT,"LiLim","src","ICNScoring.jl"))
include(joinpath(ROOT,"LiLim","src","Hybrid.jl"))
include(joinpath(ROOT,"LiLim","src","ResourceExperiment.jl"))
digest(path)=bytes2hex(sha256(read(path)))
quality(r)=(r["vehicles"],r["distance"])
lexmedian(rs)=sort(rs;by=quality)[cld(length(rs),2)]
function comparison(a,b)
    a["vehicles"] != b["vehicles"] && return a["vehicles"]<b["vehicles"] ? -1 : 1
    abs(a["distance"]-b["distance"]) <= 1e-6 && return 0
    a["distance"]<b["distance"] ? -1 : 1
end
length(ARGS)==2 || error("usage: icn_threads_report.jl campaign-directory output-prefix")
campaign,prefix=abspath.(ARGS)
isfile(joinpath(campaign,"completed.toml")) || error("campaign incomplete")
meta=TOML.parsefile(joinpath(campaign,"started.toml"));config=meta["config"]
instances=Dict{String,Any}()
for id in config["instances"]
    path=joinpath(ROOT,"LiLim","data","raw","pdp_100",id*".txt")
    digest(path)==config["source_sha256"][id] || error("original instance changed: $id")
    instances[id]=read_benchmark(path,:li_lim;id)
end
for (relative,hash) in meta["source_sha256"]
    digest(joinpath(campaign,"snapshot",relative))==hash || error("source snapshot corrupted: $relative")
end
for (file,key) in (("Project.toml","project_sha256"),("Manifest.toml","manifest_sha256"))
    digest(joinpath(campaign,"snapshot",file))==meta["baseline_environment"]["environment"][key] || error("environment snapshot corrupted")
end
resumptions=Dict{String,Any}()
resumption_dir=joinpath(campaign,"resumptions")
if isdir(resumption_dir)
    for segment in readdir(resumption_dir;join=true)
        info=TOML.parsefile(joinpath(segment,"started.toml"))
        info["config"]==config && info["baseline_environment"]==meta["baseline_environment"] || error("resumption protocol mismatch")
        Set(keys(info["source_sha256"]))==Set(keys(meta["source_sha256"])) || error("resumption source inventory mismatch")
        for (relative,hash) in info["source_sha256"]
            relative=="LiLim/scripts/icn_threads.jl" && continue
            hash==meta["source_sha256"][relative] || error("solver changed during resumption")
        end
        digest(joinpath(segment,"icn_threads.jl"))==info["source_sha256"]["LiLim/scripts/icn_threads.jl"] || error("resumption controller corrupted")
        info["icn_bank_sha256"]==meta["icn_bank_sha256"] && info["clb_commit"]==meta["clb_commit"] || error("resumption bank changed")
        resumptions[basename(segment)]=info
    end
end
records=Any[];keys_seen=Set();runtimes=Any[];total_icn=0
for width in config["thread_counts"]
    dir=joinpath(campaign,string(width))
    completion=TOML.parsefile(joinpath(dir,"completed.toml"))
    segment_id=get(completion,"resumption_id","")
    evidence=isempty(segment_id) ? dir : joinpath(resumption_dir,segment_id,string(width))
    supervision=TOML.parsefile(joinpath(evidence,"supervision.toml"))
    supervision["exitcode"]==0 && supervision["reason"]=="normal_exit" || error("failed process")
    runtime=TOML.parsefile(joinpath(evidence,"runtime.toml"))
    runtime["bank_sha256"]==meta["icn_bank_sha256"]==config["icn_bank_sha256"] || error("bank mismatch")
    push!(runtimes,merge(runtime,Dict("supervision"=>supervision,"execution_segment"=>isempty(segment_id) ? "original" : segment_id,
        "original_runtime"=>TOML.parsefile(joinpath(dir,"runtime.toml")))))
    files=sort(filter(f->endswith(f,".result.toml"),readdir(dir;join=true)))
    completion["jobs"]==length(files) || error("inventory mismatch")
    for file in files
        seal=replace(file,".result.toml"=>".completed.toml")
        sealed=TOML.parsefile(seal)
        sealed["result_sha256"]==digest(file) || error("result seal corrupted")
        execution_segment=get(sealed,"resumption_id","original")
        execution_segment=="original" || haskey(resumptions,execution_segment) || error("missing resumption provenance")
        attempt_dir=execution_segment=="original" ? dir : joinpath(resumption_dir,execution_segment,string(width))
        attempt=TOML.parsefile(joinpath(attempt_dir,replace(basename(file),".result.toml"=>".started.toml")))
        r=TOML.parsefile(file);id=r["instance"];method=r["method"];seed=r["seed"]
        (attempt["instance"],attempt["method"],attempt["seed"])==(id,method,seed) || error("attempt identity mismatch")
        id in config["instances"] && seed in config["seeds"] || error("unexpected case")
        r["source_sha256"]==config["source_sha256"][id] || error("instance digest mismatch")
        width==r["threads_requested"]==r["julia_threads_available"] || error("width mismatch")
        r["budget_seconds"]==config["budget_seconds"] || error("budget mismatch")
        key=(width,id,method,seed);key in keys_seen && error("duplicate case");push!(keys_seen,key)
        p=instances[id]
        isfinite(r["process_cpu_seconds"]) && r["process_cpu_seconds"]>=0 && r["wall_seconds"]>0 || error("invalid CPU observation")
        r["mean_active_cpus"]≈r["process_cpu_seconds"]/r["wall_seconds"] || error("CPU ratio mismatch")
        checked=validate_solution(p,r["routes"])
        checked.valid && checked.objective.vehicles==r["vehicles"] && checked.objective.distance==r["distance"] || error("invalid reported solution")
        expected=ResourceExperiment.allocation(method,width)
        r["allocation"]==expected && length(r["workers"])==length(expected) || error("allocation mismatch")
        worker_records=Any[]
        for (i,w) in enumerate(r["workers"])
            w["worker"]==i && w["method"]==expected[i] && w["seed"]==seed+10000*(i-1) || error("worker identity mismatch")
            q=validate_solution(p,w["routes"])
            q.valid && q.objective.vehicles==w["vehicles"] && q.objective.distance==w["distance"] || error("invalid worker result")
            for e in w["trace"]["trajectory"]
                q=validate_solution(p,e["routes"])
                q.valid && q.objective.vehicles==e["vehicles"] && q.objective.distance==e["distance"] || error("invalid worker snapshot")
                0<=e["seconds"]<=r["budget_seconds"] || error("late worker snapshot")
            end
            if endswith(w["method"],"icn")
                w["error_backend"]["icn_decoder_calls"]>0 || error("ICN was not executed")
                w["error_backend"]["bank_sha256"]==meta["icn_bank_sha256"] || error("worker ICN mismatch")
            else
                w["error_backend"]["icn_decoder_calls"]==0 || error("unexpected ICN attribution")
            end
            global total_icn+=w["error_backend"]["icn_decoder_calls"]
            if w["method"] in ("highs_serial","highs_native")
                w["trace"]["highs_threads_option"]==(w["method"]=="highs_native" ? width : 1) || error("HiGHS cap mismatch")
                w["trace"]["invalid_callback_solutions"]==0 || error("rejected HiGHS incumbent")
            end
            repairs=get(w["trace"],"repairs",Any[])
            compact_trace=Dict(k=>v for (k,v) in w["trace"] if k!="repairs")
            compact_trace["repair_calls"]=length(repairs)
            compact_trace["repair_improvements"]=count(x->x["status"]=="improved",repairs)
            build=Float64[get(x["trace"],"build_seconds",0.) for x in repairs]
            compact_trace["median_repair_build_seconds"]=isempty(build) ? 0. : median(build)
            backend=copy(w["error_backend"])
            backend["executed_for_search"]=!(w["method"] in ("highs_serial","highs_native"))
            backend["counter_covers_score_evaluations"]=w["method"]!="cbls_direct" && backend["executed_for_search"]
            if !backend["executed_for_search"]
                backend["backend"]="none (HiGHS algebraic model)"
                backend["witness_indices"]=Int[]
                backend["bank_sha256"]=""
            end
            push!(worker_records,merge(w,Dict("trace"=>compact_trace,"error_backend"=>backend)))
        end
        if method!="highs_native"
            length(unique(w["julia_thread_id"] for w in r["workers"]))==width || error("Julia workers not distinct")
            length(unique(w["os_thread_id"] for w in r["workers"]))==width || error("OS workers not distinct")
            r["metastrategist_executed"] && !isempty(r["metastrategist_plan_key"]) || error("MetaStrategist not executed")
        end
        previous=(typemax(Int),Inf);previous_time=-Inf
        for e in r["trajectory"]
            q=validate_solution(p,e["routes"])
            q.valid && q.objective.vehicles==e["vehicles"] && q.objective.distance==e["distance"] || error("invalid portfolio snapshot")
            0<=e["seconds"]<=r["budget_seconds"] && e["seconds"]>=previous_time || error("invalid event time")
            quality(e)<=previous || error("degrading portfolio trajectory")
            previous=quality(e);previous_time=e["seconds"]
        end
        previous==quality(r) || error("final result absent from trajectory")
        native_log=haskey(sealed,"native_log_relative") ? joinpath(campaign,sealed["native_log_relative"]) : replace(file,".result.toml"=>".highs.log")
        native_info=isfile(native_log) ? filter(l->occursin("Thread count",l),readlines(native_log)) : String[]
        push!(records,merge(r,Dict("workers"=>worker_records,"raw_relative_path"=>relpath(file,campaign),
            "raw_sha256"=>digest(file),"native_highs_thread_messages"=>native_info,"execution_segment"=>execution_segment)))
    end
end
expected=Set((width,id,method,seed) for width in config["thread_counts"],id in config["instances"],seed in config["seeds"],
    method in vcat(config["methods"],width>=4 ? config["portfolio_methods"] : String[]))
keys_seen==expected || error("incomplete campaign matrix")
mkpath(dirname(prefix))
ispath(prefix*".toml") && error("output exists")
payload=Dict("schema"=>"li-lim-icn-threads-summary/1","metadata"=>meta,"runtime"=>runtimes,"resumptions"=>resumptions,
    "records"=>records,"audited_trials"=>length(records),"icn_decoder_calls"=>total_icn,
    "maximum_wall_overrun_seconds"=>maximum(r["wall_seconds"]-r["budget_seconds"] for r in records),
    "distance_tie_tolerance"=>1e-6,"report_generator_sha256"=>digest(@__FILE__))
open(io->TOML.print(io,payload;sorted=true),prefix*".toml","w")
allmethods=vcat(config["methods"],config["portfolio_methods"])
open(prefix*".md","w") do io
    println(io,"# Li-Lim : erreurs ICN, threads et portefeuilles\n")
    println(io,length(records)," essais audités, ",total_icn," appels réels aux décodeurs ICN. Trois instances exposées, trois graines, budget mural de 10 secondes par essai. Les résultats sont diagnostiques.\n")
    println(io,"Les erreurs ICN et directes qualifiées sont numériquement identiques ici. Ce test mesure leur coût et le parallélisme, sans démontrer un bénéfice d'apprentissage. Les travailleurs de recherche locale sont des trajectoires indépendantes ; les plans MetaStrategist sont statiques et réellement exécutés.\n")
    println(io,"Les profils CBLS emploient l'API native LocalSearchSolvers, son moteur de recherche ; le coût de traduction de la façade JuMP/MOI n'est pas inclus. Dans les portefeuilles mixtes, les graines restent attachées aux positions globales des voies : une famille ne reçoit pas automatiquement la graine de la première voie. Cette allocation est fixée avant la campagne, et peut être défavorable à un profil.\n")
    println(io,"Source mesurée : `",meta["benchmarks_commit"],"`. Banque ICN : `",meta["icn_bank_sha256"],"`. Dépassement mural maximal : ",round(payload["maximum_wall_overrun_seconds"];digits=4)," s ; les solutions améliorées sont toutes validées et datées dans le budget. La fusion et son audit sont chronométrés séparément.\n")
    if !isempty(resumptions)
        resumed=count(r->r["execution_segment"]!="original",records)
        println(io,"La campagne a été interrompue à la demande de l'utilisateur après ",length(records)-resumed," essais terminés. Les ",resumed," essais manquants ont été repris avec les mêmes sources de solveur, banque, instances et budgets. Les empreintes du contrôleur de reprise, les temps de préparation des deux segments et l'attribution de chaque essai sont conservés. Cette séparation temporelle doit rester présente dans l'interprétation des résultats.\n")
    end
    for id in config["instances"]
        println(io,"## ",id,"\n")
        println(io,"Médiane lexicographique parmi les trois répétitions (flotte, distance), puis médiane du nombre moyen de CPU actifs.\n")
        println(io,"| Profil | Threads | Véhicules | Distance | CPU actifs | Réinsertions/s |\n|---|---:|---:|---:|---:|---:|")
        for method in allmethods,width in config["thread_counts"]
            rs=filter(r->r["instance"]==id && r["method"]==method && r["threads_requested"]==width,records)
            isempty(rs) && continue
            q=lexmedian(rs)
            throughput=median(sum(get(w["trace"],"pair_candidates",0) for w in r["workers"])/r["budget_seconds"] for r in rs)
            @printf(io,"| %s | %d | %d | %.3f | %.2f | %.0f |\n",method,width,q["vehicles"],q["distance"],median(r["mean_active_cpus"] for r in rs),throughput)
        end
        println(io)
    end
    println(io,"## Comparaisons appariées\n")
    println(io,"Gain / égalité / recul par rapport au profil de référence, pour la même instance, largeur et graine. À flotte égale, tolérance d'égalité de distance : 1e-6. Les cellules partagent trois instances et ne sont pas des observations indépendantes.\n")
    println(io,"| Profil | Référence | Gain | Égalité | Recul |\n|---|---|---:|---:|---:|")
    for (method,reference) in (("cbls_icn","cbls_direct"),("cbls_icn","cbls_naive"),
            ("hybrid_specialized_icn","cbls_icn"),("hybrid_bridged_icn","cbls_icn"),
            ("hybrid_specialized_icn","highs_native"),("hybrid_specialized_icn","highs_portfolio"),
            ("mixed_balanced","cbls_icn"),("mixed_balanced","highs_portfolio"),
            ("mixed_ls_heavy","mixed_balanced"))
        wins=ties=losses=0
        for r in filter(r->r["method"]==method,records)
            other=only(filter(s->s["method"]==reference && s["instance"]==r["instance"] && s["threads_requested"]==r["threads_requested"] && s["seed"]==r["seed"],records))
            result=comparison(r,other)
            if result<0;wins+=1 elseif result==0;ties+=1 else losses+=1 end
        end
        println(io,"| ",method," | ",reference," | ",wins," | ",ties," | ",losses," |")
    end
    println(io,"\n## Limites et reproduction\n")
    println(io,"Les CPU 1 à 8 sont des cœurs P distincts ; la largeur 16 ajoute quatre cœurs E et quatre frères SMT. Les compteurs CPU publient l'utilisation réelle ; une limite de threads ne signifie pas que toutes les phases utilisent cette largeur. HiGHS natif et N HiGHS série sont rapportés séparément. Aucune comparaison Timefold/Hexaly, aucune adaptation MetaStrategist ni confirmation sur de nouvelles instances n'est prétendue.\n")
    println(io,"Les variantes bridgées exécutent XCSP3Bridges pour les égalités discrètes de route, avec des DAG manuels. La banque apprise/reconstruite de bridges n'est pas chargée dans ces fragments ; les ICN sont utilisées par le parent CBLS.\n")
    println(io,"La référence HiGHS conserve le modèle compact et les deux phases de la première campagne : flotte d'abord, distance après preuve d'optimalité de la flotte. Cela peut limiter l'amélioration de distance dans les petits budgets. Elle n'est pas présentée comme le meilleur modèle ou réglage HiGHS possible ; une variante d'objectif scalaire lexicographique et un effort de réglage doivent être comparés avant toute affirmation industrielle.\n")
    println(io,"Protocole : [ICN_THREADS.md](../ICN_THREADS.md). Configuration : [icn-threads.toml](../config/icn-threads.toml). Les sources mesurées et les empreintes des traces sont conservées dans le TOML associé. Chaque solution et chaque événement ont été revérifiés dans le problème original.\n")
end
println("Audited ",length(records)," trials; actual ICN calls ",total_icn,"; output ",prefix)
