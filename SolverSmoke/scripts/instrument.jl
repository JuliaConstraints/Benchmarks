include("activate.jl")
using SHA,TOML
# Only private vendor copies. Fail closed when upstream hook anchors change.
function patchfile(relative,marker,transform)
    path=projectdir("vendor",relative);text=read(path,String)
    occursin(marker,text) && return
    revised=transform(text)
    revised!=text || error("Instrumentation anchor absent: $relative")
    write(path,revised)
end
patchfile("LocalSearchSolvers/src/pool.jl","BENCHMARK_INCUMBENT_OBSERVER",s->begin
    anchor="        @atomic :release s.pool = replacement"
    count(anchor,s)==1 || error("LSS pool anchor changed")
    "# Optional benchmark-only observer. Set before solve; clear after all workers join.\nconst BENCHMARK_INCUMBENT_OBSERVER = Ref{Any}(nothing)\n" *
    replace(s,anchor=>"        observer = BENCHMARK_INCUMBENT_OBSERVER[]\n        if observer !== nothing && is_solution(candidate)\n            observer(get_value(candidate), get_values(candidate))\n        end\n"*anchor)
end)
patchfile("JuLS/src/model/model.jl","BENCHMARK_INCUMBENT_OBSERVER",s->begin
    anchor="        model.best_solution = copy(model.current_solution)"
    count(anchor,s)==1 || error("JuLS incumbent anchor changed")
    "# Optional benchmark-only observer; disabled outside instrumented runs.\nconst BENCHMARK_INCUMBENT_OBSERVER = Ref{Any}(nothing)\n" * replace(s,anchor=>anchor*"\n        observer = BENCHMARK_INCUMBENT_OBSERVER[]\n        observer === nothing || observer(model.best_solution)")
end)
patchfile("ghost-source/include/search_unit.hpp","BENCHMARK_GHOST_INCUMBENT",s->begin
    # Instrument only accepted best objective snapshots, including initialization.
    pattern=r"(data\.best_opt_cost = data\.current_opt_cost;\s*std::transform\( model\.variables\.begin\(\),\s*model\.variables\.end\(\),\s*final_solution\.begin\(\),\s*\[&\]\(auto& var\)\{ return var\.get_value\(\); \} \);)"
    length(collect(eachmatch(pattern,s)))==3 || error("GHOST incumbent anchors changed")
    prefix="#ifndef BENCHMARK_GHOST_INCUMBENT\n#define BENCHMARK_GHOST_INCUMBENT(cost, values) ((void)0)\n#endif\n"
    prefix*replace(s,pattern=>m->m*"\n                        BENCHMARK_GHOST_INCUMBENT(data.best_opt_cost, final_solution);")
end)
cp(projectdir("vendor","ghost-source","include","search_unit.hpp"),
   projectdir("vendor","ghost-source","headers","ghost","search_unit.hpp");force=true)
paths=["LocalSearchSolvers/src/pool.jl","JuLS/src/model/model.jl","ghost-source/include/search_unit.hpp"]
open(projectdir("instrumentation.toml"),"w") do io
    TOML.print(io,Dict("schema"=>"vendor-instrumentation/1","files"=>Dict(p=>bytes2hex(sha256(read(projectdir("vendor",p)))) for p in paths));sorted=true)
end
