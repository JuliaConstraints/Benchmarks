using TOML
include("../src/Reproduction.jl")
using .HexalyReproduction.ReproductionSelections,.HexalyReproduction.ReproductionCampaign
length(ARGS)==1 || error("Usage: report.jl CAMPAIGN_DIRECTORY")
root=normpath(joinpath(@__DIR__,"../.."));directory=abspath(only(ARGS))
identity=TOML.parsefile(joinpath(directory,"manifest.toml"))["identity"]
manifest=Dict("instances"=>identity["selection_rows"])
summarize(root,directory,manifest)
println("Revalidated sealed trials and refreshed English statistical summary.")
