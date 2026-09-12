# One-time reorganization. Keep every byte and verify every destination.
include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
using SHA, TOML
root = realpath(joinpath(@__DIR__, ".."))
archive = joinpath(root, "archive", "legacy")
mkpath(archive)
function contained(path)
    relative = relpath(abspath(path), root)
    (isabspath(relative) || first(splitpath(relative)) == "..") && error("outside repository: $path")
    return path
end
inventory = Dict{String,Any}()
for name in ("ConstraintCommons", "ConstraintDomains", "ConstraintLearning", "PatternFolds")
    source = contained(joinpath(root, name))
    target = contained(joinpath(archive, name))
    isdir(source) || error("source absent (migration already performed?): $source")
    ispath(target) && error("archive already exists: $target")
    hashes = Dict{String,String}()
    for (dir, dirs, files) in walkdir(source)
        any(islink, joinpath.(dir, vcat(dirs, files))) && error("symlink in source")
        for file in files
            path = contained(joinpath(dir, file))
            hashes[replace(relpath(path, source), '\\' => '/')] = bytes2hex(sha256(read(path)))
        end
    end
    # Both absolute targets were checked above; no force and no replacement.
    mv(source, target)
    for (relative, digest) in hashes
        bytes2hex(sha256(read(joinpath(target, split(relative, '/')...)))) == digest || error("archive mismatch")
    end
    inventory[name] = hashes
end
open(joinpath(archive, "inventory.toml"), "w") do io
    TOML.print(io, Dict("schema" => "legacy-archive/1", "files" => inventory); sorted=true)
end
println("Archived and verified ", sum(length, values(inventory)), " files; no historical experiment executed.")
