using Test, SHA, TOML, Pkg
include(joinpath(@__DIR__,"..","src","NativeSolvers.jl"))
include(joinpath(@__DIR__,"..","src","PlatformResources.jl"))
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const PYTHON=joinpath(Sys.BINDIR,Base.julia_exename()) # Real executable, fake probes below.

@testset "Preserve existing installations; skip only availability failures" begin
    calls=Ref(0)
    installer=()->(calls[]+=1;error("installation must not be attempted"))
    identity=Dict("python"=>PYTHON,"ortools_version"=>"9.14.6206")
    resolver=(python;root)->identity
    @test NativeSolvers.install_ortools(PYTHON;root=ROOT,resolver,installer)===identity
    @test calls[]==0
    for reason in ("unsupported_version_9.15","native_import_failed","python_not_found")
        unavailable=(python;root)->throw(NativeSolvers.UnavailableSolver("ortools_native",reason))
        @test_throws NativeSolvers.UnavailableSolver NativeSolvers.install_ortools(PYTHON;root=ROOT,resolver=unavailable,installer)
        @test calls[]==0
    end
    missing_ortools=()->throw(NativeSolvers.UnavailableSolver("ortools_native","package_not_installed"))
    missing_hexaly=()->throw(NativeSolvers.UnavailableSolver("hexaly_native","license_unavailable"))
    result=NativeSolvers.resolve_requested(["cbls_icn","ortools_native","hexaly_native"];
        ortools_resolver=missing_ortools,hexaly_resolver=missing_hexaly)
    @test result.methods==["cbls_icn"]
    @test getindex.(result.skipped,"status")==["skipped","skipped"]
    @test getindex.(result.skipped,"reason")==["package_not_installed","license_unavailable"]
    @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_requested(["ortools_native"];
        missing="error",ortools_resolver=missing_ortools,hexaly_resolver=missing_hexaly)
    @test_throws ErrorException NativeSolvers.resolve_requested(["hexaly_native"];
        ortools_resolver=missing_ortools,hexaly_resolver=()->error("invalid adapter model"))
    @test_throws ArgumentError NativeSolvers.resolve_requested(String[];
        missing="silence",ortools_resolver=missing_ortools,hexaly_resolver=missing_hexaly)
end

@testset "Timefold availability and universal SDK bindings" begin
    missing = "__missing_java__"
    @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_timefold(missing;root=ROOT)
    probe=(command;timeout=15)->(;code=0,output="openjdk 17.0.1",timed_out=false)
    @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_timefold(PYTHON;root=ROOT,install=true,probe)
    sdk=TOML.parsefile(joinpath(ROOT,"LiLim/native/timefold/sdk.toml"))
    @test sdk["version"]=="2.6.0" && sdk["java_major"]==21
    @test length(sdk["jars"])==20
    for platform in (Pkg.BinaryPlatforms.Platform("x86_64","linux";libc="glibc"),
        Pkg.BinaryPlatforms.Platform("aarch64","linux";libc="glibc"),
        Pkg.BinaryPlatforms.Platform("x86_64","macos"),Pkg.BinaryPlatforms.Platform("aarch64","macos"),
        Pkg.BinaryPlatforms.Platform("x86_64","windows")), jar in sdk["jars"]
        @test Pkg.Artifacts.artifact_hash(jar["artifact"],NativeSolvers.SolverArtifacts.BINDINGS;platform)!==nothing
    end
end

@testset "Version, native library, timeout and license probes" begin
    probe(output;code=0,timed_out=false)=command->(;output,code,timed_out)
    mktemp() do native,io
        write(io,"fixture");flush(io)
        good=probe("PYTHON|3.12.3\nPRESENT\nORTOOLS|9.14.6206|$native\n")
        identity=NativeSolvers.ortools_identity(PYTHON;probe=good)
        @test identity["native_module_sha256"]==bytes2hex(sha256("fixture"))
        @test identity["python_version"]=="3.12.3"
        # Windows stdout uses CRLF. A missing package must reach the installer,
        # and a successful native path must not retain a trailing carriage return.
        windows_good=probe("PYTHON|3.12.3\r\nPRESENT\r\nORTOOLS|9.14.6206|$native\r\n")
        @test NativeSolvers.ortools_identity(PYTHON;probe=windows_good)==identity
        windows_missing=try
            NativeSolvers.ortools_identity(PYTHON;probe=probe("PYTHON|3.12.3\r\nMISSING\r\n";code=1))
        catch exception
            exception
        end
        @test windows_missing.reason=="package_not_installed"
        for p in (probe("PYTHON|3.12.3\nMISSING\n";code=1),
            probe("PRESENT\n";code=1),probe("";timed_out=true),
            probe("PYTHON|3.12.3\nORTOOLS|9.15|$native\n"))
            @test_throws NativeSolvers.UnavailableSolver NativeSolvers.ortools_identity(PYTHON;probe=p)
        end
        @test_throws ErrorException NativeSolvers.ortools_identity(PYTHON;probe=probe("unknown response"))
    end
    @test NativeSolvers.resolve_hexaly(PYTHON;probe=probe("Hexaly Optimizer 15.0\nJULIACONSTRAINTS_HEXALY_READY"))==realpath(PYTHON)
    syntax_probe=command->begin
        model=only(filter(a->endswith(a,".hxm"),collect(command)))
        source=read(model,String)
        @test occursin("x <- bool()",source) && !occursin("x = bool()",source)
        probe("Hexaly Optimizer 15.0\nJULIACONSTRAINTS_HEXALY_READY")(command)
    end
    @test NativeSolvers.resolve_hexaly(PYTHON;probe=syntax_probe)==realpath(PYTHON)
    source=read(joinpath(@__DIR__,"../native/hexaly/pdptw.hxm"),String)
    @test occursin("1000.0",source) && !occursin(r"\b1000\.(?!\d)",source)
    @test occursin("serviceStart[k] <-",source) && occursin("routeLength[k] <-",source)
    @test !occursin(r"\b(start|length)\[",source)
    for p in (probe("license unavailable";code=1),probe("";timed_out=true),
        probe("Hexaly Optimizer 14.0\nJULIACONSTRAINTS_HEXALY_READY"))
        @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_hexaly(PYTHON;probe=p)
    end
    @test_throws ErrorException NativeSolvers.resolve_hexaly(PYTHON;probe=probe("syntax error";code=1))
    @test_throws ErrorException NativeSolvers.resolve_hexaly(PYTHON;probe=probe("missing callback"))
    @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_hexaly("__missing_solver__")
end

@testset "GHOST wrapper availability is explicit" begin
    unavailable=()->throw(NativeSolvers.UnavailableSolver("ghost_icn","artifact_not_installed"))
    result=NativeSolvers.resolve_requested(["cbls_icn","ghost_icn"];
        ortools_resolver=()->nothing,hexaly_resolver=()->nothing,ghost_resolver=unavailable)
    @test result.methods==["cbls_icn"]
    @test only(result.skipped)["reason"]=="artifact_not_installed"
    @test_throws NativeSolvers.UnavailableSolver NativeSolvers.resolve_requested(["ghost_icn"];
        missing="error",ortools_resolver=()->nothing,hexaly_resolver=()->nothing,ghost_resolver=unavailable)
    @test_throws ErrorException NativeSolvers.resolve_requested(["ghost_icn"];
        ortools_resolver=()->nothing,hexaly_resolver=()->nothing,ghost_resolver=()->error("broken native model"))
end

@testset "Resource accounting and frozen artifact matrix" begin
    @test PlatformResources.cpu_seconds()>=0
    @test PlatformResources.cpu_seconds(3)>=0
    @test PlatformResources.os_thread_id()>0
    @test !isempty(PlatformResources.allowed_cpus())
    @test_throws ArgumentError PlatformResources.pin(`echo fixture`,Int[])
    bindings=NativeSolvers.SolverArtifacts.BINDINGS
    for platform in (Pkg.BinaryPlatforms.Platform("x86_64","linux";libc="glibc"),
        Pkg.BinaryPlatforms.Platform("aarch64","linux";libc="glibc"),
        Pkg.BinaryPlatforms.Platform("x86_64","macos"),Pkg.BinaryPlatforms.Platform("aarch64","macos"),
        Pkg.BinaryPlatforms.Platform("x86_64","windows")), package in NativeSolvers.SolverArtifacts.PACKAGES
        @test Pkg.Artifacts.artifact_hash(package*"_python312",bindings;platform)!==nothing
    end
    # No download or solve: if the frozen local SDK exists, prove that setup
    # returns it unchanged and never reaches the installer.
    local_python=joinpath(ROOT,"LiLim/native/ortools/.venv/bin/python")
    if isfile(local_python)
        before=NativeSolvers.resolve_ortools(local_python;root=ROOT)
        after=NativeSolvers.install_ortools(local_python;root=ROOT,installer=()->error("reinstallation"))
        @test before==after
        @test isempty(after["python_path"])
    end
end
