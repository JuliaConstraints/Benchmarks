include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using Pkg, TOML
ENV["JULIA_PKG_PRECOMPILE_AUTO"]="0"
root=abspath(@__DIR__,"..")
env=joinpath(root,"juls-env");mkpath(env)
write(joinpath(env,"Project.toml"),"name = \"JuLSSmoke\"\n[deps]\nJuLS = \"490cb39b-a817-4b17-9139-c18f0e28f0c3\"\n[sources]\nJuLS = {path = \"../vendor/JuLS\"}\n[compat]\njulia = \"1.11\"\n")
Pkg.activate(env);Pkg.offline(true)
cd(env) do
    Pkg.develop(PackageSpec(path="../vendor/JuLS"))
    Pkg.instantiate(;allow_autoprecomp=false)
end
