include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using Pkg, SHA, TOML
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
root = normpath(joinpath(@__DIR__, ".."))
workspace = normpath(joinpath(root, "..", ".."))
vendor = joinpath(root, "vendor")
mkpath(vendor)
copies = [(joinpath(workspace, "COPInstances.jl", item), joinpath(vendor, "COPInstances", item))
    for item in ("Project.toml", "src", "data")]
push!(copies, (joinpath(workspace, "ConstraintModels.jl", "src", "benchmarks"), joinpath(vendor, "formulations")))
for (source, target) in copies
    ispath(target) && continue
    mkpath(dirname(target))
    cp(source, target) # Private immutable working snapshot; no writes to dependency checkouts.
end
hashes = Dict{String,String}()
for (dir, _, files) in walkdir(vendor), file in files
    path = joinpath(dir, file)
    hashes[replace(relpath(path, vendor), '\\'=>'/')] = bytes2hex(sha256(read(path)))
end
record = joinpath(root, "vendor-inventory.toml")
if isfile(record)
    TOML.parsefile(record)["files"] == hashes || error("vendor snapshot changed")
else
    open(io->TOML.print(io, Dict("files"=>hashes); sorted=true), record, "w")
end
Pkg.activate(root)
Pkg.offline(true)
cd(root) do
    if !isfile("Manifest.toml")
        Pkg.develop(PackageSpec(path="vendor/COPInstances"))
    end
    Pkg.instantiate(;allow_autoprecomp=false)
end
println("Dedicated Li-Lim environment prepared offline; shared projects untouched.")
