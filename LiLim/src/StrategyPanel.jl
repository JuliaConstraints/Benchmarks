"Deterministic, opt-in CBLS and MetaStrategist configurations shared by both runners."
module StrategyPanel
using TOML, SHA
export CONFIG, CONFIG_PATH, CATALOG, methods, expand, allocation, worker, metadata

const CONFIG_PATH=joinpath(@__DIR__,"../config/strategy-panel.toml")
const CONFIG=TOML.parsefile(CONFIG_PATH)
const CATALOG=Dict{String,NamedTuple}()
const POLICIES=Dict{String,NamedTuple}()
const DEFAULT=(backend=:icn_fused_all,policy="greedy_guided",overrides=(;),hybrid=false,
    bridged=false,max_visits=12,repair_every=32,fragment_seconds=0.5,repair_fraction=0.35,
    repair_mode="mip",lp_solver="simplex",mip_lp_solver="choose",radius=4,
    fragment_selection="random",guide_mode="none",guide_depth=4,guide_every=32,
    guide_exploration=0.10,guide_fraction=0.10,pair_selection=:best,pair_every=1)

token(x)=replace(string(x),"."=>"p","-"=>"m")
function add_policy(id,base;kw...)
    haskey(POLICIES,id) && error("Duplicate panel policy")
    POLICIES[id]=(;policy=base,overrides=(;kw...))
end
let s=CONFIG["sweeps"]
    for plateau in s["plateau"]
        add_policy("greedy_p$plateau","greedy_guided";plateau_rejection=plateau)
    end
    for tenure in s["tabu_tenure"],clock in s["tabu_clock"]
        add_policy("tabu_t$(tenure)_$clock","tabu_short";local_tenure=tenure,selected_tenure=max(1,tenure÷4),clock)
    end
    for history in s["late_history"],tenure in (4,16)
        add_policy("late_h$(history)_t$tenure","late_400";history,local_tenure=tenure)
    end
    for probability in s["restart_probability"],fraction in s["restart_fraction"],source in s["restart_source"]
        add_policy("reset_p$(token(probability))_f$(token(fraction))_$source","reset_current";probability,fraction,source)
    end
    for scale in s["universal_scale"],fraction in (0.10,1.0),source in s["restart_source"]
        add_policy("universal_s$(scale)_f$(token(fraction))_$source","universal_current";universal_scale=scale,fraction,source)
    end
    for tenure in (4,16),full_every in s["exhaustion_full_every"]
        add_policy("exhaustion_t$(tenure)_full$full_every","exhaustion_partial";
            local_tenure=tenure,tabu_threshold=tenure,full_every)
    end
end
function add(id,category,lanes,weights=ones(Int,length(lanes)))
    haskey(CATALOG,id) && error("Duplicate method $id")
    all(>(0),weights) && length(weights)==length(lanes) || error("Invalid recipe weights")
    # Collapse identical roles and normalize ratios before semantic deduplication.
    roles=NamedTuple[];counts=Int[]
    for (lane,weight) in zip(lanes,weights)
        index=findfirst(==(lane),roles)
        if index===nothing;push!(roles,lane);push!(counts,weight)
        else;counts[index]+=weight;end
    end
    counts .÷= gcd(counts...)
    row=(;category,lanes=Tuple(roles),weights=Tuple(counts))
    row in values(CATALOG) && return
    CATALOG[id]=row
end
for backend in Symbol.(CONFIG["backends"]),(id,p) in sort!(collect(POLICIES);by=first)
    add("xp_cbls_$(backend)_$id",:cbls,[merge(DEFAULT,p,(;backend))])
end

const REPAIRS=("mip","root_ipx","root_hipo","rins_simplex","rins_ipx","local_branching")
function repair_lane(policy,intensity,mode;guide_mode="none",bridged=false)
    r=CONFIG["repair"][intensity]
    merge(DEFAULT,(;policy,hybrid=true,bridged,max_visits=r["max_visits"],repair_every=r["every"],
        fragment_seconds=r["slice_seconds"],repair_fraction=r["fraction"],radius=r["radius"],
        repair_mode=startswith(mode,"rins") ? "rins" : mode=="local_branching" ? mode : "mip",
        lp_solver=mode=="rins_ipx" ? "ipx" : "simplex",
        mip_lp_solver=mode=="root_ipx" ? "ipx" : mode=="root_hipo" ? "hipo" : "choose",
        fragment_selection=guide_mode=="none" ? "bottleneck" : "qubo",guide_mode))
end
for policy in ("greedy_guided","tabu_short","late_400","exhaustion_partial"),
        intensity in ("light","balanced","heavy"),mode in REPAIRS
    add("xp_hybrid_$(policy)_$(intensity)_$mode",:hybrid,[repair_lane(policy,intensity,mode)])
end
for depth in CONFIG["guide"]["depths"],every in CONFIG["guide"]["every"],
        exploration in CONFIG["guide"]["exploration"],mode in ("absolute","conditional")
    lane=merge(DEFAULT,(;policy="late_400",guide_mode=mode,guide_depth=depth,guide_every=every,guide_exploration=exploration))
    add("xp_qubo_$(mode)_d$(depth)_e$(every)_x$(token(exploration))",:qubo,[lane])
end

# Recipes specify roles, not one homogeneous method renamed many times.
const RECIPES=(
    ("policies",("plain","tabu","late","reset")),
    ("mip",("plain","tabu","mip","mip")),
    ("rins",("late","tabu","rins_simplex","rins_ipx")),
    ("root_lp",("plain","late","root_ipx","root_hipo")),
    ("repair_diverse",("tabu","mip","local_branching","rins_ipx")),
    ("qubo_ro",("qubo_absolute","qubo_conditional","local_branching","rins_ipx")),
    ("bridge_ro",("late","bridge","mip","rins_simplex")),
    ("errors",("naive","direct","icn","plain")))
function role_lane(role,intensity,policy_mix)
    base=policy_mix=="exploit" ? "tabu_short" : policy_mix=="explore" ? "exhaustion_partial" : "late_400"
    role in REPAIRS && return repair_lane(base,intensity,role)
    role=="bridge" && return repair_lane(base,intensity,"mip";bridged=true)
    role in ("qubo_absolute","qubo_conditional") && return merge(repair_lane(base,intensity,"rins_ipx";
        guide_mode=role=="qubo_absolute" ? "absolute" : "conditional"),(;guide_depth=8))
    backend=role in ("naive","direct","icn") ? Symbol(role) : :icn_fused_all
    policy=role=="tabu" ? "tabu_short" : role=="late" ? "late_400" : role=="reset" ? "universal_current_full" : base
    merge(DEFAULT,(;backend,policy))
end
for (recipe,roles) in RECIPES,intensity in ("light","balanced","heavy"),
        mix in ("exploit","balanced","explore"),(ratio,weights) in
        (("equal",[1,1,1,1]),("ls_heavy",[3,3,1,1]),("ro_heavy",[1,1,3,3]))
    add("xp_meta_$(recipe)_$(intensity)_$(mix)_$ratio",:meta,[role_lane(r,intensity,mix) for r in roles],weights)
end
methods(category=:all)=sort!([id for (id,row) in CATALOG if category==:all || row.category==category])
function expand(tokens)
    output=String[]
    for id in tokens
        category=get(Dict("cbls-panel"=>:cbls,"hybrid-panel"=>:hybrid,"meta-panel"=>:meta,
            "qubo-panel"=>:qubo,"extended-panel"=>:all),id,nothing)
        append!(output,category===nothing ? [String(id)] : methods(category))
    end
    unique(output)
end

"Largest-remainder resource allocation; missing roles at small widths stay explicit."
function allocation(id,width)
    width>0 || throw(ArgumentError("positive width required"))
    row=CATALOG[id];quota=width.*collect(row.weights)./sum(row.weights)
    counts=floor.(Int,quota)
    for i in sortperm(eachindex(quota);by=i->(-(quota[i]-counts[i]),i))[1:width-sum(counts)]
        counts[i]+=1
    end
    # Round-robin roles make prefix diagnostics meaningful; total counts are fixed.
    lanes=NamedTuple[];left=copy(counts)
    while length(lanes)<width
        for i in eachindex(left)
            left[i]>0 || continue
            push!(lanes,row.lanes[i]);left[i]-=1
        end
    end
    lanes
end
worker(id)=only(CATALOG[id].lanes)
plain(x::NamedTuple)=Dict(string(k)=>plain(v) for (k,v) in pairs(x))
plain(x::Tuple)=plain.(collect(x))
plain(x::Symbol)=string(x)
plain(x)=x
function metadata(id,width)
    row=CATALOG[id];lanes=allocation(id,width)
    Dict("method"=>id,"category"=>string(row.category),"config_sha256"=>bytes2hex(sha256(read(CONFIG_PATH))),
        "recipe"=>plain(row),"effective_lanes"=>plain.(lanes),"workers"=>width,
        "missing_roles"=>[i for i in eachindex(row.lanes) if !(row.lanes[i] in lanes)],
        "coordination"=>"fixed heterogeneous MetaStrategist allocation; independent owned workspaces; validated final incumbent merge")
end
end
