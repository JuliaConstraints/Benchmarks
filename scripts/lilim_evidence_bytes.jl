include(joinpath(@__DIR__,"..","Solvers","scripts","resources.jl"))
using TOML,SHA
const repo=abspath(@__DIR__,"..")
count=0
for sealname in ("ANYTIME_QUALIFICATION.toml","THREAD_QUALIFICATION.toml")
    seal=TOML.parsefile(joinpath(repo,"SolverSmoke",sealname))
    for (file,expected) in seal["raw_sha256"]
        relative=replace(joinpath("SolverSmoke",seal["evidence"],file),'\\'=>'/')
        bytes2hex(sha256(read(joinpath(repo,relative))))==expected || error("Local raw evidence changed: $relative")
        bytes2hex(sha256(read(`git -C $repo show $(":"*relative)`)))==expected || error("Git index changed evidence bytes: $relative")
        global count+=1
    end
    if haskey(seal,"historical_check")
        folder=joinpath("SolverSmoke",seal["historical_check"])
        history=TOML.parsefile(joinpath(repo,folder,"result.toml"))
        for row in history["rows"]
            relative=replace(joinpath(folder,basename(row["out"])),'\\'=>'/')
            expected=row["raw_sha256"]
            bytes2hex(sha256(read(joinpath(repo,relative))))==expected || error("Historical evidence changed")
            bytes2hex(sha256(read(`git -C $repo show $(":"*relative)`)))==expected || error("Historical Git bytes differ")
            global count+=1
        end
    end
end
println("Verified ",count," raw evidence hashes in the working tree and Git index")
