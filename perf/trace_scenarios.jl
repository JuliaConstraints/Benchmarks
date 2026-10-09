# Bookkeeping qualification uses ordinary dictionary arithmetic as its oracle.
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/TraceCounters.jl"))
function trace_counter_case(parameters)
    repetitions=parameters["repetitions"];mode=parameters["mode"]
    mode in ("integer","mixed","dynamic_assignment") || throw(ArgumentError("unknown trace workload"))
    mixed=mode=="mixed";dynamic_assignment=mode=="dynamic_assignment"
    repetitions>0 || throw(ArgumentError("positive counter workload required"))
    prepare=()->begin
        initial=Dict{String,Any}("summary_evaluations"=>1000,"thread_cpu_seconds"=>-0.,
            "labels"=>["original counts","original floating additions"])
        trace=TraceCounters.Trace(initial)
        values=dynamic_assignment ? Any[mod1(i,3) for i in 1:repetitions] : Any[]
        (;trace,initial,values,retained=TraceCounters.snapshot(trace),operations=Ref(0))
    end
    operation=s->begin
        if dynamic_assignment
            for value in s.values;s.trace["vnd_neighborhood"]=value;end
        else
            for _ in 1:repetitions
                TraceCounters.counter!(s.trace,"summary_evaluations",3)
                mixed && TraceCounters.counter!(s.trace,"thread_cpu_seconds",0.1)
            end
        end
        s.operations[]+=1
        s.trace.integers[dynamic_assignment ? "vnd_neighborhood" : "summary_evaluations"]
    end
    verify=(s,result)->begin
        reference=copy(s.initial)
        for _ in 1:s.operations[]
            if dynamic_assignment
                for value in s.values;reference["vnd_neighborhood"]=value;end
            else
                for _ in 1:repetitions
                    reference["summary_evaluations"]=reference["summary_evaluations"]+3
                    mixed && (reference["thread_cpu_seconds"]=reference["thread_cpu_seconds"]+0.1)
                end
            end
        end
        isequal(TraceCounters.snapshot(s.trace),reference) && isequal(s.retained,s.initial) &&
            result==reference[dynamic_assignment ? "vnd_neighborhood" : "summary_evaluations"]
    end
    (;prepare,operation,verify)
end
