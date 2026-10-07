module ReproductionSources
using Downloads,SHA,TOML,Pkg
export fetch_sources,verify_sources,digest
digest(p)=bytes2hex(sha256(read(p)))
function verify_sources(root,lock)
    records=Dict{String,Any}[]
    for row in lock["sources"]
        path=joinpath(root,"Hexaly/data",row["id"],row["filename"])
        status=!isfile(path) ? "missing" : digest(path)==row["sha256"] ? "verified" : "hash_mismatch"
        push!(records,Dict("id"=>row["id"],"status"=>status,"scope"=>row["scope"],"url"=>row["url"]))
    end
    records
end
function fetch_sources(root,lock;select="all")
    wanted=select=="all" ? getindex.(lock["sources"],"id") : split(select,',')
    all(id->id in getindex.(lock["sources"],"id"),wanted) || throw(ArgumentError("Unknown source bundle"))
    for row in lock["sources"]
        row["id"] in wanted || continue
        directory=joinpath(root,"Hexaly/data",row["id"]);mkpath(directory);path=joinpath(directory,row["filename"])
        if isfile(path)
            digest(path)==row["sha256"] || error("Existing source bytes differ and were preserved: $(row["id"])")
        else
            mktemp(directory) do temporary,io
                close(io);Downloads.download(row["url"],temporary;timeout=120)
                digest(temporary)==row["sha256"] || error("Published source changed; archive was not accepted: $(row["id"])")
                mv(temporary,path)
            end
        end
        output=joinpath(directory,"extracted");marker=joinpath(output,"archive-sha256")
        if row["format"]=="zip"
            if isdir(output)
                isfile(marker) && strip(read(marker,String))==row["sha256"] || error("Existing extracted source is unsealed and was preserved")
            else
                # The original vendor archive is checked against the committed digest before extraction.
                mkpath(output)
                run(pipeline(`$(Pkg.PlatformEngines.exe7z()) x -y -o$output $path`;stdout=devnull))
                write(marker,row["sha256"]*"\n")
            end
        end
    end
    verify_sources(root,lock)
end
end
