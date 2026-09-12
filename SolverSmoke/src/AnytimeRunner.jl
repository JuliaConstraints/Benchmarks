module AnytimeRunner
using TOML,Dates,SHA
export command, execute, configurations, save, qualify_hash, make_snapshot
const root=abspath(@__DIR__,"..")
save(path,data)=open(io->TOML.print(io,data;sorted=true),path,"w")
const configurations=[[(engine=e,profile=p) for e in ("lss_native","cbls_jump") for p in
    ("default","assignment","juls_greedy_like","ghost_assignment_like","timefold_late_acceptance_like")];
    [(engine="timefold_native",profile=p) for p in ("default","late_acceptance_400")];
    [(engine="ghost_native_cpp",profile="default_permutation"),(engine="juls_native",profile="greedy_swap"),
        (engine="highs_control",profile="compact_mip")]]
function command(job,warm;worker_root=root)
    engine=job["engine"];input=job["input"];out=job["out"];budget=job["budget"];seed=job["seed"];profile=job["profile"]
    if engine=="timefold_native"
        runtime=TOML.parsefile(joinpath(worker_root,"runtime","runtime.toml"));java=joinpath(runtime["java_home"],"bin","java.exe")
        target=joinpath(worker_root,"native","timefold","target");classpath=join([joinpath(target,"classes"),joinpath(target,"dependency","*")],';')
        return `$java -XX:ActiveProcessorCount=4 -XX:+UseSerialGC -Xmx1g -Dorg.slf4j.simpleLogger.defaultLogLevel=warn -cp $classpath bench.AnytimeRouting $input $profile $budget $seed $out $warm`
    elseif engine=="ghost_native_cpp"
        return `$(joinpath(worker_root,"runtime","ghost-portable","ghost_anytime.exe")) $input $budget $out`
    elseif engine=="highs_control"
        return `$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1 --project=$worker_root $(joinpath(worker_root,"scripts","anytime_highs.jl")) $input $budget $seed $out $warm`
    elseif engine=="juls_native"
        julia=joinpath(homedir(),".julia","juliaup","julia-1.11.9+0.x64.w64.mingw32","bin","julia.exe")
        return `$julia --startup-file=no --compiled-modules=existing --threads=4 --gcthreads=1 --project=$(joinpath(worker_root,"juls-env")) $(joinpath(worker_root,"scripts","anytime_juls.jl")) $input $budget $seed $out $warm`
    else
        return `$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --threads=4,0 --gcthreads=1 --project=$worker_root $(joinpath(worker_root,"scripts","anytime_lss.jl")) $input $engine $profile $budget $seed $out`
    end
end
function execute(cmd,log;wall)
    start=time_ns();timedout=false;pid=0;code=-1;resource_reason="none";peak_rss=0
    open(log,"w") do io
        child=run(pipeline(cmd;stdout=io,stderr=io);wait=false);pid=getpid(child)
        handle=ccall((:OpenProcess,"kernel32"),Ptr{Cvoid},(UInt32,Cint,UInt32),0x1000,0,pid)
        handle==C_NULL && error("Cannot verify worker affinity")
        allowed,system=Ref{UInt}(0),Ref{UInt}(0)
        try
            ccall((:GetProcessAffinityMask,"kernel32"),Cint,(Ptr{Cvoid},Ref{UInt},Ref{UInt}),handle,allowed,system)!=0 || error("Worker affinity read failed")
            allowed[]==UInt(240) || error("Worker outside CPUs 4-7")
        catch
            kill(child);wait(child);rethrow()
        finally
            ccall((:CloseHandle,"kernel32"),Cint,(Ptr{Cvoid},),handle)
        end
        while process_running(child)
            if (time_ns()-start)/1e9>wall
                timedout=true;resource_reason="process wall deadline";kill(child);break
            end
            # This host also runs HPO. Memory-censored jobs are not quality losses.
            query=ccall((:OpenProcess,"kernel32"),Ptr{Cvoid},(UInt32,Cint,UInt32),0x0410,0,pid)
            if query!=C_NULL
                counters=zeros(UInt64,10) # PROCESS_MEMORY_COUNTERS_EX (80 bytes)
                counters[1]=80
                try
                    ok=ccall((:GetProcessMemoryInfo,"psapi"),Cint,(Ptr{Cvoid},Ptr{Cvoid},UInt32),query,counters,80)
                    if ok!=0
                        rss=Int(counters[3]);peak_rss=max(peak_rss,rss)
                        if rss>4*1024^3
                            resource_reason="worker RSS exceeded 4 GiB";kill(child);break
                        end
                    end
                finally
                    ccall((:CloseHandle,"kernel32"),Cint,(Ptr{Cvoid},),query)
                end
            end
            if Sys.free_memory()<512*1024^2
                resource_reason="host free memory below 512 MiB";kill(child);break
            end
            sleep(.25)
        end
        wait(child);code=child.exitcode
    end
    Dict("pid"=>pid,"exitcode"=>code,"timed_out"=>timedout,"process_wall_seconds"=>(time_ns()-start)/1e9,
        "affinity"=>"f0","cpu_ceiling"=>4,"resource_censored"=>resource_reason!="none",
        "resource_reason"=>resource_reason,"peak_observed_rss_bytes"=>peak_rss)
end
function make_snapshot(snapshot)
    mkpath(snapshot)
    for folder in ("src","scripts","native","vendor","juls-env"), (dir,subdirs,files) in walkdir(joinpath(root,folder))
        filter!(x->!(x in (".git","target")),subdirs)
        for f in files
            path=joinpath(dir,f);target=joinpath(snapshot,relpath(path,root));mkpath(dirname(target));cp(path,target)
        end
    end
    for f in ("Project.toml","Manifest.toml","instrumentation.toml","ANYTIME_QUALIFICATION.toml")
        cp(joinpath(root,f),joinpath(snapshot,f))
    end
    for f in ("Solvers/scripts/resources.jl","LiLim/src/Pilot.jl")
        target=joinpath(snapshot,"..",f);mkpath(dirname(target));cp(joinpath(root,"..",f),target)
    end
    for f in ("runtime/runtime.toml","runtime/ghost-portable/ghost_anytime.exe","runtime/ghost-portable/anytime-build.toml")
        target=joinpath(snapshot,f);mkpath(dirname(target));cp(joinpath(root,f),target)
    end
    for folder in ("classes","dependency")
        target=joinpath(snapshot,"native","timefold","target",folder);mkpath(dirname(target))
        cp(joinpath(root,"native","timefold","target",folder),target)
    end
    snapshot
end
function qualify_hash(;source_root=root)
    entries=String[]
    for folder in ("scripts","src","native","vendor","juls-env"), (dir,subdirs,files) in walkdir(joinpath(source_root,folder))
        filter!(x->!(x in ("target",".git")),subdirs)
        for f in sort(files)
            p=joinpath(dir,f);push!(entries,relpath(p,source_root)*"="*bytes2hex(sha256(read(p))))
        end
    end
    for file in ("Project.toml","Manifest.toml","instrumentation.toml")
        push!(entries,file*"="*bytes2hex(sha256(read(joinpath(source_root,file)))))
    end
    for file in ("Solvers/scripts/resources.jl","LiLim/src/Pilot.jl")
        push!(entries,file*"="*bytes2hex(sha256(read(joinpath(source_root,"..",file)))))
    end
    for file in ("runtime/ghost-portable/ghost_anytime.exe","runtime/runtime.toml","runtime/ghost-portable/anytime-build.toml")
        push!(entries,file*"="*bytes2hex(sha256(read(joinpath(source_root,file)))))
    end
    for folder in ("classes","dependency"), (dir,_,files) in walkdir(joinpath(source_root,"native","timefold","target",folder)), f in files
        p=joinpath(dir,f);push!(entries,relpath(p,source_root)*"="*bytes2hex(sha256(read(p))))
    end
    bytes2hex(sha256(join(sort(entries),"\n")))
end
end
