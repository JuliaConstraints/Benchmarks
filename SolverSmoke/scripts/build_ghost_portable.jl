include("activate.jl")
using Downloads, SHA, Pkg, TOML
root=projectdir();runtime=joinpath(root,"runtime")
url="https://github.com/skeeto/w64devkit/releases/download/v2.9.1/w64devkit-x64-2.9.1.7z.exe"
archive=joinpath(runtime,"w64devkit.7z.exe")
isfile(archive) || Downloads.download(url,archive)
bytes2hex(open(sha256,archive))=="9208c19755cd4964b7915b9afcf02c66d493a4c870c4b3e83f6c538d9c1237a5" || error("Compiler archive checksum mismatch")
compiler=joinpath(runtime,"w64devkit","bin","g++.exe")
ENV["PATH"]=dirname(compiler)*";"*ENV["PATH"]
if !isfile(compiler)
    run(`$(Pkg.PlatformEngines.exe7z()) x $archive -o$runtime -y`)
end
source=abspath(root,"..","..","GHOST");snapshot=joinpath(root,"vendor","ghost-source")
if !isdir(snapshot)
    mkpath(snapshot)
    for item in ("include","src","thirdparty","LICENSE");cp(joinpath(source,item),joinpath(snapshot,item));end
end
# Compile exact private source snapshot, never the shared checkout or its build tree.
headers=joinpath(snapshot,"headers","ghost")
if !isdir(headers)
    mkpath(dirname(headers));cp(joinpath(snapshot,"include"),headers)
    cp(joinpath(snapshot,"thirdparty"),joinpath(headers,"thirdparty"))
end
files=[joinpath(d,f) for (d,_,fs) in walkdir(joinpath(snapshot,"src")) for f in fs if endswith(f,".cpp")]
build=joinpath(runtime,"ghost-portable");mkpath(build)
anytime="anytime" in ARGS
bin=joinpath(build,anytime ? "ghost_anytime.exe" : "ghost_routing.exe")
# A single compiler driver compiles translation units sequentially.
extra=anytime ? ["-include",joinpath(root,"native","ghost","anytime_trace.hpp")] : String[]
run(`$compiler -std=c++20 -O2 -static -pthread $extra -I$(joinpath(snapshot,"headers")) -I$(joinpath(snapshot,"include")) -I$snapshot -I$(joinpath(snapshot,"thirdparty")) $(joinpath(root,"native","ghost",anytime ? "anytime.cpp" : "main.cpp")) $files -o $bin`)
open(io->TOML.print(io,Dict("compiler_url"=>url,"compiler_archive_sha256"=>bytes2hex(open(sha256,archive)),
    "compiler_version"=>readchomp(`$compiler --version`),"binary_sha256"=>bytes2hex(open(sha256,bin)))),joinpath(build,anytime ? "anytime-build.toml" : "build.toml"),"w")
