module CampaignCatalog
using TOML
const CONFIG_ROOT=normpath(joinpath(@__DIR__,"..","config"))
const THREAD_CONFIG=TOML.parsefile(joinpath(CONFIG_ROOT,"icn-threads.toml"))
const CAMPAIGN_CONFIG=TOML.parsefile(joinpath(CONFIG_ROOT,"full-corpus-campaign.toml"))
const STRATEGIES=TOML.parsefile(joinpath(CONFIG_ROOT,"strategy-variants.toml"))

function available_methods(threads)
    threads>0 || throw(ArgumentError("thread count must be positive"))
    unique(vcat(THREAD_CONFIG["methods"],CAMPAIGN_CONFIG["extra_methods"],["cbls_mix_strategy"],
        threads>=4 ? THREAD_CONFIG["portfolio_methods"] : String[]))
end

function select_methods(threads,selector)
    strategies=vcat([row["method"] for row in STRATEGIES["variants"]],sort!(collect(keys(STRATEGIES["portfolios"]))))
    allowed=unique(vcat(available_methods(threads),strategies,CAMPAIGN_CONFIG["external_methods"]))
    wanted=String.(strip.(split(selector,',')))
    any(isempty,wanted) && throw(ArgumentError("empty method selection"))
    for (token,expansion) in (("panel",allowed),("all",available_methods(threads)),("strategies",strategies))
        token in wanted && (wanted=unique(vcat(filter(!=(token),wanted),expansion)))
    end
    unknown=setdiff(Set(wanted),Set(allowed))
    isempty(unknown) || throw(ArgumentError("methods unavailable at $threads threads: "*join(sort!(collect(unknown)),", ")))
    unique(wanted)
end
end
