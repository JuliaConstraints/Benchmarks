include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using Pkg, TOML, SHA
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
root = normpath(joinpath(@__DIR__, ".."))
workspace = abspath(root,"..","..")
mkpath(joinpath(root,"vendor"))
project = TOML.parsefile(joinpath(root,"..","LiLim","Project.toml"))
project["name"] = "SolverSmoke"
delete!(project,"sources")
localnames = ["GHOST_jll", "CBLS", "LocalSearchSolvers", "ConstraintDomains", "ConstraintCommons",
    "Constraints", "CompositionalNetworks", "ConstraintProgrammingExtensions", "GHOST"]
for name in [localnames; "COPInstances"]
    source = name == "GHOST_jll" ? joinpath(workspace,"GHOSTBuilder","build","local-jll-yggdrasil-gcc10") : joinpath(workspace,name*".jl")
    target = joinpath(root,"vendor",name)
    if !isfile(joinpath(target,"Project.toml"))
        mkpath(target)
        for item in ("Project.toml","Artifacts.toml","src","ext","data","LICENSE")
            ispath(joinpath(source,item)) && cp(joinpath(source,item),joinpath(target,item))
        end
    end
    project["deps"][name] = TOML.parsefile(joinpath(target,"Project.toml"))["uuid"]
end
project["sources"] = Dict(name=>Dict("path"=>"vendor/"*name) for name in [localnames;"COPInstances"])
open(io->TOML.print(io,project;sorted=true),joinpath(root,"Project.toml"),"w")
formulations=joinpath(root,"vendor","formulations")
isdir(formulations) || cp(joinpath(root,"..","LiLim","vendor","formulations"),formulations)
hashes=Dict(replace(relpath(joinpath(d,f),joinpath(root,"vendor")),'\\'=>'/')=>bytes2hex(sha256(read(joinpath(d,f))))
    for (d,_,fs) in walkdir(joinpath(root,"vendor")) for f in fs)
open(io->TOML.print(io,Dict("files"=>hashes);sorted=true),joinpath(root,"vendor-inventory.toml"),"w")
Pkg.activate(root)
Pkg.offline(true)
cd(root) do
    Pkg.develop([PackageSpec(path="vendor/"*name) for name in [localnames;"COPInstances"]])
    Pkg.instantiate(;allow_autoprecomp=false)
end
