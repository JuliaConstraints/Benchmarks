"Shared entry point for every solver and discrete benchmark family."
module BenchmarkKit
include("../Hexaly/scripts/colleague.jl")
end
if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    if isempty(ARGS) || ARGS==["--help"]
        println("Usage: julia scripts/colleague.jl preflight|prepare|qualify|lilim|run|report [--name=value]")
        println("preflight checks all kit solvers and the discrete catalogue; no comparison campaign starts.")
    else
        if first(ARGS)=="qualify"
            BenchmarkKit.LiLimKit.qualify(BenchmarkKit.options(ARGS[2:end]))
        end
        exit(BenchmarkKit.main())
    end
end
