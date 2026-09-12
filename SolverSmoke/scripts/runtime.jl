include(joinpath(@__DIR__, "..", "..", "Solvers", "scripts", "resources.jl"))
using Downloads, SHA, TOML
root=abspath(@__DIR__,"..")
runtime=joinpath(root,"runtime"); mkpath(runtime)
# Portable, private runtime. No global Java installation or environment changes.
url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip"
checksum="f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e"
archive=joinpath(runtime,"jdk.zip")
(!isfile(archive) || filesize(archive)==0) && Downloads.download(url,archive)
bytes2hex(open(sha256,archive))==checksum || error("JDK checksum mismatch")
jdkroot=joinpath(runtime,"jdk"); mkpath(jdkroot)
isempty(readdir(jdkroot)) && run(`tar -xf $archive -C $jdkroot`)
javahome=only(filter(isdir,readdir(jdkroot;join=true)))
open(io->TOML.print(io,Dict("java_home"=>javahome,"jdk_url"=>url,"jdk_sha256"=>checksum);sorted=true),joinpath(runtime,"runtime.toml"),"w")
juls=joinpath(root,"vendor","JuLS")
isdir(juls) || run(`git clone --depth 1 https://github.com/amazon-science/JuLS.git $juls`)
revision="5033406449e48b7aae1cf5ac45ac12cf8a26ff02"
if readchomp(`git -C $juls rev-parse HEAD`)!=revision
    isempty(readchomp(`git -C $juls status --porcelain`)) || error("Refusing to change modified JuLS snapshot")
    run(`git -C $juls fetch --depth 1 origin $revision`)
    run(`git -C $juls checkout --detach $revision`)
end
println("Java ready: ",javahome)
println("JuLS revision: ",readchomp(`git -C $juls rev-parse HEAD`))
