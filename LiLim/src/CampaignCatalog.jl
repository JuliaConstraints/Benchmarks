module CampaignCatalog
using TOML, SHA
include("StrategyPanel.jl")
include("RoutingPanel.jl")
const CONFIG_ROOT=normpath(joinpath(@__DIR__,"..","config"))
const THREAD_CONFIG=TOML.parsefile(joinpath(CONFIG_ROOT,"icn-threads.toml"))
const CAMPAIGN_CONFIG=TOML.parsefile(joinpath(CONFIG_ROOT,"full-corpus-campaign.toml"))
const STRATEGIES=TOML.parsefile(joinpath(CONFIG_ROOT,"strategy-variants.toml"))

"Disjoint reporting families; technical features may overlap these groups."
function family(method)
    if haskey(StrategyPanel.CATALOG,method)
        return get(Dict(:cbls=>:cbls,:hybrid=>:cbls_highs,:meta=>:meta_cbls_ro,
            :qubo=>:cbls_qubo),StrategyPanel.CATALOG[method].category,:other)
    elseif haskey(RoutingPanel.CATALOG,method)
        return RoutingPanel.CATALOG[method].category==:meta ? :meta_routing : :routing
    end
    :other
end

"Configured features of the effective lanes, distinct from observed execution."
function features(method,width)
    tags=Set{Symbol}()
    if haskey(StrategyPanel.CATALOG,method)
        for lane in StrategyPanel.allocation(method,width)
            push!(tags,lane.backend)
            policy=merge(STRATEGIES["profiles"][lane.policy],
                Dict(string(k)=>v for (k,v) in pairs(lane.overrides)))
            get(policy,"tabu","none")!="none" && push!(tags,:tabu)
            get(policy,"acceptance","greedy")=="late" && push!(tags,:late_acceptance)
            get(policy,"fraction",0.0)>0 && push!(tags,:reset)
            if lane.hybrid
                push!(tags,Symbol(lane.repair_mode))
                (lane.lp_solver in ("ipx","hipo") || lane.mip_lp_solver in ("ipx","hipo")) &&
                    push!(tags,:interior_point)
            end
            lane.bridged && push!(tags,:icn_bridge)
            lane.guide_mode!="none" && push!(tags,:qubo)
        end
    elseif haskey(RoutingPanel.CATALOG,method)
        for lane in RoutingPanel.allocation(method,width)
            push!(tags,lane.algorithm,lane.backend)
            lane.acceptance==:tabu && push!(tags,:tabu)
            lane.acceptance==:late && push!(tags,:late_acceptance)
            lane.reset_fraction>0 && push!(tags,:reset)
            lane.guidance==:qubo && push!(tags,:qubo)
            lane.master && push!(tags,:route_pool_master)
            lane.master && lane.master_lp in ("ipx","hipo") && push!(tags,:interior_point)
        end
    end
    sort!(collect(tags))
end

function screening_signatures(method)
    tags=Set(string.(features(method,4)))
    if haskey(StrategyPanel.CATALOG,method)
        for lane in StrategyPanel.allocation(method,4)
            policy=merge(STRATEGIES["profiles"][lane.policy],
                Dict(string(k)=>v for (k,v) in pairs(lane.overrides)))
            for name in ("acceptance","tabu","restart","source")
                push!(tags,name*":"*string(get(policy,name,"default")))
            end
            fraction=get(policy,"fraction",0.0)
            push!(tags,"reset:"*(fraction==0 ? "none" : fraction==1 ? "full" : "partial"))
            lane.hybrid && push!(tags,"repair:"*lane.repair_mode,
                "LP:"*lane.lp_solver,"MIP_LP:"*lane.mip_lp_solver)
            push!(tags,"guide:"*lane.guide_mode)
        end
    else
        for lane in RoutingPanel.allocation(method,4)
            push!(tags,"destroy:"*string(lane.destroy),"acceptance:"*string(lane.acceptance),
                "guidance:"*string(lane.guidance),"depth:"*string(lane.ejection_depth),
                "adaptive:"*string(lane.adaptive_roles))
            lane.master && push!(tags,"master_LP:"*lane.master_lp)
        end
    end
    tags
end

"Interleave families and prefer unseen mechanisms; affected older trials form a final replay queue."
function screening_order(methods,seed;deferred=String[],priority=String[])
    allunique(methods) || throw(ArgumentError("duplicate screening methods"))
    issubset(Set([deferred;priority]),Set(methods)) || throw(ArgumentError("unknown replay or priority method"))
    families=(:cbls,:meta_routing,:cbls_highs,:meta_cbls_ro,:cbls_qubo,:routing)
    all(m->family(m) in families,methods) || throw(ArgumentError("unknown screening family"))
    # Stable pseudo-random ties without relying on Dict iteration or Julia hash seeds.
    tie(m)=bytes2hex(SHA.sha256(string(seed)*":"*m))
    signatures=Dict(m=>screening_signatures(m) for m in methods)
    pending=Set(methods);postpone=setdiff(Set(deferred),Set(priority))
    seen=Set{String}();ordered=String[];round=0
    while !isempty(pending)
        eligible=setdiff(pending,postpone)
        isempty(eligible) && (eligible=copy(pending))
        for offset in 0:5
            category=families[mod1(round+offset+1,6)]
            candidates=[m for m in eligible if family(m)==category]
            isempty(candidates) && continue
            sort!(candidates;by=m->begin
                preferred=findfirst(==(m),priority)
                (preferred===nothing ? typemax(Int) : preferred,
                    -length(setdiff(signatures[m],seen)),tie(m))
            end)
            chosen=first(candidates);push!(ordered,chosen)
            union!(seen,signatures[chosen]);delete!(pending,chosen);delete!(eligible,chosen)
        end
        round+=1
    end
    ordered
end

function available_methods(threads)
    threads>0 || throw(ArgumentError("thread count must be positive"))
    unique(vcat(THREAD_CONFIG["methods"],CAMPAIGN_CONFIG["extra_methods"],["cbls_mix_strategy"],
        threads>=4 ? THREAD_CONFIG["portfolio_methods"] : String[]))
end

function select_methods(threads,selector)
    strategies=vcat([row["method"] for row in STRATEGIES["variants"]],sort!(collect(keys(STRATEGIES["portfolios"]))))
    historical=unique(vcat(available_methods(threads),strategies,CAMPAIGN_CONFIG["external_methods"]))
    allowed=unique(vcat(historical,StrategyPanel.methods(),RoutingPanel.methods()))
    wanted=RoutingPanel.expand(StrategyPanel.expand(String.(strip.(split(selector,',')))))
    any(isempty,wanted) && throw(ArgumentError("empty method selection"))
    for (token,expansion) in (("panel",historical),("all",available_methods(threads)),("strategies",strategies))
        token in wanted && (wanted=unique(vcat(filter(!=(token),wanted),expansion)))
    end
    unknown=setdiff(Set(wanted),Set(allowed))
    isempty(unknown) || throw(ArgumentError("methods unavailable at $threads threads: "*join(sort!(collect(unknown)),", ")))
    unique(wanted)
end
end
