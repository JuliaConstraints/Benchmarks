include("activate.jl")
using Pkg
ENV["JULIA_PKG_PRECOMPILE_AUTO"]="0"
Pkg.offline(true)
cd(projectdir()) do
    Pkg.develop(PackageSpec(path="vendor/JuLS"))
    Pkg.instantiate(;allow_autoprecomp=false)
end
