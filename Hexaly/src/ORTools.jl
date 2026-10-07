module ReproductionORTools
using JuMP,TOML
import MathOptInterface as MOI
using ..ReproductionProblems, ..ReproductionSolvers
include("../../LiLim/src/NativeSolvers.jl")
export solve_ortools,linear_request
exactint(x)=isfinite(x) && isinteger(x) && abs(x)<=2.0^53 ? Int64(x) : throw(ArgumentError("CP-SAT linear constraints require exact integer data; no scaling or rounding is applied"))
function linear_request(model;seconds,threads,seed)
    vars=all_variables(model);index=Dict(JuMP.index(v)=>i for(i,v)in enumerate(vars))
    bounds=[Dict{String,Int64}() for _ in vars];constraints=Dict{String,Any}[]
    for (F,S) in list_of_constraint_types(model),ref in all_constraints(model,F,S)
        c=constraint_object(ref);func=c.func;set=c.set
        if func isa VariableRef
            i=index[JuMP.index(func)];b=bounds[i]
            if set isa MOI.ZeroOne;b["lower"]=0;b["upper"]=1
            elseif set isa MOI.Integer
            elseif set isa MOI.GreaterThan;b["lower"]=exactint(set.lower)
            elseif set isa MOI.LessThan;b["upper"]=exactint(set.upper)
            elseif set isa MOI.EqualTo;b["lower"]=b["upper"]=exactint(set.value)
            elseif set isa MOI.Interval;b["lower"]=exactint(set.lower);b["upper"]=exactint(set.upper)
            else;throw(ArgumentError("Unsupported variable set in CP-SAT interchange"));end
        elseif func isa GenericAffExpr
            row=Dict{String,Any}("indices"=>[index[JuMP.index(v)] for v in keys(func.terms)],
                "coefficients"=>exactint.(collect(values(func.terms))))
            constant=exactint(func.constant)
            if set isa MOI.GreaterThan;row["lower"]=exactint(set.lower)-constant
            elseif set isa MOI.LessThan;row["upper"]=exactint(set.upper)-constant
            elseif set isa MOI.EqualTo;row["lower"]=row["upper"]=exactint(set.value)-constant
            else;throw(ArgumentError("Unsupported linear set in CP-SAT interchange"));end
            push!(constraints,row)
        else;throw(ArgumentError("Nonlinear model cannot pass through the linear CP-SAT adapter"));end
    end
    all(v->is_integer(v)||is_binary(v),vars) || throw(ArgumentError("Continuous decisions are out of scope"))
    all(b->haskey(b,"lower") && haskey(b,"upper"),bounds) || throw(ArgumentError("Finite CP-SAT domains required"))
    objective=objective_function(model)
    objective isa VariableRef && (objective=AffExpr(0.,objective=>1.))
    objective isa GenericAffExpr || throw(ArgumentError("Linear objective required"))
    Dict("variables"=>bounds,"constraints"=>constraints,"seconds"=>seconds,"threads"=>threads,"seed"=>seed,
        "objective"=>Dict("indices"=>[index[JuMP.index(v)] for v in keys(objective.terms)],
            "coefficients"=>collect(values(objective.terms)),"constant"=>objective.constant))
end
function solve_ortools(p;seconds=1.,threads=1,seed=41,python=nothing,max_cells=250_000)
    root=normpath(joinpath(@__DIR__,"../.."));python===nothing && (python=NativeSolvers.default_python(root))
    identity=NativeSolvers.resolve_ortools(python;root)
    built=mip_model(p;max_cells);request=linear_request(built.model;seconds,threads,seed)
    mktempdir() do directory
        input=joinpath(directory,"request.toml");output=joinpath(directory,"result.toml")
        open(io->TOML.print(io,request),input,"w")
        script=joinpath(root,"Hexaly/native/ortools/linear.py")
        r=NativeSolvers.capture(NativeSolvers.python_command(identity,script,input,output);timeout=seconds+60)
        r.timed_out && error("OR-Tools model timed out outside its solve budget")
        r.code==0 && isfile(output) || error("OR-Tools CP-SAT adapter failed; native diagnostics are kept private")
        result=TOML.parsefile(output);native_values=result["values"]
        if !isempty(native_values)
            vars=all_variables(built.model)
            # Decode using the same variable indexing as the exported linear formulation.
            if p.family in (:bpp,:bppc,:vbp,:salbp)
                n=length(domains(p));B=last(first(domains(p)));matrix=reshape(native_values[1:n*B],n,B)
                decoded=[argmax(matrix[i,:]) for i in 1:n]
            elseif p.family in (:rcpsp,:jssp,:aircraft_landing)
                decoded=Int.(native_values[1:length(domains(p))])
            elseif p.family==:fjsp
                n=length(p.data["duration"]);offset=n+1;choices=Int[]
                for alternatives in p.data["alternatives"]
                    push!(choices,argmax(native_values[offset+1:offset+length(alternatives)]));offset+=length(alternatives)
                end
                decoded=vcat(Int.(native_values[1:n]),choices)
            else;error("Missing original CP-SAT solution decoder");end
            validate(p,decoded).valid || error("OR-Tools solution fails original validator")
            result["values"]=decoded
        end
        result["ortools_version"]=identity["ortools_version"];result
    end
end
end
