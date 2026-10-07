using TOML
include("../src/Reproduction.jl")
using .HexalyReproduction.ReproductionSelections,.HexalyReproduction.ReproductionCampaign
function options(args)
    opts=Dict{String,String}()
    for arg in args
        startswith(arg,"--") && occursin('=',arg) || error("Use --name=value")
        k,v=split(arg[3:end],'=';limit=2)
        k in ("selection","instances","methods","budget","threads","seeds","output","resume","max-cells") || error("Unknown option $k")
        haskey(opts,k) && error("Duplicate option $k");opts[k]=v
    end
    opts
end
function main(args=ARGS)
    opts=options(args);root=normpath(joinpath(@__DIR__,"../.."))
    for k in ("instances","output");haskey(opts,k) || error("Explicit --$k is required; no campaign starts by default");end
    selected=selection(get(opts,"selection",joinpath(root,"Hexaly/config/instances.toml")))
    complete=run_campaign(root,selected;ids=split(opts["instances"],','),methods=split(get(opts,"methods","cbls_icn_fused,strategies,metastrategist,hybrid_highs,highs,ortools,ghost,hexaly"),','),
        seconds=parse(Float64,get(opts,"budget","8")),threads=parse(Int,get(opts,"threads","1")),
        seeds=parse.(Int,split(get(opts,"seeds","41,42,43"),',')),output=abspath(opts["output"]),
        resume=parse(Bool,get(opts,"resume","false")),max_cells=parse(Int,get(opts,"max-cells","250000")))
    groups=TOML.parsefile(joinpath(abspath(opts["output"]),"summary.toml"))["groups"]
    any(row->"failed" in row["statuses"],groups) && error("Model/native failures were sealed; inspect summary.toml. No failed method was replaced.")
    println(complete ? "Requested attempt set complete." : "Stopped after the current sealed trial.")
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && main()
