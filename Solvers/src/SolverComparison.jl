"""Functional ILP pilot contracts. No solver imports, downloads or work on import."""
module SolverComparison
using TOML, SHA, UUIDs, Dates
import DrWatson
export load_campaign, load_cases, validate_primal, exact_oracle, pilot_plan, write_attempt

function load_campaign(path)
    spec = TOML.parsefile(path)
    spec["schema"] == "solver-comparison/1" || error("unknown campaign schema")
    spec["purpose"] == "functional_qualification" || error("performance campaigns are not implemented")
    spec["automatic_run"] === false || error("automatic execution is disabled")
    spec["performance_claims"] === false || error("functional results cannot claim performance")
    1 <= spec["max_cpus"] <= 2 || error("pilot permits at most two CPUs")
    spec["max_concurrent_runs"] == 1 || error("pilot runs must be sequential")
    all(n -> n in 1:spec["max_cpus"], spec["thread_profiles"]) || error("invalid thread profile")
    ids = [p["id"] for p in spec["paths"]]
    allunique(ids) || error("duplicate path identity")
    return spec
end

function load_cases(path)
    data = TOML.parsefile(path)
    data["schema"] == "bounded-ilp-fixtures/1" || error("unknown fixture schema")
    cases = data["cases"]
    allunique([p["id"] for p in cases]) || error("duplicate case identity")
    for p in cases
        n = length(p["lower"])
        n > 0 && length(p["upper"]) == length(p["cost"]) == n || error("invalid dimensions")
        all(p["lower"] .<= p["upper"]) || error("empty domain")
        length(p["matrix"]) == length(p["relations"]) == length(p["rhs"]) || error("invalid rows")
        all(row -> length(row) == n, p["matrix"]) || error("invalid row dimensions")
        all(r -> r in ("<=", ">=", "=="), p["relations"]) || error("unknown relation")
        p["sense"] in ("min", "max") || error("unknown sense")
        for values in (p["lower"], p["upper"], p["cost"], p["rhs"], [p["offset"]], p["matrix"]...)
            all(x -> x isa Integer && !(x isa Bool), values) || error("integer fixture required")
        end
    end
    return cases
end

exact_dot(a, b) = sum((BigInt(x) * BigInt(y) for (x, y) in zip(a, b)); init=BigInt(0))
objective(p, x) = exact_dot(p["cost"], x) + p["offset"]

"""Independent exact integer oracle; never rounds an invalid primal into feasibility."""
function validate_primal(p, values; reported_objective=nothing)
    values === nothing && return (; status=:no_primal, feasible=false)
    length(values) == length(p["lower"]) || return (; status=:invalid_dimension, feasible=false)
    all(x -> x isa Real && isfinite(x) && isinteger(x), values) ||
        return (; status=:invalid_integrality, feasible=false)
    x = BigInt.(values)
    all(p["lower"] .<= x .<= p["upper"]) || return (; status=:invalid_domain, feasible=false)
    for (row, rel, rhs) in zip(p["matrix"], p["relations"], p["rhs"])
        lhs = exact_dot(row, x)
        ok = rel == "<=" ? lhs <= rhs : rel == ">=" ? lhs >= rhs : lhs == rhs
        ok || return (; status=:invalid_constraint, feasible=false)
    end
    obj = objective(p, x)
    if reported_objective !== nothing && reported_objective != obj
        return (; status=:invalid_objective, feasible=true, objective=obj)
    end
    return (; status=:validated, feasible=true, objective=obj)
end

function exact_oracle(p; max_assignments=4096)
    count = prod(BigInt(hi) - lo + 1 for (lo, hi) in zip(p["lower"], p["upper"]))
    count <= max_assignments || throw(ArgumentError("oracle enumeration budget exceeded"))
    best = nothing
    incumbent = Int[]
    feasible_count = 0
    for tuple in Iterators.product((lo:hi for (lo, hi) in zip(p["lower"], p["upper"]))...)
        x = collect(tuple)
        result = validate_primal(p, x)
        result.feasible || continue
        feasible_count += 1
        obj = result.objective
        if best === nothing || (p["sense"] == "min" ? obj < best : obj > best)
            best = obj
            incumbent = x
        end
    end
    return Dict{String,Any}("status" => best === nothing ? "infeasible" : "optimal",
        "objective_exact" => best === nothing ? "none" : string(best),
        "primal" => incumbent, "assignments" => Int(count), "feasible_count" => feasible_count)
end

function pilot_plan(manifest)
    spec = load_campaign(manifest)
    fixture = normpath(joinpath(dirname(manifest), spec["cases"]))
    cases = load_cases(fixture)
    rows = [Dict("path" => path["id"], "case" => p["id"], "threads" => t,
        "implementation" => path["implementation"], "execution" => "not_run")
        for path in spec["paths"] for p in cases for t in spec["thread_profiles"]]
    return Dict("schema" => spec["schema"], "purpose" => spec["purpose"],
        "performance_claims" => false, "manifest_sha256" => bytes2hex(sha256(read(manifest))),
        "fixture_sha256" => bytes2hex(sha256(read(fixture))), "planned_runs" => rows)
end

"""New immutable attempt directory per invocation. No shared HPO state or scheduler."""
function write_attempt(root, payload)
    provenance = project_provenance()
    mkpath(root)
    dir = joinpath(root, string(uuid4()))
    mkdir(dir) # Refuse a collision; never replace a previous attempt.
    start = Dict("schema" => "solver-comparison-attempt/1", "state" => "started",
        "pid" => getpid(), "started_utc" => string(now(UTC)), "julia" => string(VERSION),
        "provenance" => provenance)
    project = normpath(joinpath(@__DIR__, ".."))
    for relative in vcat(collect(keys(provenance["source_sha256"])), ["Project.toml", "Manifest.toml"])
        target = joinpath(dir, "snapshot", split(relative, '/')...)
        mkpath(dirname(target))
        cp(joinpath(project, split(relative, '/')...), target)
        expected = relative == "Project.toml" ? provenance["project_sha256"] :
            relative == "Manifest.toml" ? provenance["manifest_sha256"] : provenance["source_sha256"][relative]
        bytes2hex(sha256(read(target))) == expected || error("input changed during snapshot: $relative")
    end
    open(io -> TOML.print(io, start; sorted=true), joinpath(dir, "started.toml"), "w")
    # Consumers only accept completed.toml. A crash leaves the partial attempt visible.
    tmp = joinpath(dir, "result.partial.toml")
    open(io -> TOML.print(io, payload; sorted=true), tmp, "w")
    mv(tmp, joinpath(dir, "result.toml"))
    completion = Dict("state" => "completed", "finished_utc" => string(now(UTC)),
        "result_sha256" => bytes2hex(sha256(read(joinpath(dir, "result.toml")))))
    marker = joinpath(dir, "completed.partial.toml")
    open(io -> TOML.print(io, completion; sorted=true), marker, "w")
    mv(marker, joinpath(dir, "completed.toml"))
    return dir
end

function project_provenance()
    project = normpath(joinpath(@__DIR__, ".."))
    samefile(DrWatson.projectdir(), project) || error("activate SolverComparisonBenchmarks before writing results")
    hashes = Dict{String,String}()
    for folder in ("src", "scripts", "test", "campaigns", "fixtures")
        for (dir, _, files) in walkdir(joinpath(project, folder)), file in files
            endswith(file, ".jl") || endswith(file, ".toml") || continue
            path = joinpath(dir, file)
            hashes[replace(relpath(path, project), '\\' => '/')] = bytes2hex(sha256(read(path)))
        end
    end
    metadata = Dict{String,Any}("project_name" => DrWatson.projectname(),
        "drwatson_version" => string(pkgversion(DrWatson)), "source_sha256" => hashes,
        "project_sha256" => bytes2hex(sha256(read(joinpath(project, "Project.toml")))))
    manifest = joinpath(project, "Manifest.toml")
    isfile(manifest) || error("a pinned Manifest.toml is required for experiment provenance")
    metadata["manifest_sha256"] = bytes2hex(sha256(read(manifest)))
    # Git tagging is observational. Untracked source files are covered by hashes above.
    DrWatson.tag!(metadata; gitpath=dirname(project), storepatch=false)
    return metadata
end
end
