module PlatformResources

affinity_mode() = Sys.islinux() ? "hard_cpu_affinity" : "solver_thread_caps_only"

function allowed_cpus()
    Sys.islinux() || return collect(0:Sys.CPU_THREADS-1)
    row=only(filter(l->startswith(l,"Cpus_allowed_list:"),readlines("/proc/self/status")))
    cpus=Int[]
    for item in split(strip(split(row,':')[2]),',')
        bounds=parse.(Int,split(item,'-'))
        append!(cpus,length(bounds)==1 ? bounds : first(bounds):last(bounds))
    end
    sort(cpus)
end

"macOS and Windows use solver thread caps; no hard CPU affinity is claimed."
function pin(command,cpus)
    isempty(cpus) && throw(ArgumentError("empty CPU selection"))
    allunique(cpus) && all(c->c isa Integer && c>=0,cpus) || throw(ArgumentError("invalid CPU selection"))
    Sys.islinux() ? `taskset --cpu-list $(join(cpus,',')) $command` : command
end

function windows_cpu(handle; thread=false)
    creation=Ref{UInt64}(0); finish=Ref{UInt64}(0)
    kernel=Ref{UInt64}(0); user=Ref{UInt64}(0)
    result = if thread
        ccall((:GetThreadTimes,"kernel32"),Cint,(Ptr{Cvoid},Ref{UInt64},Ref{UInt64},Ref{UInt64},Ref{UInt64}),handle,creation,finish,kernel,user)
    else
        ccall((:GetProcessTimes,"kernel32"),Cint,(Ptr{Cvoid},Ref{UInt64},Ref{UInt64},Ref{UInt64},Ref{UInt64}),handle,creation,finish,kernel,user)
    end
    result!=0 || error("Windows CPU accounting failed")
    (kernel[]+user[])/1e7
end

function cpu_seconds(id=2)
    id in (2,3) || throw(ArgumentError("expected process or thread CPU clock"))
    if Sys.iswindows()
        handle = id==3 ? ccall((:GetCurrentThread,"kernel32"),Ptr{Cvoid},()) :
            ccall((:GetCurrentProcess,"kernel32"),Ptr{Cvoid},())
        return windows_cpu(handle;thread=id==3)
    end
    native_id=Sys.isapple() ? (id==2 ? 12 : 16) : id
    stamp=Ref{NTuple{2,Clong}}((0,0))
    ccall(:clock_gettime,Cint,(Cint,Ref{NTuple{2,Clong}}),native_id,stamp)==0 || error("CPU clock unavailable")
    stamp[][1]+stamp[][2]/1e9
end

function os_thread_id()
    Sys.islinux() && return Int(ccall(:gettid,Cint,()))
    Sys.iswindows() && return Int(ccall((:GetCurrentThreadId,"kernel32"),UInt32,()))
    if Sys.isapple()
        value=Ref{UInt64}(0)
        ccall(:pthread_threadid_np,Cint,(Ptr{Cvoid},Ref{UInt64}),C_NULL,value)==0 || error("Thread ID unavailable")
        return Int(value[])
    end
    error("Unsupported host platform")
end

"Cumulative reaped child CPU; used as a before/after delta on macOS."
function children_cpu_seconds()
    Sys.isapple() || return 0.0
    # Darwin rusage: two timevals followed by fourteen longs. Each timeval
    # has a 64-bit seconds field and a 32-bit microseconds field plus padding.
    usage=zeros(Clong,18)
    ccall(:getrusage,Cint,(Cint,Ptr{Clong}),-1,usage)==0 || error("Child CPU accounting failed")
    usage[1]+(UInt64(usage[2]) & 0xffffffff)/1e6+
        usage[3]+(UInt64(usage[4]) & 0xffffffff)/1e6
end

function child_cpu_seconds(pid)
    Sys.isapple() && return nothing # Read the exact reaped-child delta after wait.
    if Sys.iswindows()
        handle=ccall((:OpenProcess,"kernel32"),Ptr{Cvoid},(UInt32,Cint,UInt32),0x1000,0,pid)
        handle==C_NULL && return nothing
        try
            return windows_cpu(handle)
        finally
            ccall((:CloseHandle,"kernel32"),Cint,(Ptr{Cvoid},),handle)
        end
    end
    path="/proc/$pid/stat"
    isfile(path) || return nothing
    contents=try read(path,String) catch e; e isa SystemError || rethrow(); return nothing end
    closing=findlast(')',contents); closing===nothing && return nothing
    fields=split(contents[nextind(contents,closing):end]); length(fields)>=13 || return nothing
    ticks=ccall(:sysconf,Clong,(Cint,),2)
    ticks>0 || error("CPU clock ticks unavailable")
    (parse(Int,fields[12])+parse(Int,fields[13]))/ticks
end
end
