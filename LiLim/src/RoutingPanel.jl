"Additive Li-Lim route strategies; historical strategy IDs remain immutable."
module RoutingPanel
using TOML
export CONFIG, CONFIG_PATH, CATALOG, methods, expand, allocation, metadata
const CONFIG_PATH = joinpath(@__DIR__, "../config/routing-panel.toml")
const CONFIG = TOML.parsefile(CONFIG_PATH)
const CATALOG = Dict{String,NamedTuple}()
const DEFAULT = (algorithm=:alns, destroy=:adaptive, regret=2, acceptance=:late,
    blinks=0.0, ejection_depth=1, reset_fraction=0.0, guidance=:none,
    backend=:icn_fused_all, master=false, master_lp="simplex", adaptive_roles=false)
function add(id, lanes; meta=false)
    row = (;category=meta ? :meta : :search, lanes=Tuple(lanes))
    row in values(CATALOG) && return
    haskey(CATALOG,id) && error("Duplicate routing profile")
    CATALOG[id] = row
end
lane(;kw...) = merge(DEFAULT,(;kw...))
for acceptance in Symbol.(CONFIG["acceptance"])
    add("rp_vnd_$acceptance", [lane(;algorithm=:vnd,acceptance)])
end
for fraction in (0.25,1.0)
    add("rp_vnd_reset_$(fraction==1 ? "full" : "partial")", [lane(;algorithm=:vnd,reset_fraction=fraction)])
end
for depth in CONFIG["ejection_depth"], acceptance in (:greedy,:late)
    add("rp_ges$(depth)_$acceptance", [lane(;algorithm=:ges,ejection_depth=depth,acceptance)])
end
for destroy in Symbol.(CONFIG["destroy"]), regret in CONFIG["regret"]
    add("rp_alns_$(destroy)_regret$regret", [lane(;destroy,regret)])
end
for blinks in CONFIG["blinks"], regret in CONFIG["regret"]
    add("rp_sisr_b$(round(Int,100blinks))_regret$regret", [lane(;algorithm=:sisr,destroy=:sisr,blinks,regret)])
end
for algorithm in (:aco,:memetic), regret in CONFIG["regret"]
    add("rp_$(algorithm)_regret$regret", [lane(;algorithm,regret)])
end
for guidance in (:qubo,:critical,:incompatibility)
    add("rp_alns_$guidance", [lane(;guidance)])
end
add("rp_alns_direct", [lane(;backend=:direct)])
add("rp_alns_naive", [lane(;backend=:naive)])
const RECIPES = (
    ("fleet_distance", (:ges,:vnd)),
    ("ruin_repair", (:alns,:sisr,:ges)),
    ("diversity", (:aco,:memetic,:alns)),
    ("guided", (:qubo,:critical,:ges,:vnd)),
    ("pool_mip", (:ges,:sisr,:vnd)),
    ("pool_ipx", (:ges,:alns,:memetic)),
    ("pool_hipo", (:ges,:alns,:vnd)),
    ("adaptive", (:ges,:alns,:sisr,:vnd)))
for (name,roles) in RECIPES, acceptance in (:late,:tabu)
    lanes = [lane(;algorithm=r in (:qubo,:critical) ? :alns : r,
        guidance=r in (:qubo,:critical) ? r : :none, acceptance,
        master=startswith(name,"pool"), master_lp=name=="pool_ipx" ? "ipx" : name=="pool_hipo" ? "hipo" : "simplex",
        adaptive_roles=name=="adaptive") for r in roles]
    add("rp_meta_$(name)_$acceptance", lanes;meta=true)
end
methods(category=:all) = sort!([id for (id,r) in CATALOG if category==:all || r.category==category])
function expand(tokens)
    aliases=Dict("routing-panel"=>:all,"routing-search-panel"=>:search,"routing-meta-panel"=>:meta)
    unique(vcat([haskey(aliases,t) ? methods(aliases[t]) : [String(t)] for t in tokens]...))
end
function allocation(id,width)
    width>0 || throw(ArgumentError("positive width required"))
    roles=CATALOG[id].lanes
    [roles[mod1(i,length(roles))] for i in 1:width]
end
function metadata(id,width)
    r=CATALOG[id]; lanes=allocation(id,width)
    Dict{String,Any}("id"=>id,"category"=>string(r.category),
        "lanes"=>[Dict(string(k)=>v isa Symbol ? string(v) : v for (k,v) in pairs(l)) for l in lanes],
        "roles"=>length(r.lanes),"initial_missing_roles"=>max(0,length(r.lanes)-width),
        "small_width_policy"=>"roles rotate between episodes; fixed CPU width",
        "coordination"=>"typed MetaStrategist episode barriers, validated incumbent and route pool sharing",
        "authority"=>"original validator and actual configured error backend")
end
end
