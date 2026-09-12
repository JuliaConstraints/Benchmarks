include("activate.jl")
using TOML
root=projectdir();runtime=TOML.parsefile(joinpath(root,"runtime","runtime.toml"))
java=joinpath(runtime["java_home"],"bin","java.exe")
maven=joinpath(homedir(),"apache-maven-3.9.1")
launcher=only(filter(p->endswith(p,".jar"),readdir(joinpath(maven,"boot");join=true)))
native=joinpath(root,"native","timefold")
run(`$java -XX:ActiveProcessorCount=4 -XX:+UseSerialGC -Xmx1g -classpath $launcher -Dmaven.home=$maven -Dclassworlds.conf=$(joinpath(maven,"bin","m2.conf")) -Dmaven.multiModuleProjectDirectory=$native org.codehaus.plexus.classworlds.launcher.Launcher -B -f $(joinpath(native,"pom.xml")) -Dmaven.repo.local=$(joinpath(root,"runtime","m2")) package dependency:copy-dependencies`)
