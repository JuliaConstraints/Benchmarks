include(joinpath(@__DIR__,"..","Solvers","scripts","resources.jl"))
using TOML,SHA,Dates,UUIDs

function require_stopped(pid)
    h=ccall((:OpenProcess,"kernel32"),Ptr{Cvoid},(UInt32,Cint,UInt32),0x1000,0,pid)
    if h==C_NULL
        ccall((:GetLastError,"kernel32"),UInt32,())==87 || error("Cannot prove process $pid is stopped")
        return
    end
    try
        code=Ref{UInt32}(0)
        ccall((:GetExitCodeProcess,"kernel32"),Cint,(Ptr{Cvoid},Ref{UInt32}),h,code)!=0 || error("Cannot query process")
        code[]!=259 || error("Process $pid is still active; do not retry")
    finally
        ccall((:CloseHandle,"kernel32"),Cint,(Ptr{Cvoid},),h)
    end
end

function main(campaign,key)
    repo=realpath(joinpath(@__DIR__,".."));campaign=realpath(campaign)
    startswith(lowercase(campaign),lowercase(joinpath(repo,"SolverSmoke","data"))*"\\") || error("Campaign outside study data")
    basename(key)==key && !(key in (".","..")) || error("Expected a run basename")
    source=realpath(joinpath(campaign,"runs",key))
    dirname(source)==realpath(joinpath(campaign,"runs")) || error("Run outside campaign")
    isfile(joinpath(campaign,"completed.toml")) && error("Campaign already completed")
    require_stopped(TOML.parsefile(joinpath(campaign,"controller.toml"))["pid"])
    status=TOML.parsefile(joinpath(source,"status.toml"));proc=TOML.parsefile(joinpath(source,"process.toml"))
    status["state"]=="resource_censored" && proc["resource_reason"]=="host free memory below 512 MiB" || error("Only transient host-memory censoring is eligible")
    require_stopped(proc["pid"])
    free=Sys.free_memory();needed=max(2*1024^3,proc["peak_observed_rss_bytes"]+1024^3)
    free>=needed || error("Not enough memory headroom to retry")
    target=abspath(campaign,"attempts",key,string(uuid4()))
    startswith(lowercase(target),lowercase(campaign)*"\\") && !ispath(target) || error("Invalid archive target")
    lock=joinpath(repo,"_research","run.lock");mkdir(lock)
    open(io->TOML.print(io,Dict("pid"=>getpid(),"study"=>"archive-memory-censor","directory"=>campaign)),joinpath(lock,"owner.toml"),"w")
    try
        hashes=Dict(relpath(joinpath(d,f),source)=>bytes2hex(sha256(read(joinpath(d,f)))) for (d,_,fs) in walkdir(source) for f in fs)
        mkpath(dirname(target))
        target=joinpath(realpath(dirname(target)),basename(target))
        startswith(lowercase(target),lowercase(campaign)*"\\") || error("Resolved archive target outside campaign")
        mv(source,target)
        for (name,expected) in hashes
            bytes2hex(sha256(read(joinpath(target,name))))==expected || error("Archive byte mismatch")
        end
        open(joinpath(target,"archive.toml"),"w") do io
            TOML.print(io,Dict("schema"=>"archived-attempt/1","archived_utc"=>string(now(UTC)),"run"=>key,
                "original_directory"=>source,"reason"=>proc["resource_reason"],"memory_available_before_retry"=>free,
                "source_sha256"=>hashes,"policy"=>"Preserved attempt; retry keeps original solver snapshot, budget, seed and thread count");sorted=true)
        end
        println("ARCHIVED=",target)
    finally
        rm(joinpath(lock,"owner.toml"));rm(lock)
    end
end
length(ARGS)==2 || error("Expected campaign directory and run key")
main(ARGS...)
