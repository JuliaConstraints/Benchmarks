include("activate.jl")
using Dates, TOML, SHA, UUIDs
root=projectdir()
parent=datadir("sims");mkpath(parent)
attempt=joinpath(parent,string(uuid4()));mkdir(attempt)
function save(path,record)
    ispath(path) && error("attempt exists")
    open(io->TOML.print(io,record;sorted=true),path,"w")
end
lock=normpath(joinpath(root,"..","_research","run.lock"))
mkpath(dirname(lock)); mkdir(lock)
save(joinpath(lock,"owner.toml"),Dict("pid"=>getpid(),"study"=>"Li-Lim","cpus"=>COMPARISON_CPUS))

struct ProcessMemory
    cb::UInt32
    faults::UInt32
    peakworking::UInt
    working::UInt
    peakpaged::UInt
    paged::UInt
    peaknonpaged::UInt
    nonpaged::UInt
    pagefile::UInt
    peakpagefile::UInt
    privatebytes::UInt
end
function memory_bytes(pid)
    handle=ccall((:OpenProcess,"kernel32"),Ptr{Cvoid},(UInt32,Cint,UInt32),0x410,0,pid)
    handle==C_NULL && return 0
    try
        record=Ref(ProcessMemory(UInt32(sizeof(ProcessMemory)),0,0,0,0,0,0,0,0,0,0))
        ok=ccall((:GetProcessMemoryInfo,"psapi"),Cint,(Ptr{Cvoid},Ref{ProcessMemory},UInt32),handle,record,sizeof(ProcessMemory))
        return ok==0 ? 0 : Int(record[].privatebytes)
    finally
        ccall((:CloseHandle,"kernel32"),Cint,(Ptr{Cvoid},),handle)
    end
end
try
    metadata=Dict{String,Any}("started_utc"=>string(now(UTC)),"pid"=>getpid(),"cpus"=>COMPARISON_CPUS,
        "affinity"=>string(COMPARISON_AFFINITY;base=16),"instances"=>["lc101","lr101","lrc101"],
        "seconds_per_solver"=>30.0,"wall_limit_per_child"=>180.,"memory_limit_bytes"=>3*1024^3,
        "hpo_concurrency"=>"HPO on CPUs 0-3; shared memory/cache/frequency; diagnostic only",
        "unavailable"=>["CBLS/LSS: specialized Li-Lim route adapter not qualified",
            "GHOST/JuLS/Timefold/Hexaly: Li-Lim adapters not qualified in this repository"])
    tag!(metadata;gitpath=normpath(joinpath(root,"..")),storepatch=false)
    hashes=Dict{String,String}()
    for folder in ("src","scripts","vendor"), (dir,_,files) in walkdir(joinpath(root,folder)), file in files
        path=joinpath(dir,file);relative=relpath(path,root)
        target=joinpath(attempt,"snapshot",relative);mkpath(dirname(target));cp(path,target)
        hashes[replace(relative,'\\'=>'/')]=bytes2hex(sha256(read(target)))
    end
    for file in ("Project.toml","Manifest.toml","vendor-inventory.toml")
        cp(projectdir(file),joinpath(attempt,"snapshot",file))
        hashes[file]=bytes2hex(sha256(read(projectdir(file))))
    end
    guard=normpath(joinpath(root,"..","Solvers","scripts","resources.jl"))
    cp(guard,joinpath(attempt,"snapshot","resources.jl"))
    hashes["resources.jl"]=bytes2hex(sha256(read(guard)))
    metadata["source_sha256"]=hashes
    save(joinpath(attempt,"started.toml"),metadata)
    println("Campaign: ",attempt)
    for id in metadata["instances"]
        output=joinpath(attempt,id);mkdir(output)
        command=`$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=1 --gcthreads=1 --project=$root $(scriptsdir("case.jl")) $id $output`
        open(joinpath(output,"console.log"),"w") do io
            process=run(pipeline(command;stdout=io,stderr=io);wait=false)
            pid=getpid(process);started=time();peak=0;reason="normal_exit"
            println("Started ",id," PID ",pid)
            while process_running(process)
                peak=max(peak,memory_bytes(pid))
                if peak>metadata["memory_limit_bytes"] || time()-started>metadata["wall_limit_per_child"]
                    reason=peak>metadata["memory_limit_bytes"] ? "memory_limit" : "wall_limit"
                    kill(process);break
                end
                sleep(0.5)
            end
            wait(process)
            save(joinpath(output,"supervision.toml"),Dict("pid"=>pid,"exitcode"=>process.exitcode,
                "reason"=>reason,"peak_private_bytes"=>peak,"wall_seconds"=>time()-started))
            println("Finished ",id,": ",reason,"; exit ",process.exitcode,"; peak MiB ",round(peak/1024^2;digits=1))
        end
    end
    save(joinpath(attempt,"finished.toml"),Dict("finished_utc"=>string(now(UTC))))
finally
    rm(joinpath(lock,"owner.toml");force=true);rm(lock)
end
println("Campaign finished: ",attempt)
