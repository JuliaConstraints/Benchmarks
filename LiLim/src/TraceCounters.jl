"Private numeric trace storage with ordinary dictionary values at observation boundaries."
module TraceCounters

mutable struct Trace <: AbstractDict{String,Any}
    integers::Dict{String,Int}
    scalars::Dict{String,Float64}
    values::Dict{String,Any}
end
Trace()=Trace(Dict{String,Int}(),Dict{String,Float64}(),Dict{String,Any}())
function Trace(source::AbstractDict)
    trace=Trace()
    for (key,value) in source;trace[key]=value;end
    trace
end

Base.length(trace::Trace)=length(trace.integers)+length(trace.scalars)+length(trace.values)
Base.haskey(trace::Trace,key)=haskey(trace.integers,key)||haskey(trace.scalars,key)||haskey(trace.values,key)
function Base.getindex(trace::Trace,key)
    haskey(trace.integers,key) && return trace.integers[key]
    haskey(trace.scalars,key) && return trace.scalars[key]
    trace.values[key]
end
Base.get(trace::Trace,key,default)=haskey(trace,key) ? trace[key] : default
Base.get(f::Union{Function,Type},trace::Trace,key)=haskey(trace,key) ? trace[key] : f()
function Base.setindex!(trace::Trace,value,key::AbstractString)
    name=String(key)
    if value isa Int
        delete!(trace.scalars,name);delete!(trace.values,name);trace.integers[name]=value
    elseif value isa Float64
        delete!(trace.integers,name);delete!(trace.values,name);trace.scalars[name]=value
    else
        delete!(trace.integers,name);delete!(trace.scalars,name);trace.values[name]=value
    end
    trace
end
function Base.delete!(trace::Trace,key)
    delete!(trace.integers,key);delete!(trace.scalars,key);delete!(trace.values,key)
    trace
end
function Base.empty!(trace::Trace)
    empty!(trace.integers);empty!(trace.scalars);empty!(trace.values)
    trace
end
Base.copy(trace::Trace)=Trace(copy(trace.integers),copy(trace.scalars),copy(trace.values))
Base.empty(trace::Trace)=Trace()
function Base.iterate(trace::Trace,state=(1,nothing))
    part,cursor=state
    while part<=3
        dictionary=part==1 ? trace.integers : part==2 ? trace.scalars : trace.values
        result=cursor===nothing ? iterate(dictionary) : iterate(dictionary,cursor)
        if result!==nothing
            pair,next=result
            return (Pair{String,Any}(first(pair),last(pair)),(part,next))
        end
        part+=1;cursor=nothing
    end
    nothing
end

"Update counters without boxing each ordinary integer increment; unsupported arithmetic keeps its original path."
function counter!(trace::Trace,key::String,amount::Int=1)
    previous=get(trace.integers,key,0)
    if previous!=0 || haskey(trace.integers,key)
        trace.integers[key]=previous+amount
    elseif haskey(trace.scalars,key)
        trace.scalars[key]+=amount
    elseif haskey(trace.values,key)
        trace.values[key]+=amount
    else
        trace.integers[key]=amount
    end
    nothing
end
function counter!(trace::Trace,key::String,amount::Float64)
    if haskey(trace.integers,key)
        value=trace.integers[key]+amount
        delete!(trace.integers,key);trace.scalars[key]=value
    elseif haskey(trace.values,key)
        trace.values[key]+=amount
    else
        trace.scalars[key]=get(trace.scalars,key,0.)+amount
    end
    nothing
end
function counter!(trace::Trace,key,amount)
    trace[key]=get(trace,key,0)+amount
    nothing
end

"An ordinary dictionary copy for export; numeric updates cannot mutate retained observations."
snapshot(trace::Trace)=Dict{String,Any}(trace)

end
