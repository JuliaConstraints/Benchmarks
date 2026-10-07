module ReproductionHexaly
using ..ReproductionProblems,TOML,SHA
include("../../LiLim/src/NativeSolvers.jl")
export solve_hexaly,template_model,decode_output,TEMPLATES
const TEMPLATES=Dict(:tsp=>"tsp",:cvrp=>"cvrp",:cvrptw=>"cvrptw",:qap=>"qap",:bpp=>"bin_packing",
    :mssc=>"kmeans",:rcpsp=>"rcpsp",:jssp=>"jobshop",:fjsp=>"flexiblejobshop",:salbp=>"assembly_line_balancing",
    :aircraft_landing=>"aircraft_landing",:car_sequencing=>"car_sequencing_color")
function function_span(source,name)
    found=findfirst("function "*name*"()",source);found===nothing && error("Vendor function missing: $name")
    opening=findnext('{',source,last(found));depth=0
    i=opening
    while i<=lastindex(source)
        c=source[i];c=='{' && (depth+=1);c=='}' && (depth-=1)
        depth==0 && return first(found):i
        i=nextind(source,i)
    end
    error("Unclosed vendor function")
end
function output_body(f)
    f==:tsp && return "for [i in 0...nbCities] f.println(i+1, \" \", cities.value[i]+1);"
    f==:qap && return "for [i in 0...n] f.println(i+1, \" \", p.value[i]+1);"
    f in (:cvrp,:cvrptw) && return "for [k in 0...nbTrucks] { local pos=0; for [c in customersSequences[k].value] { f.println(c+1, \" \", k+1, \" \", pos); pos+=1; } }"
    f==:bpp && return "for [k in 0...nbMaxBins] for [i in bins[k].value] f.println(i+1, \" \", k+1);"
    f==:mssc && return "for [c in 0...k] for [i in clusters[c].value] f.println(i+1, \" \", c+1);"
    f==:salbp && return "for [i in 0...nbTasks] f.println(i+1, \" \", taskStation[i].value+1);"
    f==:rcpsp && return "for [i in 0...nbTasks] f.println(i+1, \" \", tasks[i].value.start);"
    f==:jssp && return "for [j in 0...nbJobs][k in 0...nbMachines] f.println(j*nbMachines+k+1, \" \", tasks[j][machineOrder[j][k]].value.start);"
    f==:fjsp && return "for [i in 0...nbTasks] f.println(i+1, \" \", tasks[i].value.start, \" \", taskMachine[i].value+1, \" \", duration[i].value);"
    f==:aircraft_landing && return "for [i in 0...nbPlanes] f.println(landingOrder.value[i]+1, \" \", landingTime.value[i]);"
    f==:car_sequencing && return "for [i in startPosition...nbPositions] f.println(i-startPosition+1, \" \", sequence.value[i]-startPosition+1);"
    throw(ArgumentError("No vendor exporter for $f"))
end
function template_model(root,p)
    id=get(TEMPLATES,p.family,nothing);id===nothing && throw(ArgumentError("No qualified vendor template for $(p.family)"))
    lock=TOML.parsefile(joinpath(root,"Hexaly/config/sources.toml"));entry=only(filter(r->r["id"]==id,lock["sources"]))
    archive=joinpath(root,"Hexaly/data",id,entry["filename"])
    isfile(archive) && bytes2hex(sha256(read(archive)))==entry["sha256"] || error("Missing or changed vendor template archive")
    candidates=[joinpath(dir,f) for (dir,_,files) in walkdir(joinpath(root,"Hexaly/data",id,"extracted")) for f in files if endswith(f,".hxm")]
    path=only(candidates)
    relative=relpath(path,joinpath(root,"Hexaly/data",id,"extracted"))
    bytes2hex(sha256(read(path)))==entry["model_files"][relative] || error("Extracted vendor model changed")
    source=read(path,String)
    # Modification is solely a Hexaly application under the external template's license.
    # Its source is never imported into the CBLS models or redistributed in Git.
    span=function_span(source,"output")
    replacement="function output() { local f=io.openWrite(jcOut); f.println(\"JC_DECISIONS_1\"); "*output_body(p.family)*" f.close(); }"
    replace(source,source[span]=>replacement;count=1)
end
function decode_output(p,text)
    lines=filter(!isempty,strip.(split(text,'\n')))
    !isempty(lines) && first(lines)=="JC_DECISIONS_1" || error("Malformed Hexaly decision output")
    rows=[parse.(Float64,split(line)) for line in lines[2:end]]
    n=length(domains(p));expected=p.family==:fjsp || p.family in (:cvrp,:cvrptw) ? n÷2 : n
    length(rows)==expected && sort(Int.(first.(rows)))==collect(1:expected) || error("Missing/duplicate Hexaly decisions")
    if p.family in (:cvrp,:cvrptw)
        all(r->length(r)==3 && all(isinteger,r),rows) || error("Malformed Hexaly routes")
        sort!(rows;by=r->(r[2],r[3]));labels=zeros(Int,expected)
        for r in rows;labels[Int(r[1])]=Int(r[2]);end
        values=vcat(Int.(first.(rows)),labels)
    elseif p.family==:fjsp
        sort!(rows;by=first);choices=Int[]
        for(i,row)in enumerate(rows)
            length(row)==4 || error("Missing FJSP machine/duration")
            k=findfirst(a->a==Int.(row[3:4]),p.data["alternatives"][i]);k===nothing && error("Ineligible exported FJSP machine")
            push!(choices,k)
        end
        values=vcat(Int.(getindex.(rows,2)),choices)
    else
        all(r->length(r)==2 && all(isinteger,r),rows) || error("Malformed integer Hexaly decisions")
        sort!(rows;by=first);values=Int.(last.(rows))
    end
    checked=validate(p,values)
    (;values,checked)
end
function solve_hexaly(root,p,original;seconds=1.,threads=1,seed=41,executable=get(ENV,"HEXALY_EXECUTABLE","hexaly"),max_cells=250_000)
    isinteger(seconds) && seconds>=1 || throw(ArgumentError("Hexaly budgets are whole seconds"))
    executable=NativeSolvers.resolve_hexaly(executable);source=template_model(root,p)
    mktempdir() do directory
        model=joinpath(directory,"model.hxm");write(model,source)
        output=joinpath(directory,"solution.txt");input=original
        if p.family==:tsp
            D=p.data["distance"];n=size(D,1);n*n<=max_cells || throw(ArgumentError("Dense template conversion exceeds size cap"))
            all(isinteger,D) || throw(ArgumentError("The vendor TSP template accepts integer distances only"))
            input=joinpath(directory,"distances.tsp")
            open(input,"w") do io
                println(io,"DIMENSION: ",n,"\nEDGE_WEIGHT_SECTION")
                for i in 1:n;println(io,join(Int.(D[i,:]),' '));end
            end
        elseif p.family==:cvrp
            D=p.data["distance"]
            hasproperty(D,:coordinates) && D.metric==:EUC_2D && all(isinteger,D.coordinates) || throw(ArgumentError("Vendor CVRP reader would change the original metric/coordinates"))
            # The official template uses an unrestricted fleet; apply the same explicit fleet cap.
            span=function_span(source,"model");before=source[span]
            source=replace(source,before=>before[1:end-1]*" constraint nbTrucksUsed <= "*string(p.data["vehicles"])*"; }";count=1)
            write(model,source)
        elseif p.family==:cvrptw
            all(isinteger,p.data["distance"].coordinates) && all(k->all(isinteger,p.data[k]),("earliest","latest","service","demand")) ||
                throw(ArgumentError("The vendor Solomon reader would change noninteger original data"))
        elseif p.family==:mssc
            input=joinpath(directory,"points.txt");coords=p.data["coordinates"]
            open(input,"w") do io
                println(io,size(coords,1)," ",size(coords,2))
                for i in axes(coords,1);println(io,join(coords[i,:],' ')," 0");end
            end
        end
        args=["inFileName="*abspath(input),"jcOut="*output,"hxTimeLimit="*string(Int(seconds)),"hxNbThreads="*string(threads),"hxSeed="*string(seed)]
        p.family==:mssc && push!(args,"k="*string(p.data["clusters"]))
        result=NativeSolvers.capture(`$executable $model $args`;timeout=seconds+120)
        result.timed_out && error("Hexaly did not exit after its bounded solve")
        result.code==0 && isfile(output) || error("Hexaly model/exporter failed qualification; vendor diagnostics remain private")
        decoded=decode_output(p,read(output,String))
        Dict("status"=>decoded.checked.valid ? "feasible" : "no_feasible_solution",
            "values"=>decoded.checked.valid ? decoded.values : Int[],"objective"=>decoded.checked.valid ? collect(decoded.checked.objective) : Float64[],
            "rejected_native_candidates"=>decoded.checked.valid ? 0 : 1,"version"=>"15.0",
            "model_provenance"=>"checksum-frozen external vendor template with original decision exporter; license qualification required")
    end
end
end
