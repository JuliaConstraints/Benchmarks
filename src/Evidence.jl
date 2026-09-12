module Evidence
using Dates, SHA, TOML, UUIDs
import DrWatson

digest(path) = bytes2hex(sha256(read(path)))
function provenance(root)
    hashes = Dict{String,String}()
    for folder in ("src", "scripts", "config")
        for (dir, _, files) in walkdir(joinpath(root, folder)), file in files
            endswith(file, ".jl") || endswith(file, ".toml") || continue
            path = joinpath(dir, file)
            hashes[replace(relpath(path, root), '\\' => '/')] = digest(path)
        end
    end
    hashes["Solvers/scripts/resources.jl"] = digest(joinpath(root, "Solvers", "scripts", "resources.jl"))
    record = Dict{String,Any}("julia_version" => string(VERSION),
        "cpu_name" => Sys.CPU_NAME, "machine" => Sys.MACHINE, "kernel" => string(Sys.KERNEL),
        "drwatson_version" => string(pkgversion(DrWatson)), "project_name" => DrWatson.projectname(),
        "project_sha256" => digest(joinpath(root, "Project.toml")),
        "manifest_sha256" => digest(joinpath(root, "Manifest.toml")), "source_sha256" => hashes)
    DrWatson.tag!(record; gitpath=root, storepatch=false)
    return record
end

function atomic_toml(path, content)
    ispath(path) && error("refusing to replace evidence: $path")
    temporary = path * ".partial"
    ispath(temporary) && error("partial evidence already exists: $temporary")
    open(io -> TOML.print(io, content; sorted=true), temporary, "w")
    mv(temporary, path)
end

function start(kind, metadata)
    root = DrWatson.projectdir()
    record = provenance(root)
    merge!(record, metadata)
    record["started_utc"] = string(now(UTC))
    record["pid"] = getpid()
    record["kind"] = kind
    parent = DrWatson.datadir("sims", kind)
    mkpath(parent)
    path = joinpath(parent, string(uuid4()))
    mkdir(path)
    # Preserve uncommitted inputs as well as their digests; a dirty Git tag alone
    # does not allow another researcher to reconstruct this invocation.
    for relative in vcat(collect(keys(record["source_sha256"])), ["Project.toml", "Manifest.toml"])
        target = joinpath(path, "snapshot", split(relative, '/')...)
        mkpath(dirname(target))
        cp(joinpath(root, split(relative, '/')...), target)
        expected = relative == "Project.toml" ? record["project_sha256"] :
            relative == "Manifest.toml" ? record["manifest_sha256"] : record["source_sha256"][relative]
        digest(target) == expected || error("input changed during snapshot: $relative")
    end
    atomic_toml(joinpath(path, "started.toml"), record)
    return path
end

function complete(path, payload)
    atomic_toml(joinpath(path, "result.toml"), payload)
    atomic_toml(joinpath(path, "completed.toml"), Dict("state" => "completed",
        "finished_utc" => string(now(UTC)), "result_sha256" => digest(joinpath(path, "result.toml"))))
end

function fail(path, err)
    atomic_toml(joinpath(path, "failed.toml"), Dict("state" => "failed",
        "finished_utc" => string(now(UTC)), "error" => sprint(showerror, err)))
end
end
