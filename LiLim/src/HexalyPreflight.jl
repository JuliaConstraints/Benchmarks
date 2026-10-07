"Catalogue-wide readiness checks; a solver import is not a model qualification."
module HexalyPreflight
using TOML, SHA, Dates

digest(path) = bytes2hex(sha256(read(path)))

function catalogue(path)
    c = TOML.parsefile(path)
    rows = c["benchmarks"]
    c["schema"] == "hexaly-benchmark-coverage/1" || error("Unknown benchmark catalogue schema")
    length(rows) == c["entry_count"] || error("Benchmark catalogue count differs")
    allunique(getindex.(rows,"id")) && allunique(getindex.(rows,"published_benchmark_url")) ||
        error("Duplicate benchmark catalogue entry")
    all(row->startswith(row["published_benchmark_url"],"https://www.hexaly.com/benchmarks/"),rows) ||
        error("Benchmark catalogue contains an unexpected source")
    c
end

function asset(root, cohort, relative)
    isempty(relative) && return Dict("status"=>"missing", "path"=>"")
    base = root
    if startswith(relative,"cohort:")
        base = cohort
        relative = relative[8:end]
    end
    path = abspath(joinpath(base,relative))
    startswith(relpath(path,base),"..") && error("Asset leaves the handoff directory")
    isfile(path) ? Dict("status"=>"present","path"=>path,"sha256"=>digest(path)) :
        Dict("status"=>"missing","path"=>path)
end

"Verify all original instance and archive bytes, rather than a directory's existence."
function pdptw_data(root, manifest)
    isfile(manifest) || return Dict{String,Any}("status"=>"missing", "verified_instances"=>0,
        "verified_archives"=>0,"issues"=>["original_data_manifest_missing"])
    bks = TOML.parsefile(manifest)
    issues = String[]; instances = 0; archives = 0
    for (filename,expected) in bks["archive_sha256"]
        path = joinpath(root,"LiLim/data/raw/sintef-archives",filename)
        if !isfile(path); push!(issues,"archive_missing:"*filename)
        elseif digest(path)!=expected; push!(issues,"archive_hash_mismatch:"*filename)
        else; archives += 1
        end
    end
    for (size,group) in bks["instances"], id in keys(group)
        key = size*"."*id
        path = joinpath(root,"LiLim/data/raw/pdp_"*size,id*".txt")
        if !isfile(path); push!(issues,"instance_missing:"*key)
        elseif digest(path)!=bks["instance_sha256"][key]; push!(issues,"instance_hash_mismatch:"*key)
        else; instances += 1
        end
        target = group[id]
        (get(target,"vehicles",0)>0 && isfinite(get(target,"distance",NaN)) && target["distance"]>=0) ||
            push!(issues,"invalid_reference:"*key)
    end
    length(bks["instance_sha256"])==354 && sum(length,values(bks["instances"]))==354 ||
        push!(issues,"original_instance_count_mismatch")
    length(bks["archive_sha256"])==6 || push!(issues,"original_archive_count_mismatch")
    Dict{String,Any}("status"=>isempty(issues) ? "verified" : "blocked",
        "verified_instances"=>instances,"verified_archives"=>archives,"issues"=>sort!(issues),
        "manifest_sha256"=>digest(manifest))
end

function coverage(root,cohort,c; solvers,qualification,environment_ok)
    rows = Dict{String,Any}[]
    for entry in c["benchmarks"]
        if startswith(get(entry,"decision_scope",""),"deferred_continuous")
            push!(rows,Dict{String,Any}("id"=>entry["id"],"family"=>entry["family"],
                "published_benchmark_url"=>entry["published_benchmark_url"],"equivalence"=>entry["equivalence"],
                "status"=>"deferred_continuous","issues"=>String[],"assets"=>Dict(),"data"=>Dict("status"=>"deferred"),"solvers"=>[]))
            continue
        end
        assets = Dict(name=>asset(root,cohort,get(entry,name,"")) for name in
            ("adapter","validator","hexaly_model","data_manifest"))
        issues = [name*"_missing" for (name,a) in assets if a["status"]!="present"]
        tests = get(entry,"qualification_tests",String[])
        isempty(tests) && push!(issues,"original_model_qualification_missing")
        for test in tests
            isfile(joinpath(root,test)) || push!(issues,"qualification_test_missing:"*test)
        end
        data = entry["id"]=="pdptw" ? pdptw_data(root,assets["data_manifest"]["path"]) :
            Dict{String,Any}("status"=>"unqualified","issues"=>["original_corpus_and_references_unqualified"])
        append!(issues,data["issues"])
        environment_ok || push!(issues,"frozen_environment_not_verified")
        comparators = Dict{String,Any}[]
        for solver in entry["published_solvers"]
            state = get(solvers,solver,Dict("status"=>"not_detected","reason"=>"probe_not_available"))
            qualified = get(qualification,entry["id"]*":"*solver,"not_run")
            push!(comparators,Dict("solver"=>solver,"installation"=>state["status"],
                "qualification"=>qualified,"reason"=>get(state,"reason","")))
            state["status"]=="available" && qualified!="passed" &&
                push!(issues,"model_not_qualified:"*solver)
        end
        get(qualification,entry["id"]*":core","not_run")=="passed" ||
            push!(issues,"core_qualification_not_passed")
        available = count(row->row["installation"]=="available",comparators)
        available>0 || push!(issues,"no_published_solver_available")
        push!(rows,Dict{String,Any}("id"=>entry["id"],"family"=>entry["family"],
            "published_benchmark_url"=>entry["published_benchmark_url"],
            "equivalence"=>entry["equivalence"],"status"=>isempty(issues) ? "ready_available_solvers" : "blocked",
            "issues"=>sort!(unique(issues)),"assets"=>assets,"data"=>data,"solvers"=>comparators))
    end
    rows
end

"Merge functional model evidence without promoting it to published-corpus qualification."
function discrete_evidence!(report, checks; core_state)
    for row in report["benchmarks"]
        row["id"] in ("pdptw","irp") && continue
        family = row["id"]=="large_cvrp" ? "cvrp" :
            row["id"]=="large_jssp" ? "jssp" :
            row["id"]=="rcpsp_records" ? "rcpsp" : row["id"]
        row["discrete_model_qualification"] = core_state
        row["published_corpus_qualification"] = "not_complete"
        for comparator in row["solvers"]
            name = comparator["solver"]
            evidence = get(checks,name,Dict{String,Any}())
            if comparator["installation"]=="available" && get(evidence,"status","")=="passed" &&
                    family in get(evidence,"qualified_families",String[])
                comparator["qualification"] = "functional_passed"
                comparator["qualification_scope"] = get(evidence,"scope","small_model_only")
                filter!(!=("model_not_qualified:"*name),row["issues"])
                pending = "published_instance_qualification_pending:"*name
                pending in row["issues"] || push!(row["issues"],pending)
            end
        end
        if core_state=="passed"
            filter!(!=("core_qualification_not_passed"),row["issues"])
            row["status"] = "prepared_models_published_corpus_pending"
        end
        sort!(unique!(row["issues"]))
    end
    report
end

function save_report(directory,report;refresh=false)
    # Repeated checks receive new directories; never overwrite another run's evidence.
    ispath(directory) && !refresh && error("Preflight output already exists; choose a new --output directory")
    mkpath(directory)
    open(io->TOML.print(io,report;sorted=true),joinpath(directory,"report.toml"),"w")
    open(joinpath(directory,"report.md"),"w") do io
        println(io,"# Hexaly benchmark preflight\n")
        println(io,"Source: [Hexaly benchmark page]($(report["source"]))\n")
        println(io,"Checked: $(report["checked_at_utc"]). Catalogue entries: $(report["entry_count"]). ",
            "Overall status: **$(report["status"])**.\n")
        println(io,"This checks host readiness and original model qualification. It starts no comparative campaign. ",
            "Unavailable optional solvers are skipped; unavailable models, data or validators are blockers.\n")
        println(io,"## Host\n\nOS: $(report["host"]["os"]), architecture: $(report["host"]["architecture"]), ",
            "Julia: $(report["host"]["julia"]), available CPU IDs: $(join(report["host"]["cpus"],", ")), ",
            "RAM: $(report["host"]["ram_gib"]) GiB.\n")
        println(io,"## Solver availability\n\n| Solver | Status | Detail |\n|---|---|---|")
        for (name,state) in sort!(collect(report["solvers"]);by=first)
            println(io,"| $name | $(state["status"]) | $(get(state,"reason",get(state,"version",""))) |")
        end
        println(io,"\n## All benchmark entries\n\n| Benchmark | Status | Checks still required |\n|---|---|---|")
        for row in report["benchmarks"]
            println(io,"| [$(row["family"])]($(row["published_benchmark_url"])) | $(row["status"]) | ",
                join(row["issues"],"; ")," |")
        end
        println(io,"\n## Preparation and qualification\n")
        for (name,state) in sort!(collect(report["checks"]);by=first)
            println(io,"- $name: $(state["status"]) ($(get(state,"reason","")))")
        end
        println(io,"\nThe machine-readable report records asset hashes, corpus checks and per-solver qualification. ",
            "A generic license probe does not qualify any unsupported benchmark family. ",
            "Hexaly 15.0 is the local target; published experiments may use different versions, models or settings.")
    end
end
end
