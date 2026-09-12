# Compare the archived six-visit fixture with the exact running campaign adapters.
include(joinpath(@__DIR__,"..","SolverSmoke","scripts","activate.jl"))
using TOML,SHA,Dates,UUIDs,Statistics
const campaign=abspath(only(ARGS))
const snapshot=joinpath(campaign,"snapshot","Benchmarks","SolverSmoke")
include(joinpath(snapshot,"src","Anytime.jl"));using .Anytime
include(joinpath(snapshot,"src","AnytimeValidation.jl"));using .AnytimeValidation
include(joinpath(snapshot,"src","AnytimeRunner.jl"));using .AnytimeRunner
include(joinpath(snapshot,"src","RoutingSmoke.jl"))
import .AnytimeRunner: save

function main()
    repo=abspath(@__DIR__,"..")
    lock=joinpath(repo,"_research","run.lock");mkdir(lock)
    out=projectdir("data","historical-anytime-check",string(uuid4()));mkpath(out)
    save(joinpath(lock,"owner.toml"),Dict("pid"=>getpid(),"study"=>"historical-anytime-check","directory"=>out))
    println("CHECK=",out);flush(stdout)
    try
        started=TOML.parsefile(joinpath(campaign,"started.toml"))
        qualify_hash(source_root=snapshot)==started["code_sha256"] || error("Campaign snapshot changed")
        cases=TOML.parsefile(projectdir("data","anytime-inputs","cases.toml"))["cases"]
        original=only(filter(c->c["id"]=="lc101",cases))
        ENV["LILIM_SMOKE_SOURCE"]=original["raw_source"]
        p=RoutingSmoke.fixture();oracle=RoutingSmoke.oracle(p)
        history=projectdir("data","sims","ddfa1aa5-c08e-4d3e-a88d-3f358549e471","routing")
        p.provenance==TOML.parsefile(joinpath(history,"provenance.toml")) || error("Historical fixture provenance changed")
        RoutingSmoke.export_fixture(p,joinpath(out,"legacy"))
        read(joinpath(out,"legacy","instance.txt"))==read(joinpath(history,"instance.txt")) || error("Historical fixture bytes differ")
        input=joinpath(out,"instance.txt");write_input(input,p)
        warm=fixtures(joinpath(out,"warmup"));ENV["ANYTIME_WARMUP_INPUT"]=warm
        jobs=[Dict("input"=>input,"engine"=>c.engine,"profile"=>c.profile,"seed"=>seed,"budget"=>2.,
            "out"=>joinpath(out,"$(c.engine)-$(c.profile)-$seed.toml")) for c in configurations for seed in 1:3]
        save(joinpath(out,"jobs.toml"),Dict("jobs"=>jobs))
        batch=joinpath(out,"lss-batch.toml");save(batch,Dict("jobs"=>filter(j->j["engine"] in ("lss_native","cbls_jump"),jobs)))
        cmd=`$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1 --project=$snapshot $(joinpath(snapshot,"scripts","anytime_lss.jl")) $batch`
        proc=execute(cmd,joinpath(out,"lss.log");wall=600.)
        save(joinpath(out,"lss-process.toml"),proc)
        proc["exitcode"]==0 || error("LSS historical check failed")
        for job in filter(j->!(j["engine"] in ("lss_native","cbls_jump")),jobs)
            println("START ",job["engine"]," / ",job["profile"]," / ",job["seed"]);flush(stdout)
            proc=execute(command(job,warm;worker_root=snapshot),job["out"]*".log";wall=180.)
            save(job["out"]*".process.toml",proc)
            proc["exitcode"]==0 || error("Native historical check failed: $(job["out"])")
        end
        rows=Dict{String,Any}[]
        for job in jobs
            trace=check_trace(input,job["out"])
            for e in trace["events"]
                e["vehicles"]==1 && isapprox(e["distance"],oracle["distance"];atol=1e-8) || error("Historical oracle disagreement")
            end
            save(job["out"]*".validated.toml",trace)
            eligible=filter(e->e["within_solve_budget"],trace["events"])
            push!(rows,merge(job,Dict("feasible"=>!isempty(eligible),"first_seconds"=>isempty(eligible) ? "unavailable" : first(eligible)["solve_seconds"],
                "solve_seconds"=>trace["solve_call_seconds"],"raw_sha256"=>bytes2hex(sha256(read(job["out"]))))))
        end
        save(joinpath(out,"result.toml"),Dict("rows"=>rows,"oracle"=>oracle,"provenance"=>p.provenance,
            "snapshot_sha256"=>started["code_sha256"],"campaign_revision"=>started["revision"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),"completed_utc"=>string(now(UTC))))
        open(joinpath(out,"report.md"),"w") do io
            println(io,"# Contrôle sur le même extrait historique Li–Lim\n\nSix visites, trois requêtes, un véhicule. Les octets de l'ancien fichier et la provenance sont identiques. Les nouvelles formulations reçoivent ces mêmes données dans leur format multi-véhicules. Budget : deux secondes, trois répétitions, quatre cœurs. Oracle : ",oracle["distance"]," ; une seule permutation réalisable parmi 720.")
            println(io,"\nAncien pilote : CBLS, Timefold, GHOST et JuLS avaient chacun 3/3 solutions réalisables. Les colonnes ci-dessous concernent uniquement les nouvelles formulations. Les temps de découverte n'étaient pas enregistrés dans l'ancien pilote : aucune comparaison temporelle directe n'est possible.")
            println(io,"\n| Solveur / profil | Réalisables dans 2 s | Temps de première solution, répétitions 1–3 (s) |\n|---|---:|---|")
            for c in configurations
                rs=filter(r->r["engine"]==c.engine && r["profile"]==c.profile,rows)
                println(io,"| ",c.engine," / ",c.profile," | ",count(r->r["feasible"],rs),"/3 | ",join([r["first_seconds"] for r in rs],", ")," |")
            end
            println(io,"\nCe contrôle isole le changement de formulation sur un cas identique. Il ne démontre pas la performance sur lc101 complet, ni l'absence de régressions sur d'autres cas. GHOST conserve des répétitions non appariées par graine. Les observations et le code de contrôle sont archivés.")
        end
        cp(@__FILE__,joinpath(out,"check-source.jl"))
        println("HISTORICAL_CHECK_COMPLETED=",out);flush(stdout)
    finally
        owner=TOML.parsefile(joinpath(lock,"owner.toml"))
        if owner["pid"]==getpid();rm(joinpath(lock,"owner.toml"));rm(lock);end
    end
end
main()
