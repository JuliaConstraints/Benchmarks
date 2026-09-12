include("activate.jl")
root=projectdir();source=abspath(root,"..","..","GHOST","build-jump-wrapper","install-test")
snapshot=joinpath(root,"vendor","ghost-native")
if !isdir(snapshot)
    mkpath(snapshot)
    for folder in ("include","lib");cp(joinpath(source,folder),joinpath(snapshot,folder));end
end
native=joinpath(root,"native","ghost");build=joinpath(root,"runtime","ghost-build")
run(`cmake -S $native -B $build -G "Visual Studio 17 2022" -A x64 -DGHOST_SNAPSHOT=$snapshot`)
run(`cmake --build $build --config Release --parallel 4`)
