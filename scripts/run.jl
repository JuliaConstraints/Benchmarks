# The only catalogue launcher: sequential Julia subprocesses, inherited CPU affinity.
include(joinpath(@__DIR__, "..", "Solvers", "scripts", "resources.jl"))
include("activate.jl")
using TOML
include(srcdir("Evidence.jl"))
length(ARGS) == 1 || error("usage: run.jl check|packages-smoke|packages-measure|solvers-check|solvers-plan")
jobs = Dict(
    "check" => [(".", "scripts/check.jl", String[]),
        (".", "scripts/packages.jl", ["smoke"]), ("Solvers", "test/runtests.jl", String[])],
    "packages-smoke" => [(".", "scripts/packages.jl", ["smoke"])],
    "packages-measure" => [(".", "scripts/packages.jl", ["measure"])],
    "solvers-check" => [("Solvers", "test/runtests.jl", String[])],
    "solvers-plan" => [("Solvers", "scripts/plan.jl", String[])])
selection = get(jobs, only(ARGS), nothing)
selection === nothing && error("unknown command: $(only(ARGS))")
lockpath = projectdir("_research", "run.lock")
mkpath(dirname(lockpath))
try
    mkdir(lockpath)
catch
    error("run lock already exists at $lockpath; inspect the owner before removing a stale lock")
end
try
    open(io -> TOML.print(io, Dict("pid" => getpid(), "cpus" => COMPARISON_CPUS)),
        joinpath(lockpath, "owner.toml"), "w")
    attempt = Evidence.start("orchestration", Dict("command" => only(ARGS),
        "cpus" => COMPARISON_CPUS, "julia_threads" => Threads.nthreads(), "performance_claims" => false))
    try
        for (i, (environment, script, args)) in enumerate(selection)
            project = projectdir(environment)
            entrypoint = joinpath(project, script)
            println("Running ", script, " (", environment, ")")
            # No shell, Python launcher, detached process or parallel task.
            command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=$(Threads.nthreads()) --gcthreads=1 --project=$project $entrypoint $args`
            open(joinpath(attempt, "step-$i.log"), "w") do io
                run(pipeline(command; stdout=io, stderr=io))
            end
        end
        Evidence.complete(attempt, Dict("state" => "completed", "steps" => length(selection)))
        println("Evidence: ", attempt)
    catch err
        Evidence.fail(attempt, err)
        println(stderr, "Failed run evidence: ", attempt)
        rethrow()
    end
finally
    rm(joinpath(lockpath, "owner.toml"); force=true)
    rm(lockpath) # Empty directory owned by this invocation; no recursive cleanup.
end
