"Shared bounded HiGHS fragment policies; fractional LP points are never incumbents."
module ROFragments
using JuMP
import HiGHS, MathOptInterface as MOI
export optimize_fragment!

function optimize_fragment!(m;remaining,assignment=Dict{VariableRef,Float64}(),
        mode="mip",lp_solver="simplex",mip_lp_solver="choose",radius=4,seed=41,trace=Dict{String,Any}())
    mode in ("mip","rins","local_branching") || throw(ArgumentError("unknown RO repair"))
    lp_solver in ("simplex","ipx","hipo") && mip_lp_solver in ("choose","simplex","ipx","hipo") ||
        throw(ArgumentError("unknown LP algorithm"))
    radius>0 || throw(ArgumentError("positive neighborhood radius required"))
    set_optimizer(m,HiGHS.Optimizer);set_silent(m);set_attribute(m,MOI.NumberOfThreads(),1)
    set_attribute(m,"random_seed",seed)
    for (v,x) in assignment;set_start_value(v,x);end
    trace["mode"]=mode;trace["lp_solver"]=lp_solver;trace["mip_lp_solver"]=mip_lp_solver
    trace["threads"]=1;trace["bound_scope"]="restricted_fragment_not_global_original_bound"
    trace["lp_seconds"]=0.;trace["rins_fixed_variables"]=0
    if mode=="rins" && remaining()>0
        started=time_ns();integer=[v for v in all_variables(m) if is_binary(v)||is_integer(v)]
        undo=relax_integrality(m);fixings=Pair{VariableRef,Float64}[]
        try
            set_attribute(m,"solver",lp_solver);set_time_limit_sec(m,max(1e-6,.30remaining()))
            optimize!(m);trace["lp_status"]=string(termination_status(m))
            # Only an optimal LP solution guides fixing; incomplete LPs leave the MIP free.
            if termination_status(m)==MOI.OPTIMAL && has_values(m)
                trace["lp_objective"]=objective_value(m)
                for v in integer
                    haskey(assignment,v) && !is_fixed(v) && abs(value(v)-assignment[v])<=1e-6 &&
                        push!(fixings,v=>assignment[v])
                end
            end
        finally
            undo();set_attribute(m,"solver","choose")
        end
        for (v,x) in fixings;fix(v,x;force=true);end
        trace["rins_fixed_variables"]=length(fixings);trace["lp_seconds"]=(time_ns()-started)/1e9
    elseif mode=="local_branching"
        binaries=[v=>x for (v,x) in assignment if is_binary(v) && !is_fixed(v)]
        if !isempty(binaries)
            @constraint(m,sum(x>0.5 ? 1-v : v for (v,x) in binaries)<=radius)
            trace["neighborhood_metric"]="binary_hamming"
        else
            integers=[v=>x for (v,x) in assignment if is_integer(v) && !is_fixed(v)]
            t=@variable(m,[1:length(integers)],lower_bound=0)
            for (i,(v,x)) in enumerate(integers);@constraint(m,t[i]>=v-x);@constraint(m,t[i]>=x-v);end
            @constraint(m,sum(t)<=radius);trace["neighborhood_metric"]="integer_L1"
        end
    end
    remaining()>0 || return false
    set_attribute(m,"solver","choose");set_attribute(m,"mip_lp_solver",mip_lp_solver)
    set_time_limit_sec(m,remaining());started=time_ns();optimize!(m)
    trace["mip_seconds"]=(time_ns()-started)/1e9;trace["mip_status"]=string(termination_status(m))
    has_values(m) && remaining()>0
end
end
