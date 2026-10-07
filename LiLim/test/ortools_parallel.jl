using Test, ConstraintModels, JuMP, TOML
using ConstraintModels.Benchmarks
include(joinpath(@__DIR__,"..","src","Pilot.jl"))
include(joinpath(@__DIR__,"..","competitors","Adapters.jl"))
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))

const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const RUNNER=joinpath(ROOT,"LiLim/native/ortools/pdptw.py")
const CPUS=CompetitorAdapters.PlatformResources.allowed_cpus()[1:min(2,end)]
const EVIDENCE=Dict{String,Any}()
const IDENTITY=try
    NativeSolvers.resolve_ortools(NativeSolvers.default_python(ROOT);root=ROOT)
catch e
    e isa NativeSolvers.UnavailableSolver || rethrow()
    nothing
end

"Exhaustive fleet-first reference from the original validator on four customers."
function original_optimum(p)
    best=(typemax(Int),Inf)
    for a in 2:5,b in 2:5,c in 2:5,d in 2:5
        order=[a,b,c,d];allunique(order) || continue
        for mask in 0:7
            routes=[Int[]]
            for i in 1:4
                push!(last(routes),order[i])
                i<4 && !iszero(mask & (1<<(i-1))) && push!(routes,Int[])
            end
            checked=validate_solution(p,routes)
            checked.valid || continue
            best=min(best,(checked.objective.vehicles,checked.objective.distance))
        end
    end
    best
end

@testset "OR-Tools parallel resource and original-model qualification" begin
    if IDENTITY===nothing
        for profile in ("routing_portfolio","cpsat")
            EVIDENCE[profile]=Dict("status"=>"skipped","reason"=>"OR_Tools_unavailable")
        end
        @test_skip false
    else
        data=PickupDeliveryProblem(3,1,[0. 0.;1 0;2 0;-1 0;-2 0],
            [0,1,-1,1,-1],zeros(5),fill(20.,5),zeros(5),[(2,3),(4,5)])
        p=BenchmarkInstance("parallel integer PDPTW",data);initial=[[2,3],[4,5]]
        @test validate_solution(p,initial).valid
        @test original_optimum(p)==(1,8.)
        if length(CPUS)<2
            EVIDENCE["routing_portfolio"]=Dict("status"=>"skipped","reason"=>"two_CPUs_not_allocated")
            @test_skip false
        else
            portfolio=CompetitorAdapters.ortools_portfolio(p,initial,IDENTITY;seconds=4,seed=41,cpus=CPUS)
            @test portfolio["original_validation"]
            @test (portfolio["vehicles"],portfolio["distance"])==original_optimum(p)
            workers=portfolio["workers"];native=[w["native"] for w in workers]
            @test length(native)==2
            @test allunique([n["process_id"] for n in native])
            @test [n["gls_lambda"] for n in native]==[0.1,0.2]
            @test all(n["internal_search_threads"]==1 for n in native)
            @test all(all(endswith(limit,"=1") for limit in n["native_thread_limits"]) for n in native)
            @test maximum(n["search_start_seconds"] for n in native)<
                minimum(n["search_start_seconds"]+n["solver_seconds"] for n in native)
            if Sys.islinux()
                @test [n["affinity_cpus"] for n in native]==[[cpu] for cpu in CPUS]
                @test all(n["max_sampled_native_threads"]==1 for n in native)
            end
            @test all(validate_solution(p,e["routes"]).valid && e["seconds"]<=4 for e in portfolio["trajectory"])
            EVIDENCE["routing_portfolio"]=Dict("status"=>"passed","processes"=>2,"cpus"=>CPUS,
                "gls_coefficients"=>[0.1,0.2],"overlapping_searches_verified"=>true,
                "native_threads_sampled"=>[n["max_sampled_native_threads"] for n in native],
                "affinity_enforced"=>Sys.islinux(),"scope"=>"small_original_PDPTW_model")
        end
        cpsat_cases=Any[]
        for (name,coords,ready,due,service) in (
                ("integer distances",data.coordinates,zeros(5),fill(20.,5),zeros(5)),
                ("tight windows require separate vehicles",data.coordinates,zeros(5),[10.,2,4,2,4],zeros(5)),
                ("zero travel still requires pickup precedence",zeros(5,2),zeros(5),ones(5),zeros(5)),
                ("waiting and fractional depot service",data.coordinates,[0.,5,6,5,6],fill(20.,5),[0.25,0.1,0.1,0.1,0.1]))
            @testset "$name" begin
                problem=BenchmarkInstance(name,PickupDeliveryProblem(3,1,coords,[0,1,-1,1,-1],ready,due,service,[(2,3),(4,5)]))
                @test validate_solution(problem,initial).valid
                mktempdir() do directory
                    input=joinpath(directory,"input.txt");output=joinpath(directory,"output.toml")
                    epoch=round(Int,time()*1e9)
                    open(io->CompetitorAdapters.export_common_start(io,problem,initial),input,"w")
                    command=CompetitorAdapters.ortools_command(IDENTITY["python"],RUNNER,input,output;
                        seconds=5,seed=41,trial_start_epoch_ns=epoch,cpus=CPUS,engine="cpsat",
                        workers=length(CPUS),verify_cpsat=true)
                    path=get(IDENTITY,"python_path","")
                    isempty(path) || (command=addenv(command,"PYTHONPATH"=>path,"PYTHONNOUSERSITE"=>"1"))
                    result=NativeSolvers.capture(command;timeout=20)
                    @test result.code==0 && !result.timed_out
                    isfile(output) || error("CP-SAT did not export a result: "*last(result.output,min(length(result.output),2500)))
                    native=TOML.parsefile(output)
                    @test native["solver_status"]=="solution"
                    @test occursin("Starting CP-SAT solver",result.output)
                    @test occursin(Regex("with $(length(CPUS)) workers?"),result.output)
                    @test !native["cp_local_search_enabled"] && native["generalized_cp_sat_enabled"]
                    audited=CompetitorAdapters.audit_ortools_trial(problem,initial,native;budget_seconds=5,
                        engine="cpsat",workers=length(CPUS))
                    @test audited["original_validation"]
                    @test (audited["vehicles"],audited["distance"])==original_optimum(problem)
                    @test all(validate_solution(problem,e["routes"]).valid && e["seconds"]<=5 for e in audited["trajectory"])
                    if Sys.islinux();@test native["affinity_cpus"]==CPUS;end
                    bad=deepcopy(native);bad["routes"]=[[3,2,4,5]]
                    @test_throws ErrorException CompetitorAdapters.audit_ortools_trial(problem,initial,bad;
                        budget_seconds=5,engine="cpsat",workers=length(CPUS))
                    push!(cpsat_cases,Dict("case"=>name,"native_worker_log_verified"=>true,
                        "vehicles"=>audited["vehicles"],"distance"=>audited["distance"],
                        "native_threads_sampled"=>native["max_sampled_native_threads"],
                        "original_validation"=>true))
                end
            end
        end
        EVIDENCE["cpsat"]=Dict("status"=>"passed","workers"=>length(CPUS),"cpus"=>CPUS,
            "multicore_status"=>length(CPUS)==2 ? "passed" : "skipped_one_CPU_allocated",
            "affinity_enforced"=>Sys.islinux(),"scope"=>"four_small_original_PDPTW_models",
            "cases"=>cpsat_cases,"objective"=>"conservative integer model; original distances audited")
    end
end
for evidence in values(EVIDENCE)
    evidence["native_runner_sha256"]=NativeSolvers.digest(RUNNER)
    evidence["adapter_sha256"]=NativeSolvers.digest(joinpath(ROOT,"LiLim/competitors/Adapters.jl"))
    evidence["qualification_sha256"]=NativeSolvers.digest(@__FILE__)
    IDENTITY===nothing || (evidence["ortools_version"]=IDENTITY["ortools_version"])
end
for arg in ARGS
    startswith(arg,"--output=") || error("Unknown option: $arg")
    open(io->TOML.print(io,EVIDENCE;sorted=true),arg[10:end],"w")
end
