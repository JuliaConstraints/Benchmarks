include("activate.jl")
using TOML,Dates
out=abspath(only(ARGS));runs=joinpath(out,"runs");rows=Dict{String,Any}[]
for dir in readdir(runs;join=true)
    isfile(joinpath(dir,"status.toml")) || continue
    row=merge(TOML.parsefile(joinpath(dir,"job.toml")),TOML.parsefile(joinpath(dir,"status.toml")))
    if isfile(joinpath(dir,"validated.toml"));merge!(row,TOML.parsefile(joinpath(dir,"validated.toml")));end
    push!(rows,row)
end
# One shared post-hoc target per instance, explicitly labelled observed, not known optimal.
targets=Dict{String,Tuple{Int,Float64}}()
for row in rows,event in get(row,"events",[])
    event["within_solve_budget"] || continue
    key=(event["vehicles"],event["distance"]);id=row["instance"]
    targets[id]=min(get(targets,id,(typemax(Int),Inf)),key)
end
for row in rows
    haskey(targets,row["instance"]) || continue
    target=targets[row["instance"]];row["target_origin"]="best observed in this report, not an optimality claim"
    row["target_vehicles"],row["target_distance"]=target
    event=findfirst(e->e["within_solve_budget"] && (e["vehicles"]<target[1] || (e["vehicles"]==target[1] && e["distance"]<=target[2]+1e-8)),get(row,"events",[]))
    row["target_reached"]=event!==nothing
    if event!==nothing
        row["time_to_target_seconds"]=row["events"][event]["solve_seconds"]
        row["time_to_target_end_to_end_seconds"]=row["events"][event]["elapsed_seconds"]
    end
end
open(io->TOML.print(io,Dict("reported_utc"=>string(now(UTC)),"rows"=>rows);sorted=true),joinpath(out,"anytime-report.toml"),"w")
open(joinpath(out,"anytime-report.md"),"w") do io
    println(io,"# Li–Lim anytime diagnostic\n\n$(length(rows)) completed observations. Missing discovery times are unavailable, never replaced by solve duration.\n")
    println(io,"| Instance | Engine / profile | Budget | State | First feasible (s) | Shared target (s) |\n|---|---|---:|---|---:|---:|")
    for row in rows
        println(io,"| ",row["instance"]," | ",row["engine"]," / ",row["profile"]," | ",row["budget"]," | ",row["state"]," | ",
            get(row,"first_feasible_seconds","—")," | ",get(row,"time_to_target_seconds","—")," |")
    end
end
