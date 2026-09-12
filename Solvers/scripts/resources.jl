# Apply before importing solver packages; no AUTO or implicit CPU allocation.
const COMPARISON_CPUS = parse.(Int, split(get(ENV, "SOLVER_COMPARISON_CPUS", ""), ','))
const COMPARISON_CPU_LIMIT = parse(Int, get(ENV, "SOLVER_COMPARISON_CPU_LIMIT", "2"))
1 <= COMPARISON_CPU_LIMIT <= 4 || error("CPU ceiling must be between one and four")
1 <= length(COMPARISON_CPUS) <= COMPARISON_CPU_LIMIT && allunique(COMPARISON_CPUS) ||
    error("set SOLVER_COMPARISON_CPUS to distinct CPU ids within the explicit ceiling")
all(cpu -> 0 <= cpu < 8sizeof(UInt), COMPARISON_CPUS) || error("invalid CPU id")
Threads.nthreads() <= length(COMPARISON_CPUS) || error("Julia threads exceed CPU allocation")
for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS",
        "JULIA_NUM_PRECOMPILE_TASKS", "JULIA_NUM_GC_THREADS", "JULIA_NUM_IMAGE_THREADS")
    ENV[key] = "1"
end
ENV["JULIA_NUM_THREADS"] = string(Threads.nthreads())
Sys.iswindows() || error("this pilot resource guard is currently qualified only on Windows")
const COMPARISON_AFFINITY = foldl(|, (UInt(1) << cpu for cpu in COMPARISON_CPUS))
let process = ccall((:GetCurrentProcess, "kernel32"), Ptr{Cvoid}, ())
    allowed, system = Ref{UInt}(0), Ref{UInt}(0)
    ccall((:GetProcessAffinityMask, "kernel32"), Cint,
        (Ptr{Cvoid}, Ref{UInt}, Ref{UInt}), process, allowed, system) != 0 || error("affinity read failed")
    allowed[] & COMPARISON_AFFINITY == COMPARISON_AFFINITY || error("CPU allocation outside inherited affinity")
    ccall((:SetProcessAffinityMask, "kernel32"), Cint,
        (Ptr{Cvoid}, UInt), process, COMPARISON_AFFINITY) != 0 || error("affinity restriction failed")
    ccall((:GetProcessAffinityMask, "kernel32"), Cint,
        (Ptr{Cvoid}, Ref{UInt}, Ref{UInt}), process, allowed, system) != 0 || error("affinity readback failed")
    allowed[] == COMPARISON_AFFINITY || error("affinity readback mismatch")
    ccall((:SetPriorityClass, "kernel32"), Cint, (Ptr{Cvoid}, UInt32), process, UInt32(0x4000))
end
