include("activate.jl")
using COPInstances,TOML,SHA,Dates
include("../src/Anytime.jl");using .Anytime
include("../src/AnytimeValidation.jl");using .AnytimeValidation
include("../src/AnytimeRunner.jl");using .AnytimeRunner
import .AnytimeRunner: save
root=datadir("anytime-inputs");mkpath(root)
specs=COPInstances.instances(COPInstances.li_lim_registry())
budgets=[30,60,120,240];seeds=[1,2,3]
total=length(specs)*length(configurations)*sum(budgets)*length(seeds)
plan=Dict("schema"=>"anytime-campaign-plan/1","instances"=>length(specs),"configurations"=>length(configurations),
    "budgets_seconds"=>budgets,"seeds"=>seeds,"jobs"=>length(specs)*length(configurations)*length(budgets)*length(seeds),
    "nominal_sequential_search_days"=>total/86400,"cpu_ceiling"=>4,"hexaly"=>"excluded: license not activated",
    "budget_semantics"=>"independent restart at each time budget, not truncation of a 240-second run")
save(joinpath(root,"plan.toml"),plan);println(plan);flush(stdout)
"--plan-only" in ARGS && exit()
cases=Dict{String,Any}[]
for spec in specs
    dir=joinpath(root,spec.id);mkpath(dir)
    try
        download=COPInstances.download_dataset(:li_lim;ids=[spec.id],cache=datadir("anytime-cache"),
            downloader=(url,path)->COPInstances.Downloads.download(url,path;timeout=30))
        source=download.paths[spec.id];p=Benchmarks.read_benchmark(source,:li_lim)
        target=joinpath(dir,"instance.txt");write_input(target,p)
        push!(cases,Dict("id"=>spec.id,"input"=>target,"raw_source"=>source,"source_sha256"=>bytes2hex(sha256(read(source))),
            "input_sha256"=>bytes2hex(sha256(read(target))),"nominal_tasks"=>spec.scale["nominal_tasks"],
            "actual_customers"=>length(p.data.demand)-1,"fleet"=>p.data.vehicles,"ready"=>true))
    catch e
        push!(cases,Dict("id"=>spec.id,"nominal_tasks"=>spec.scale["nominal_tasks"],"ready"=>false,"error"=>sprint(showerror,e)))
    end
    save(joinpath(root,"cases.toml"),Dict("cases"=>cases))
    println("PREPARED ",length(cases),"/",length(specs)," ",spec.id," ready=",last(cases)["ready"]);flush(stdout)
end
save(joinpath(root,"prepared.toml"),Dict("completed_utc"=>string(now(UTC)),"ready"=>count(c->c["ready"],cases),"total"=>length(specs)))
