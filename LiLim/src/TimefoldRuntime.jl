using Downloads, Pkg.Artifacts

function timefold_sdk(root; install=false)
    lock = TOML.parsefile(joinpath(root,"LiLim/native/timefold/sdk.toml"))
    lock["schema"]=="timefold-sdk/1" || error("Unknown Timefold SDK lock")
    jars = String[]
    for row in lock["jars"]
        filename = row["filename"]
        basename(filename)==filename || error("Invalid Timefold SDK filename")
        existing = joinpath(root,"LiLim/native/timefold/target/dependency",filename)
        if isfile(existing)
            digest(existing)==row["sha256"] || error("Existing Timefold SDK bytes differ; file preserved")
            push!(jars,existing)
            continue
        end
        name = row["artifact"]
        metadata = artifact_meta(name,SolverArtifacts.BINDINGS)
        expected = artifact_hash(name,SolverArtifacts.BINDINGS)
        expected===nothing && error("Missing Timefold Artifact binding")
        if !artifact_exists(expected)
            install || throw(UnavailableSolver("timefold","sdk_not_prepared"))
            download = only(metadata["download"])
            actual = mktempdir() do directory
                archive = joinpath(directory,filename)
                Downloads.download(download["url"],archive)
                digest(archive)==row["sha256"]==download["sha256"] || error("Timefold SDK checksum mismatch")
                create_artifact() do destination
                    cp(archive,joinpath(destination,filename))
                end
            end
            actual==expected || error("Timefold SDK Artifact tree mismatch")
        end
        path = joinpath(artifact_path(expected),filename)
        digest(path)==row["sha256"] || error("Cached Timefold SDK bytes differ")
        push!(jars,path)
    end
    jars
end

function timefold_sources(root)
    native = joinpath(root,"LiLim/native/timefold")
    files = [joinpath(native,"src/main/java/bench/Pdptw.java"),
        joinpath(native,"src/test/java/bench/PdptwQualification.java"),
        joinpath(native,"pom.xml"),joinpath(native,"sdk.toml")]
    Dict(relpath(path,root)=>digest(path) for path in files)
end

"Reuse a checked Java 21 runtime and SDK; compile only a missing adapter."
function resolve_timefold(java=get(ENV,"JAVA_EXECUTABLE","java");root,install=false,cpus=nothing,probe=capture)
    executable_path = executable(java)
    executable_path===nothing && throw(UnavailableSolver("timefold","java_not_found"))
    version = probe(`$executable_path --version`)
    version.code==0 && !version.timed_out || throw(UnavailableSolver("timefold","java_probe_failed"))
    matched = match(r"(?:openjdk|java)\s+(\d+)\.(\S+)",version.output)
    matched!==nothing && matched[1]=="21" || throw(UnavailableSolver("timefold","java_21_required_existing_runtime_preserved"))
    native = joinpath(root,"LiLim/native/timefold")
    directory = joinpath(native,".runtime")
    metadata = joinpath(directory,"qualification.toml")
    if install && !isdir(directory)
        modules = probe(`$executable_path --list-modules`)
        modules.code==0 && occursin("jdk.compiler@21",modules.output) ||
            throw(UnavailableSolver("timefold","java_21_compiler_required"))
    end
    jars = timefold_sdk(root;install)
    sources = timefold_sources(root)
    sdk = Dict(basename(path)=>digest(path) for path in jars)
    if isdir(directory)
        isfile(metadata) || error("Incomplete Timefold build preserved; choose a clean handoff checkout")
        saved = TOML.parsefile(metadata)
        saved["sources"]==sources && saved["sdk"]==sdk || error("Timefold build differs from frozen sources; existing build preserved")
        for (relative,expected) in saved["classes"]
            basename(relative)==relative && error("Invalid Timefold class path")
            path = joinpath(directory,"classes",relative)
            startswith(relpath(path,joinpath(directory,"classes")),"..") && error("Timefold class path leaves build")
            isfile(path) && digest(path)==expected || error("Timefold compiled class bytes differ")
        end
    else
        install || throw(UnavailableSolver("timefold","adapter_not_prepared"))
        mktempdir(native;prefix=".compile-") do temporary
            classes = joinpath(temporary,"classes");mkpath(classes)
            classpath = join(jars,SolverArtifacts.path_separator())
            main = joinpath(native,"src/main/java/bench/Pdptw.java")
            tests = joinpath(native,"src/test/java/bench/PdptwQualification.java")
            command = `$executable_path -XX:ActiveProcessorCount=1 -XX:+UseSerialGC -Xmx512m --add-modules jdk.compiler -cp $classpath com.sun.tools.javac.Main -source 21 -target 21 -d $classes -classpath $classpath $main $tests`
            cpus===nothing || (command=PlatformResources.pin(command,cpus))
            built = probe(command;timeout=60)
            built.code==0 && !built.timed_out || error("Timefold adapter compilation failed")
            hashes = Dict(relpath(joinpath(dir,file),classes)=>digest(joinpath(dir,file))
                for (dir,_,files) in walkdir(classes) for file in files)
            isempty(hashes) && error("Timefold compilation produced no classes")
            state = Dict("schema"=>"timefold-build/1","version"=>"2.6.0","sources"=>sources,"sdk"=>sdk,"classes"=>hashes)
            open(io->TOML.print(io,state;sorted=true),joinpath(temporary,"qualification.toml"),"w")
            mv(temporary,directory)
        end
    end
    Dict("java"=>executable_path,"java_version"=>matched.match,"version"=>"2.6.0",
        "classpath"=>join(vcat([joinpath(directory,"classes")],jars),SolverArtifacts.path_separator()),
        "sources"=>sources,"sdk"=>sdk,"build_sha256"=>digest(metadata))
end

function timefold_command(identity,classname,args...;cpus)
    PlatformResources.pin(`$(identity["java"]) -XX:ActiveProcessorCount=1 -XX:+UseSerialGC -Xmx512m -Dorg.slf4j.simpleLogger.defaultLogLevel=warn -cp $(identity["classpath"]) $classname $args`,cpus)
end
