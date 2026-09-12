include("activate.jl")
input,out=ARGS;mkpath(out)
bin=projectdir("runtime","ghost-portable","ghost_routing.exe")
started=time();p=run(pipeline(`$bin $input $out`;stdout=stdout,stderr=stderr);wait=false)
while process_running(p)
    if time()-started>60;kill(p);error("GHOST exceeded 60-second wall ceiling");end
    sleep(0.25)
end
wait(p);success(p) || error("GHOST native routing failed")
