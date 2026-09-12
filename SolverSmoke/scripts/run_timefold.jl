include("activate.jl")
using TOML
mode,input,out=ARGS;mkpath(out)
root=projectdir();runtime=TOML.parsefile(joinpath(root,"runtime","runtime.toml"))
java=joinpath(runtime["java_home"],"bin","java.exe")
target=joinpath(root,"native","timefold","target")
classpath=join([joinpath(target,"classes"),joinpath(target,"dependency","*")],';')
cmd=`$java -XX:ActiveProcessorCount=4 -XX:+UseSerialGC -Xmx1g -Dorg.slf4j.simpleLogger.defaultLogLevel=warn -cp $classpath bench.Smoke $mode $input $out`
started=time();p=run(pipeline(cmd;stdout=stdout,stderr=stderr);wait=false)
while process_running(p)
    if time()-started>90; kill(p);error("Timefold worker exceeded 90-second wall ceiling");end
    sleep(0.25)
end
wait(p);success(p) || error("Timefold failed")
