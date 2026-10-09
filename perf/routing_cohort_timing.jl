# Fixed original Li-Lim work across independently frozen package/application cohorts.
# Run one cohort process at a time on the same reserved physical CPU mask.
# Original validation and complete lane/RNG observations follow every timed operation.
using TOML,SHA,Dates,Random,Statistics,LinearAlgebra
include(joinpath(@__DIR__, "routing_perfcheck.jl"))
using ConstraintModels
using ConstraintModels.Benchmarks
const TIMING_KEYS = Set(("application", "instance", "cpus", "seeds", "samples", "output", "timing-scope"))
function timing_options(args)
    parsed = Dict{String,String}()
    for arg in args
        startswith(arg, "--") && occursin('=', arg) || throw(ArgumentError("Use --name=value"))
        key, value = split(arg[3:end], '='; limit=2)
        key in TIMING_KEYS || throw(ArgumentError("Unknown timing option: $key"))
        haskey(parsed, key) && throw(ArgumentError("Duplicate timing option: $key"))
        parsed[key] = value
    end
    all(key -> haskey(parsed, key), ("application", "cpus", "output")) ||
        throw(ArgumentError("--application, --cpus and --output are required"))
    parsed
end
const TIMING_OPTIONS = timing_options(ARGS)
const root = abspath(TIMING_OPTIONS["application"])
success(Cmd(["git", "-C", root, "diff", "--quiet", "HEAD", "--", "LiLim/src"])) ||
    throw(ArgumentError("Measured application sources must be clean"))
const TIMING_OUTPUT = abspath(TIMING_OPTIONS["output"])
ispath(TIMING_OUTPUT) && throw(ArgumentError("Existing evidence is preserved; choose a new output path"))
isdir(dirname(TIMING_OUTPUT)) || throw(ArgumentError("Output parent must already exist"))
Sys.islinux() || throw(ArgumentError("This reserved-CPU timing protocol currently requires Linux"))
const TIMING_SEEDS = parse.(Int, split(get(TIMING_OPTIONS, "seeds", "41,42,43"), ','))
const TIMING_SAMPLES = parse(Int, get(TIMING_OPTIONS, "samples", "5"))
!isempty(TIMING_SEEDS) && allunique(TIMING_SEEDS) && all(>=(0), TIMING_SEEDS) ||
    throw(ArgumentError("Distinct nonnegative seeds are required"))
1 <= TIMING_SAMPLES <= 20 || throw(ArgumentError("Use 1-20 bounded samples per seed"))

for file in ("Pilot.jl","MetaRepair.jl","ICNScoring.jl","Hybrid.jl","ResourceExperiment.jl")
 include(joinpath(root,"LiLim/src",file))
end
const R=ResourceExperiment.StructuredRouting
const cpus = parse.(Int, split(TIMING_OPTIONS["cpus"], ','))
const width = length(cpus)
1 <= width <= 8 && all(cpu -> 0 <= cpu < 1024, cpus) || throw(ArgumentError("Use 1-8 valid Linux CPU IDs"))
@assert width==Threads.nthreads() && length(cpus)==width && allunique(cpus)
@assert Threads.ngcthreads()==1 "Run this protocol with --gcthreads=1"
@assert Set(ResourceExperiment.PlatformResources.allowed_cpus())==Set(cpus)
BLAS.set_num_threads(1)
thread_pins=Vector{Any}(undef,width)
Threads.@threads :static for i in 1:width
 mask=Ref(ntuple(j->j==div(cpus[i],64)+1 ? UInt64(1)<<mod(cpus[i],64) : UInt64(0),16))
 @assert ccall(:sched_setaffinity,Cint,(Cint,Csize_t,Ref{NTuple{16,UInt64}}),0,128,mask)==0
 actual=ccall(:sched_getcpu,Cint,())
 @assert actual==cpus[i]
 thread_pins[i]=Dict("lane"=>i,"thread"=>Threads.threadid(),"cpu"=>actual)
end
coordinator_mask=Ref(ntuple(j->j==div(first(cpus),64)+1 ? UInt64(1)<<mod(first(cpus),64) : UInt64(0),16))
@assert ccall(:sched_setaffinity,Cint,(Cint,Csize_t,Ref{NTuple{16,UInt64}}),0,128,coordinator_mask)==0
@assert ccall(:sched_getcpu,Cint,())==first(cpus)
const instance = abspath(get(TIMING_OPTIONS, "instance", joinpath(dirname(@__DIR__), "LiLim", "data", "raw", "pdp_100", "lr101.txt")))
const p=read_benchmark(instance,:li_lim)
const initial=Pilot.insertion(p;starts=1,seed=41)
@assert initial!==nothing && validate_solution(p,initial).valid
const banks=Dict(k=>ICNScoring.load_backend(k) for k in (:naive,:direct,:icn))
const executor=(;clone_backend=ICNScoring.clone_backend,metadata=ICNScoring.metadata,
 run=(plan,call,rows)->ResourceExperiment.MS.execute!(plan.prepared.kernel,ResourceExperiment.ExecutionContext(call,rows)))
function prepare(id,seed)
 if startswith(id,"rp_meta")
  plan=ResourceExperiment.prepare_portfolio(ResourceExperiment.allocation(id,width))
  return (;plan,id,seed)
 end
 roles=R.RoutingPanel.allocation(id,width)
 lanes=map(enumerate(roles)) do (i,r)
  k=r.backend==:icn_fused_all ? :icn : r.backend
  scorer=ICNScoring.clone_backend(banks[k],r.backend)
  R.Lane(p,initial;seed=seed+10000(i-1),guidance=r.guidance,scorer)
 end
 (;lanes,roles,id,seed,cpu=zeros(width))
end
function operation(s)
 if startswith(s.id,"rp_meta")
  return R.run_portfolio(p,initial,s.id,30.,s.seed,banks,s.plan,executor;
   max_episodes=8,episode_steps=32,episode_seconds=30.,fill_episode=false,
   cpu_clock=()->ResourceExperiment.cpu_seconds(3))
 end
 Threads.@threads :static for i in eachindex(s.lanes)
  before=ResourceExperiment.cpu_seconds(3)
  R.episode!(s.lanes[i],p,s.roles[i],typemax(UInt64);max_steps=1024)
  s.cpu[i]=ResourceExperiment.cpu_seconds(3)-before
 end
 s
end
function verify(result)
 lanes=result.lanes
 @assert all(l->validate_solution(p,l.best).valid&&validate_solution(p,l.current).valid,lanes)
 if hasproperty(result,:coordination)
  @assert result.coordination["episodes"]==8
  work=(lanes=lane_observations(lanes),coordination=Dict(k=>v for(k,v)in result.coordination
   if !(k in ("master_seconds","master_build_seconds","budget_seconds"))))
  cpu=[get(l.trace,"thread_cpu_seconds",0.) for l in lanes]
 else
  @assert all(l->l.steps==1024,lanes)
  work=(lanes=lane_observations(lanes),)
  cpu=result.cpu
 end
 (;work,cpu,fingerprint=work_fingerprint(work))
end
rows=Dict{String,Any}[]
d=Dict("schema"=>"whole-application-cohort-controlled-fixed-work/1",
 "application_commit"=>strip(read(Cmd(["git","-C",root,"rev-parse","HEAD"]),String)),
 "application_root"=>root,
 "measured_application_sources_clean"=>true,
 "source_sha256"=>bytes2hex(sha256(read(joinpath(root,"LiLim/src/StructuredRouting.jl")))),
 "project_sha256"=>bytes2hex(sha256(read(Base.active_project()))),
 "manifest_sha256"=>bytes2hex(sha256(read(joinpath(dirname(Base.active_project()),"Manifest.toml")))),
 "cpu_affinity"=>cpus,"thread_pins"=>thread_pins,"coordinator_cpu"=>first(cpus),"workers"=>width,"gc_threads"=>1,
 "blas_threads"=>BLAS.get_num_threads(),"recorded_utc"=>string(now(UTC)),
 "instance_sha256"=>bytes2hex(sha256(read(instance))),"records"=>rows,
 "scope"=>"Entire early published performance cohort/application versus final qualified cohort/application, separate processes and exact original LR101 work. Pure search starts with prepared private lane workspaces; MetaStrategist measurements cover the full bounded cooperative lifecycle, including lane construction, shared pool and native HiGHS master. Native HiGHS is single-threaded. Every timed attempt is retained. Original-model checks and semantic/RNG hashes follow measurement.",
 "timing_scope"=>get(TIMING_OPTIONS, "timing-scope", "protocol_qualification_shared_machine"),
 "heap_phase"=>"All timed states prepared before one collection per fixed seed/configuration batch; no explicit collection between measured steady operations.")
d["protocol_sha256"] = bytes2hex(sha256(read(@__FILE__)))
d["protocol"] = "fixed-work Linux pipeline timing/1"
d["comparison_limit"] = "Baseline and candidate must use the same CPU mask, source-qualified instance, seed and sample count. Per-worker work is fixed, so widths change total work and portfolio roles; this is not a strong-scaling or search-quality campaign."
d["package_sources"] = map(collect(filter(name -> Base.find_package(name)!==nothing, OWNED_PACKAGES))) do name
    source = dirname(dirname(Base.find_package(name)))
    clean = isempty(strip(read(Cmd(["git", "-C", source, "status", "--porcelain"]), String)))
    clean || throw(ArgumentError("Measured package sources must be clean: $name"))
    Dict("package"=>name, "commit"=>strip(read(Cmd(["git", "-C", source, "rev-parse", "HEAD"]), String)), "source_clean"=>true)
end
for id in ["rp_vnd_greedy","rp_alns_route_regret2","rp_aco_regret2","rp_alns_random_regret2",
 "rp_meta_adaptive_late","rp_meta_diversity_tabu","rp_meta_pool_ipx_late","rp_meta_pool_mip_tabu"],
 seed in TIMING_SEEDS
 for _ in 1:3
  state=prepare(id,seed);verify(operation(state))
 end
 states=[prepare(id,seed) for _ in 1:TIMING_SAMPLES]
 GC.gc()
 for (sample,state) in enumerate(states)
  process_cpu=ResourceExperiment.cpu_seconds(2)
  timed=@timed operation(state)
  consumed=ResourceExperiment.cpu_seconds(2)-process_cpu
  checked=verify(timed.value)
  push!(rows,Dict("method"=>id,"seed"=>seed,"sample"=>sample,
   "seconds"=>timed.time,"bytes"=>timed.bytes,"objects"=>Base.gc_alloc_count(timed.gcstats),
   "gc_seconds"=>timed.gctime,"compile_seconds"=>timed.compile_time,
   "recompile_seconds"=>timed.recompile_time,"process_cpu_seconds"=>consumed,
   "mean_active_cpus"=>consumed/timed.time,"thread_cpu_seconds"=>checked.cpu,
   "work_sha256"=>checked.fingerprint,"original_oracle"=>"passed",
   "worker_work"=>[Dict(k=>v for(k,v)in w if k!="thread_cpu_seconds") for w in checked.work.lanes],
   "coordinator"=>hasproperty(timed.value,:coordination) ? timed.value.coordination : Dict{String,Any}()))
  open(TIMING_OUTPUT,"w") do io;TOML.print(io,d;sorted=true);end
  println((id,seed,sample,seconds=timed.time,bytes=timed.bytes,objects=Base.gc_alloc_count(timed.gcstats),
   compilation=timed.compile_time,recompilation=timed.recompile_time));flush(stdout)
 end
end
d["complete"]=true;d["completed_utc"]=string(now(UTC))
d["all_warm_compilation_zero"]=all(r->r["compile_seconds"]==r["recompile_seconds"]==0,rows)
open(TIMING_OUTPUT,"w") do io;TOML.print(io,d;sorted=true);end
