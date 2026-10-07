module ReproductionSelections
using TOML,SHA
using ..ReproductionReaders
export selection,load_instance,verify_instances
digest(p)=bytes2hex(sha256(read(p)))
function selection(path)
    manifest=TOML.parsefile(path)
    manifest["schema"]=="hexaly-instance-selection/1" || error("Unknown instance selection")
    rows=manifest["instances"]
    allunique(getindex.(rows,"id")) || error("Duplicate instance ID")
    for row in rows
        row["scope"] in ("functional_smoke","local_comparison","published_selection") || error("Unknown instance scope")
        row["metric"]=="original_primal" || error("A primal trial cannot reproduce dual-bound records")
        row["family"]!="irp" || error("Continuous IRP is deferred")
        length(row["sha256"])==64 || error("Instance hash required")
        if row["scope"]=="published_selection"
            haskey(row,"reference") && haskey(row,"reference_url") || error("Published reproduction requires original references")
            row["reference"] isa Vector && !isempty(row["reference"]) && all(isfinite,row["reference"]) || error("Finite objective reference required")
            startswith(row["reference_url"],"https://") || error("Primary reference URL required")
        end
    end
    manifest
end
function instance_path(root,row)
    relative=row["path"];isabspath(relative) && error("Use portable repository-relative instance paths")
    path=abspath(joinpath(root,relative));startswith(relpath(path,root),"..") && error("Instance leaves repository")
    path
end
function load_instance(root,row)
    path=instance_path(root,row)
    isfile(path) && digest(path)==row["sha256"] || error("Missing or changed original instance: $(row["id"])")
    parameters=Dict{Symbol,Any}(Symbol(k)=>v for(k,v)in get(row,"parameters",Dict()))
    p=read_problem(path;family=Symbol(row["family"]),parameters...)
    (;p,path)
end
function verify_instances(root,manifest)
    [begin
        path=instance_path(root,row)
        Dict("id"=>row["id"],"entry"=>row["entry"],"scope"=>row["scope"],
            "status"=>!isfile(path) ? "missing" : digest(path)==row["sha256"] ? "verified" : "hash_mismatch")
    end for row in manifest["instances"]]
end
end
