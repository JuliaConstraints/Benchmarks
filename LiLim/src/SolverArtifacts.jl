module SolverArtifacts
using Pkg, Pkg.Artifacts, Pkg.BinaryPlatforms, TOML, Downloads, SHA

const BINDINGS = normpath(joinpath(@__DIR__, "..", "Artifacts.toml"))
const PACKAGES = ("absl_py", "immutabledict", "numpy", "ortools", "pandas",
    "protobuf", "python_dateutil", "six", "typing_extensions", "tzdata")

# PyPI wheels are ZIP archives. Pkg's tar installer cannot unpack them.
# Keep the upstream bytes and checksums; materialize the checked tree using
# Julia's bundled 7z rather than pip or a platform-specific unzip program.
function install_wheel(name, expected; platform=Pkg.BinaryPlatforms.HostPlatform())
    metadata = artifact_meta(name,BINDINGS;platform)
    download = only(metadata["download"])
    actual = mktempdir() do directory
        wheel = joinpath(directory,"sdk.whl")
        Downloads.download(String(download["url"]),wheel)
        bytes2hex(sha256(read(wheel)))==download["sha256"] || error("SDK archive checksum mismatch: $name")
        create_artifact() do destination
            run(pipeline(`$(Pkg.PlatformEngines.exe7z()) x -y -o$destination $wheel`;stdout=devnull))
        end
    end
    actual==expected || error("SDK extracted tree checksum mismatch: $name")
    nothing
end

"Unmodified upstream wheels, extracted in Julia's immutable artifact cache."
function python_paths(; install=false, platform=Pkg.BinaryPlatforms.HostPlatform())
    isfile(BINDINGS) || return nothing
    paths = String[]
    for package in PACKAGES
        name = package * "_python312"
        hash = artifact_hash(name, BINDINGS; platform)
        hash === nothing && return nothing
        if !artifact_exists(hash)
            install || return nothing
            install_wheel(name, hash; platform)
        end
        push!(paths, artifact_path(hash))
    end
    paths
end

path_separator() = Sys.iswindows() ? ";" : ":"
python_path(paths) = join(paths, path_separator())
end
