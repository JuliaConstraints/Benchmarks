"Strict original-format readers; unsupported variants are rejected, not approximated."
module ReproductionReaders
using ..ReproductionProblems
using TOML
export read_problem, CoordinateDistances

struct CoordinateDistances <: AbstractMatrix{Float64}
    coordinates::Matrix{Float64}
    metric::Symbol
end
Base.size(d::CoordinateDistances)=(size(d.coordinates,1),size(d.coordinates,1))
function Base.getindex(d::CoordinateDistances,i::Int,j::Int)
    i==j && return 0.
    a=view(d.coordinates,i,:);b=view(d.coordinates,j,:)
    r=sqrt(sum((a[k]-b[k])^2 for k in eachindex(a)))
    d.metric==:EUC_2D && return Float64(floor(Int,r+0.5))
    d.metric==:EUC_3D && return Float64(floor(Int,r+0.5))
    d.metric==:CEIL_2D && return Float64(ceil(Int,r))
    d.metric==:euclidean && return r
    d.metric in (:MAN_2D,:MAN_3D) && return Float64(floor(Int,sum(abs(a[k]-b[k]) for k in eachindex(a))+0.5))
    d.metric in (:MAX_2D,:MAX_3D) && return Float64(floor(Int,maximum(abs(a[k]-b[k]) for k in eachindex(a))+0.5))
    if d.metric==:ATT
        r=sqrt(sum((a[k]-b[k])^2 for k in eachindex(a))/10);t=floor(Int,r+0.5)
        return Float64(t<r ? t+1 : t)
    elseif d.metric==:GEO
        rad(x)=3.141592*(trunc(x)+5(x-trunc(x))/3)/180
        ai,aj,bi,bj=rad(a[1]),rad(a[2]),rad(b[1]),rad(b[2])
        q1=cos(aj-bj);q2=cos(ai-bi);q3=cos(ai+bi)
        return Float64(floor(Int,6378.388*acos(clamp(0.5*((1+q1)*q2-(1-q1)*q3),-1,1))+1))
    end
    error("Unsupported distance metric $(d.metric)")
end

function tsplib(path,family;vehicles=nothing)
    lines=strip.(readlines(path));header=Dict{String,String}();section="";blocks=Dict{String,Vector{String}}()
    for line in lines
        isempty(line) && continue
        line=="EOF" && break
        if endswith(line,"_SECTION")
            section=line;blocks[section]=String[]
        elseif isempty(section)
            pair=split(line,':';limit=2)
            length(pair)==2 || throw(ArgumentError("Malformed TSPLIB header"))
            header[strip(pair[1])]=strip(pair[2])
        else
            push!(blocks[section],line)
        end
    end
    n=parse(Int,header["DIMENSION"])
    header["TYPE"] in (family==:tsp ? ("TSP",) : ("CVRP",)) || throw(ArgumentError("Unexpected TSPLIB problem type"))
    metric=Symbol(header["EDGE_WEIGHT_TYPE"])
    if metric==:EXPLICIT
        weights=parse.(Float64,split(join(blocks["EDGE_WEIGHT_SECTION"]," ")));D=zeros(n,n);index=1
        format=get(header,"EDGE_WEIGHT_FORMAT","")
        format in ("FULL_MATRIX","UPPER_ROW","LOWER_ROW","UPPER_DIAG_ROW","LOWER_DIAG_ROW",
            "UPPER_COL","LOWER_COL","UPPER_DIAG_COL","LOWER_DIAG_COL") || throw(ArgumentError("Unsupported explicit matrix format"))
        pairs = if format=="FULL_MATRIX"; [(i,j) for i in 1:n for j in 1:n]
        elseif format=="UPPER_ROW";[(i,j) for i in 1:n for j in i+1:n]
        elseif format=="LOWER_ROW";[(i,j) for i in 1:n for j in 1:i-1]
        elseif format=="UPPER_DIAG_ROW";[(i,j) for i in 1:n for j in i:n]
        elseif format=="LOWER_DIAG_ROW";[(i,j) for i in 1:n for j in 1:i]
        elseif format=="UPPER_COL";[(i,j) for j in 1:n for i in 1:j-1]
        elseif format=="LOWER_COL";[(i,j) for j in 1:n for i in j+1:n]
        elseif format=="UPPER_DIAG_COL";[(i,j) for j in 1:n for i in 1:j]
        else;[(i,j) for j in 1:n for i in j:n]
        end
        length(pairs)==length(weights) || throw(DimensionMismatch("TSPLIB edge weights"))
        for (i,j) in pairs
            D[i,j]=weights[index];format=="FULL_MATRIX" || (D[j,i]=weights[index]);index+=1
        end
    else
        metric in (:EUC_2D,:EUC_3D,:CEIL_2D,:MAN_2D,:MAN_3D,:MAX_2D,:MAX_3D,:ATT,:GEO) || throw(ArgumentError("Unsupported TSPLIB metric: $metric"))
        rows=[split(line) for line in blocks["NODE_COORD_SECTION"]]
        length(rows)==n && sort(parse.(Int,first.(rows)))==collect(1:n) || throw(DimensionMismatch("TSPLIB coordinates"))
        sort!(rows;by=row->parse(Int,first(row)));coords=ReproductionProblems.matrix([parse.(Float64,row[2:end]) for row in rows])
        size(coords,2)==(endswith(string(metric),"3D") ? 3 : 2) || throw(DimensionMismatch("TSPLIB coordinate dimensions"))
        D=CoordinateDistances(coords,metric)
    end
    if D isa CoordinateDistances
        all(isfinite,D.coordinates) || throw(ArgumentError("Invalid TSPLIB coordinates"))
    else
        all(isfinite,D) && all(>=(0),D) || throw(ArgumentError("Invalid TSPLIB distances"))
    end
    data=Dict{String,Any}("distance"=>D,"distance_rule"=>string(metric))
    if family==:cvrp
        depots=parse.(Int,split(join(blocks["DEPOT_SECTION"]," ")))
        depots==[1,-1] || throw(ArgumentError("Only the original single depot 1 is supported"))
        demand=zeros(Int,n)
        rows=[parse.(Int,split(line)) for line in blocks["DEMAND_SECTION"]]
        length(rows)==n && sort(first.(rows))==collect(1:n) || throw(DimensionMismatch("TSPLIB demands"))
        for row in rows; demand[row[1]]=row[2];end
        demand[1]==0 && all(>=(0),demand) || throw(ArgumentError("Invalid delivery demand"))
        # The fleet is part of the published instance; never infer it from a filename or BKS.
        vehicles===nothing && throw(ArgumentError("CVRP requires the published --vehicles value"))
        merge!(data,Dict("demand"=>demand,"capacity"=>parse(Int,header["CAPACITY"]),"vehicles"=>vehicles))
    end
    problem(family,data;id=get(header,"NAME",basename(path)))
end

function read_problem(path;family::Symbol,vehicles=nothing,clusters=nothing,format="original")
    format=="normalized" && return problem(family,TOML.parsefile(path);id=basename(path))
    family in (:tsp,:cvrp) && return tsplib(path,family;vehicles)
    family==:maintenance && return maintenance_json(path)
    lines=filter(!isempty,strip.(readlines(path)))
    if family==:bppc
        n,cap=parse.(Int,split(first(lines)));length(lines)==n+1 || throw(DimensionMismatch("Muritiba BPPC items"))
        rows=[parse.(Int,split(line)) for line in lines[2:end]]
        sort(first.(rows))==collect(1:n) || throw(DimensionMismatch("BPPC item ids"))
        sort!(rows;by=first);weights=reshape([r[2] for r in rows],n,1)
        edges=sort!(unique([minmax(i,j) for (i,r) in enumerate(rows) for j in r[3:end]]))
        return problem(family,Dict("weights"=>weights,"capacity"=>[cap],"conflicts"=>collect.(edges));id=basename(path))
    elseif family==:vbp
        tokens=parse.(Int,split(join(lines," ")));r=tokens[1];caps=tokens[2:1+r];n=tokens[2+r]
        length(tokens)==3+r+n*r || throw(DimensionMismatch("Published modified VBP records"))
        weights=permutedims(reshape(tokens[3+r:end-1],r,n))
        return problem(family,Dict("weights"=>weights,"capacity"=>caps,"max_bins"=>tokens[end]);id=basename(path))
    elseif family==:top
        length(lines)>=5 || throw(DimensionMismatch("TOP records"))
        headers=split.(lines[1:3]);first.(headers)==["n","m","tmax"] || throw(ArgumentError("Unknown original TOP header"))
        n=parse(Int,headers[1][2]);fleet=parse(Int,headers[2][2]);limit=parse(Float64,headers[3][2])
        rows=[parse.(Float64,split(line)) for line in lines[4:end]]
        length(rows)==n && all(r->length(r)==3,rows) || throw(DimensionMismatch("TOP customers"))
        return problem(family,Dict("distance"=>CoordinateDistances(ReproductionProblems.matrix([r[1:2] for r in rows]),:euclidean),
            "prize"=>last.(rows),"vehicles"=>fleet,"max_distance"=>limit,"distance_rule"=>"unrounded_euclidean");id=basename(path))
    elseif family==:car_sequencing
        tokens=parse.(Int,split(join(lines," ")));N,q,K,batch,order,past=tokens[1:6];pos=7
        0<=past<N && 0<=order<=4 || throw(ArgumentError("Invalid car prefix/objective"))
        limits=Int[];windows=Int[];priority=Int[]
        for _ in 1:q;push!(limits,tokens[pos]);push!(windows,tokens[pos+1]);push!(priority,tokens[pos+2]);pos+=3;end
        colors=Int[];counts=Int[];opts=Vector{Int}[]
        for _ in 1:K
            push!(colors,tokens[pos]);push!(counts,tokens[pos+1]);push!(opts,tokens[pos+2:pos+1+q]);pos+=q+2
        end
        classes=tokens[pos:end].+1;length(classes)==N && all(c->1<=c<=K,classes) || throw(DimensionMismatch("Car initial sequence"))
        [count(==(c),classes) for c in 1:K]==counts || throw(ArgumentError("Car multiplicities differ"))
        permutation=vcat(classes[past+1:end],classes[1:past]);n=N-past
        !(0 in priority) && (order=order==0 ? 3 : order in (1,2) ? 4 : order)
        objectives=((2,1,3),(1,3,2),(1,2,3),(2,1),(1,2))[order+1]
        return problem(family,Dict("today_count"=>n,"history"=>collect(n+1:N),"colors"=>colors[permutation],
            "options"=>ReproductionProblems.matrix(opts[permutation]),"window"=>windows,"limit"=>limits,
            "priority"=>priority,"max_paint_batch"=>batch,"objective_order"=>collect(objectives));id=basename(path))
    elseif family==:qap
        tokens=parse.(Int,split(join(lines," ")));n=first(tokens)
        length(tokens)==1+2n*n || throw(DimensionMismatch("QAPLIB matrices"))
        A=permutedims(reshape(tokens[2:1+n*n],n,n));B=permutedims(reshape(tokens[2+n*n:end],n,n))
        return problem(family,Dict("flow"=>A,"distance"=>B);id=basename(path))
    elseif family==:bpp
        tokens=parse.(Int,split(join(lines," ")));n=first(tokens)
        length(tokens)==n+2 || throw(DimensionMismatch("BPPLIB weights"))
        return problem(family,Dict("weights"=>reshape(tokens[3:end],n,1),"capacity"=>[tokens[2]]);id=basename(path))
    elseif family==:aircraft_landing
        tokens=parse.(Float64,split(join(lines," ")));n=Int(tokens[1]);length(tokens)==2+n*(6+n) || throw(DimensionMismatch("OR-Library aircraft records"))
        earliest=Int[];target=Int[];latest=Int[];early=Float64[];late=Float64[];sep=zeros(Int,n,n);pos=3
        for i in 1:n
            push!(earliest,Int(tokens[pos+1]));push!(target,Int(tokens[pos+2]));push!(latest,Int(tokens[pos+3]))
            push!(early,tokens[pos+4]);push!(late,tokens[pos+5]);sep[i,:]=Int.(tokens[pos+6:pos+5+n]);pos+=6+n
        end
        return problem(family,Dict("earliest"=>earliest,"target"=>target,"latest"=>latest,
            "early_cost"=>early,"late_cost"=>late,"separation"=>sep,"variant"=>"static_single_runway");id=basename(path))
    elseif family==:mssc
        clusters===nothing && throw(ArgumentError("MSSC requires the published cluster count"))
        n,d=parse.(Int,split(first(lines)));length(lines)==n+1 || throw(DimensionMismatch("MSSC point count"))
        coords=ReproductionProblems.matrix([parse.(Float64,split(line)[1:d]) for line in lines[2:end]])
        return problem(family,Dict("coordinates"=>coords,"clusters"=>clusters,"normalization"=>"none");id=basename(path))
    elseif family==:rcpsp
        tokens=parse.(Int,split(join(lines," ")));n,r=tokens[1:2];capacity=tokens[3:2+r];pos=3+r
        duration=Int[];resource=zeros(Int,n,r);edges=Vector{Int}[]
        for i in 1:n
            push!(duration,tokens[pos]);resource[i,:]=tokens[pos+1:pos+r];k=tokens[pos+r+1]
            for j in tokens[pos+r+2:pos+r+1+k];push!(edges,[i,j]);end
            pos+=r+2+k
        end
        pos==length(tokens)+1 || throw(DimensionMismatch("RCPSP records"))
        return problem(family,Dict("duration"=>duration,"resource_use"=>resource,"capacity"=>capacity,
            "precedence"=>edges,"horizon"=>sum(duration));id=basename(path))
    elseif family==:fjsp
        jobs,machines=parse.(Int,split(first(lines))[1:2]);length(lines)==jobs+1 || throw(DimensionMismatch("FJSP jobs"))
        choices=Vector{Vector{Vector{Int}}}();edges=Vector{Int}[]
        for line in lines[2:end]
            tokens=parse.(Int,split(line));count=tokens[1];pos=2;previous=0
            for _ in 1:count
                k=tokens[pos];pos+=1;alts=Vector{Int}[]
                for _ in 1:k
                    m,t=tokens[pos:pos+1];1<=m<=machines && t>=0 || throw(ArgumentError("Invalid FJSP alternative"))
                    push!(alts,[m,t]);pos+=2
                end
                isempty(alts) && throw(ArgumentError("No eligible machine"))
                push!(choices,alts);i=length(choices);previous==0 || push!(edges,[previous,i]);previous=i
            end
            pos==length(tokens)+1 || throw(DimensionMismatch("FJSP operation records"))
        end
        duration=[first(c)[2] for c in choices]
        return problem(family,Dict("duration"=>duration,"alternatives"=>choices,"precedence"=>edges,
            "horizon"=>sum(maximum(last,c) for c in choices));id=basename(path))
    elseif family==:jssp
        if first(lines)=="nb_jobs nb_machines"
            jobs,machines=parse.(Int,split(lines[2])[1:2]);t=findfirst(==("Times"),lines);m=findfirst(==("Machines"),lines)
            duration=[parse.(Int,split(line)) for line in lines[t+1:t+jobs]]
            machine=[parse.(Int,split(line)) for line in lines[m+1:m+jobs]]
            all(row->length(row)==machines,duration) && all(row->length(row)==machines,machine) || throw(DimensionMismatch("Taillard JSSP"))
        else
            jobs,machines=parse.(Int,split(first(lines)));length(lines)==jobs+1 || throw(DimensionMismatch("OR-Library JSSP jobs"))
            records=[parse.(Int,split(line)) for line in lines[2:end]]
            all(row->length(row)==2machines,records) || throw(DimensionMismatch("JSSP operation pairs"))
            machine=[row[1:2:end].+1 for row in records];duration=[row[2:2:end] for row in records]
        end
        all(m->1<=m<=machines,Iterators.flatten(machine)) || throw(ArgumentError("JSSP machine id"))
        edges=[[base+i,base+i+1] for base in 0:machines:(jobs-1)*machines for i in 1:machines-1]
        times=reduce(vcat,duration)
        return problem(family,Dict("duration"=>times,"machine"=>reduce(vcat,machine),"precedence"=>edges,"horizon"=>sum(times));id=basename(path))
    elseif family==:salbp
        section="";n=0;cycle=0;duration=Int[];edges=Vector{Int}[]
        for line in lines
            if startswith(line,"<");section=line;continue;end
            if section=="<number of tasks>";n=parse(Int,line);duration=zeros(Int,n)
            elseif section=="<cycle time>";cycle=parse(Int,line)
            elseif section=="<task times>";i,t=parse.(Int,split(line));duration[i]=t
            elseif section=="<precedence relations>";push!(edges,parse.(Int,split(line,',')))
            end
        end
        n>0 && cycle>0 && all(>(0),duration) || throw(ArgumentError("Incomplete SALBP input"))
        return problem(family,Dict("duration"=>duration,"cycle"=>cycle,"precedence"=>edges);id=basename(path))
    elseif family==:cvrptw
        numeric = [split(line) for line in lines if all(t->tryparse(Float64,t)!==nothing,split(line))]
        fleet=findfirst(row->length(row)==2,numeric);fleet===nothing && throw(ArgumentError("Missing Solomon fleet/capacity"))
        rows=filter(row->length(row)==7,numeric[fleet+1:end]);length(rows)>=2 || throw(ArgumentError("Missing Solomon customers"))
        ids=parse.(Int,first.(rows));ids==collect(0:length(rows)-1) || throw(ArgumentError("Original customer ids must be consecutive"))
        coords=ReproductionProblems.matrix([parse.(Float64,row[2:3]) for row in rows])
        return problem(family,Dict("distance"=>CoordinateDistances(coords,:euclidean),
            "distance_rule"=>"unrounded_euclidean","vehicles"=>parse(Int,numeric[fleet][1]),
            "capacity"=>parse(Int,numeric[fleet][2]),"demand"=>[parse(Int,row[4]) for row in rows],
            "earliest"=>[parse(Float64,row[5]) for row in rows],"latest"=>[parse(Float64,row[6]) for row in rows],
            "service"=>[parse(Float64,row[7]) for row in rows]);id=basename(path))
    end
    throw(ArgumentError("Original reader not qualified for $family/$format; normalized fixtures are not the published corpus"))
end

"The frozen solver Manifest already contains JSON; no environment mutation is required."
function maintenance_json(path)
    json=Base.require(Base.PkgId(Base.UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6"),"JSON"))
    Base.invokelatest(_maintenance_json,json,path)
end
function _maintenance_json(json,path)
    raw=json.parsefile(path);H=Int(raw["T"])
    names=sort!(collect(keys(raw["Interventions"])));resources=sort!(collect(keys(raw["Resources"])))
    scenarios=Int.(raw["Scenarios_number"]);dur=Vector{Int}[];starts=Int[];loads=Any[];risks=Any[]
    for name in names
        it=raw["Interventions"][name];S=parse(Int,string(it["tmax"]));push!(starts,S)
        push!(dur,Int.(it["Delta"][1:S]));il=Any[];ir=Any[]
        for s in 1:S
            sl=Any[];sr=Any[]
            for t in s:min(H,s+dur[end][s]-1)
                push!(sl,[Float64(get(get(get(it["workload"],r,Dict()),string(t),Dict()),string(s),0.)) for r in resources])
                # Unlike sparse resource entries, the official checker requires every active risk record.
                push!(sr,Float64.(it["risk"][string(t)][string(s)]))
            end
            push!(il,sl);push!(ir,sr)
        end
        push!(loads,il);push!(risks,ir)
    end
    index=Dict(n=>i for (i,n) in enumerate(names))
    exclusions=[[index[a],index[b],parse.(Int,string.(raw["Seasons"][season]))] for (a,b,season) in values(raw["Exclusions"])]
    data=Dict("horizon"=>H,"scenario_count"=>scenarios,"alpha"=>Float64(raw["Alpha"]),"quantile"=>Float64(raw["Quantile"]),
        "latest_start"=>starts,"duration"=>dur,"resource_use_by_start"=>loads,"risk_by_start"=>risks,"exclusions"=>exclusions,
        "capacity_lower"=>[[Float64(raw["Resources"][r]["min"][t]) for r in resources] for t in 1:H],
        "capacity_upper"=>[[Float64(raw["Resources"][r]["max"][t]) for r in resources] for t in 1:H],"intervention_names"=>names)
    problem(:maintenance,data;id=basename(path))
end
end
