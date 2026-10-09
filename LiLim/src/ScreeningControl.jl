"Resource admission and durable stop boundaries for the six-size screening."
module ScreeningControl
using TOML, SHA, Dates, Random

const SIZES = (100, 200, 400, 600, 800, 1000)

function atomic(path, value)
    mkpath(dirname(path))
    temporary = path * ".partial-" * string(getpid())
    open(temporary, "w") do io
        TOML.print(io, value; sorted=true)
        flush(io)
    end
    mv(temporary, path; force=true)
end

function sample_instances(bks, seed)
    rng = Xoshiro(seed)
    [let size=string(n), ids=sort!(collect(keys(bks["instances"][string(n)])))
        id = rand(rng, ids)
        Dict{String,Any}("size"=>n, "id"=>id,
            "source_sha256"=>bks["instance_sha256"][size*"."*id],
            "target"=>bks["instances"][size][id])
    end for n in SIZES]
end

function halt_reason(directory)
    isempty(directory) && return ""
    isfile(joinpath(directory,"STOP_AFTER_TRIAL")) && return "human_stop"
    isfile(joinpath(directory,"PROCESS_FAILURE.toml")) && return "process_failure"
    any(f->startswith(f,"GC_ALERT_") && endswith(f,".toml"), readdir(directory)) && return "gc_review"
    ""
end

function admission(state, slot; now=time())
    now - get(state,"updated_epoch",0.0) <= 90 || return false
    get(state,"reason","") in ("running","resource_wait") || return false
    slot in get(state,"allowed_slots",Int[])
end

"No measured clock runs while admission is pending; human and GC stops never auto-resume."
function await_permission(directory, slot; interval=30.0)
    isempty(directory) && return Dict{String,Any}()
    while true
        isempty(halt_reason(directory)) || return nothing
        path=joinpath(directory,"state.toml")
        if isfile(path)
            state=TOML.parsefile(path)
            admission(state,slot) && return state
        end
        sleep(interval)
    end
end

function gc_alert(record, threshold)
    fraction=get(record,"search_gc_fraction",record["search_gc_seconds"]/record["wall_seconds"])
    # A very high allocation rate also merits review even when enough memory
    # postpones collection. Compare bytes/s within a trial, never across sizes.
    rate=get(record,"search_allocated_bytes",0)/record["wall_seconds"]
    fraction >= threshold || rate >= 2.0^30
end

function flag_gc(directory, slot, path, record, threshold)
    isempty(directory) && return
    gc_alert(record,threshold) || return
    atomic(joinpath(directory,"GC_ALERT_$(slot).toml"),Dict(
        "method"=>record["method"],"instance"=>record["instance"],"trial"=>path,
        "recorded_utc"=>string(now(UTC)),"gc_fraction"=>record["search_gc_fraction"],
        "allocated_bytes"=>record["search_allocated_bytes"],"threshold"=>threshold,
        "action"=>"Finish current trials, stop admission, diagnose with PerfChecker; preserve evidence and rerun all six instances after correction."))
end

function cpu_counters()
    total=0; busy=0
    lines=readlines("/proc/stat")
    values=parse.(Int,split(first(lines))[2:end])
    # guest/guest_nice are already included in user/nice.
    total=sum(values[1:8]);busy=total-values[4]-values[5]
    (; total,busy,cpu_count=count(l->occursin(r"^cpu\d+ ",l),lines))
end

function process_counters(pid)
    try
        text=read("/proc/$pid/stat",String)
        fields=split(text[findlast(')',text)+2:end])
        (;ticks=parse(Int,fields[12])+parse(Int,fields[13]),start=fields[20])
    catch e
        e isa IOError || e isa SystemError || rethrow()
        nothing
    end
end

function available_memory()
    line=only(filter(l->startswith(l,"MemAvailable:"),readlines("/proc/meminfo")))
    parse(Int,split(line)[2])*1024
end

function resource_capacity(external_cpus, memory_bytes; cpu_pressure=0.0)
    external_cpus >= 5.0 || memory_bytes < 8*2.0^30 || cpu_pressure >= 25.0 ? 0 :
        external_cpus >= 2.5 || memory_bytes < 12*2.0^30 || cpu_pressure >= 10.0 ? 1 : 2
end

function cpu_pressure()
    isfile("/proc/pressure/cpu") || return 0.0
    line=first(readlines("/proc/pressure/cpu"))
    parse(Float64,split(split(line)[2],'=')[2])
end

function resource_snapshot(previous, owned, previous_processes; interval)
    current=cpu_counters()
    seconds_per_tick=interval/max(1,current.total-previous.total)*current.cpu_count
    counters=Dict{Int,Any}()
    owned_cpu=0.0
    for pid in owned
        counter=process_counters(pid)
        counter===nothing && continue
        counters[pid]=counter
        old=get(previous_processes,pid,nothing)
        old===nothing || old.start!=counter.start ||
            (owned_cpu+=max(0,counter.ticks-old.ticks)*seconds_per_tick/interval)
    end
    busy=max(0,current.busy-previous.busy)*seconds_per_tick/interval
    external=max(0.0,busy-owned_cpu)
    memory=available_memory();pressure=cpu_pressure()
    state=Dict{String,Any}("external_active_cpus"=>external,"total_active_cpus"=>busy,
        "owned_active_cpus"=>owned_cpu,"available_memory_bytes"=>memory,
        "cpu_pressure_percent"=>pressure,
        "capacity"=>resource_capacity(external,memory;cpu_pressure=external>=2.5 ? pressure : 0.0))
    (;current,counters,state)
end

function controller(directory, jobs, launch; interval=30.0)
    Sys.islinux() || error("Adaptive screening currently requires Linux resource counters")
    lock=joinpath(directory,"controller.lock")
    try
        mkdir(lock)
    catch
        error("Controller lock exists; inspect its owner before an explicit recovery: $lock")
    end
    atomic(joinpath(lock,"owner.toml"),Dict("pid"=>getpid(),"started_utc"=>string(now(UTC))))
    running=Dict{Int,Any}();logs=IO[]
    previous=cpu_counters();counters=Dict{Int,Any}();last_sample=time()
    last_capacity=-1;last_reason="";normal_exit=false
    try
        atomic(joinpath(directory,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>Int[],"reason"=>"resource_wait"))
        for job in jobs
            logpath=joinpath(directory,"slot-$(job.slot).log")
            log=open(logpath,"a");push!(logs,log)
            running[job.slot]=run(pipeline(launch(job),stdout=log,stderr=log);wait=false)
        end
        while true
            sleep(min(interval,2.0))
            reason=halt_reason(directory)
            finished=[slot for (slot,process) in running if !process_running(process)]
            for slot in finished
                process=running[slot];wait(process)
                if !success(process)
                    atomic(joinpath(directory,"PROCESS_FAILURE.toml"),Dict(
                        "slot"=>slot,"exitcode"=>process.exitcode,"log"=>joinpath(directory,"slot-$(slot).log"),
                        "recorded_utc"=>string(now(UTC))))
                    reason="process_failure"
                end
            end
            if all(!process_running(process) for process in values(running))
                complete=all(job->isfile(joinpath(job.output,"manifest.toml")) &&
                    get(TOML.parsefile(joinpath(job.output,"manifest.toml")),"complete",false),jobs)
                reason=isempty(reason) ? (complete ? "complete" : "incomplete") : reason
                atomic(joinpath(directory,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>Int[],"reason"=>reason))
                println("Screening controller: ",reason);flush(stdout)
                normal_exit=true
                return reason
            end
            if !isempty(reason)
                atomic(joinpath(directory,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>Int[],"reason"=>reason))
                if reason!=last_reason;println("Admission stopped: ",reason,"; joining current trials.");flush(stdout);end
                last_reason=reason
                continue
            end
            time()-last_sample >= interval || continue
            sample=resource_snapshot(previous,[getpid();[getpid(p) for p in values(running) if process_running(p)]],counters;
                interval=time()-last_sample)
            previous=sample.current;counters=sample.counters;last_sample=time()
            capacity=sample.state["capacity"]
            live=sort!([slot for (slot,p) in running if process_running(p)])
            # Fixed slots keep each configuration on an immutable CPU mask.
            # When only one remains alive, it can use the single available slot.
            admitted=live[1:min(capacity,length(live))]
            reason=length(admitted)==2 ? "running" : "resource_wait"
            merge!(sample.state,Dict("updated_epoch"=>time(),"recorded_utc"=>string(now(UTC)),
                "allowed_slots"=>admitted,"reason"=>reason,"controller_pid"=>getpid(),
                "worker_pids"=>[getpid(p) for p in values(running) if process_running(p)]))
            atomic(joinpath(directory,"state.toml"),sample.state)
            if capacity!=last_capacity || reason!=last_reason
                println("Resource admission: ",length(admitted)," four-core configurations; external CPU ",
                    round(sample.state["external_active_cpus"];digits=2),"; free RAM ",
                    round(sample.state["available_memory_bytes"]/2.0^30;digits=1)," GiB")
                flush(stdout)
            end
            last_capacity=capacity;last_reason=reason
        end
    finally
        # A controller exception cannot leave its workers admitting fresh work.
        if !normal_exit
            atomic(joinpath(directory,"PROCESS_FAILURE.toml"),Dict("controller_pid"=>getpid(),
                "recorded_utc"=>string(now(UTC)),"reason"=>"Unexpected controller termination; inspect logs before recovery."))
            atomic(joinpath(directory,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>Int[],"reason"=>"controller_stopped"))
        end
        for log in logs;close(log);end
        rm(lock;recursive=true)
    end
end

end
