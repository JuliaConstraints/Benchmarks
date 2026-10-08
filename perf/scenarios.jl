using Random
Base.include(@__MODULE__,joinpath(@__DIR__,"../LiLim/src/QUBOGuidance.jl"))

"Numerical kernels share one explicit sparse interaction model and an independent energy oracle."
function kernel_case(parameters)
    n=parameters["variables"];depth=parameters["depth"];iterations=parameters["repetitions"]
    operation=parameters["operation"]
    prepare=()->begin
        g=QUBOGuidance.structural_guide(fill(1:8,n),[(i,mod1(i+1,n),1.) for i in 1:n])
        w=QUBOGuidance.Workspace(g);other=QUBOGuidance.Workspace(g)
        values=[mod1(i,8) for i in 1:n];candidate=copy(values)
        QUBOGuidance.refresh!(w,g,values)
        (;g,w,other,values,candidate,rng=Xoshiro(41),ids=(1,2),replacement=(3,4))
    end
    work=state->begin
        g,w=state.g,state.w;result=0.0
        if operation=="energy"
            for _ in 1:iterations;result=QUBOGuidance.energy(g,w);end
        elseif operation=="delta"
            for _ in 1:iterations;result=QUBOGuidance.delta!(w,g,state.ids,state.replacement);end
        elseif operation=="full_move"
            for _ in 1:iterations
                copyto!(state.candidate,state.values)
                for (i,v) in zip(state.ids,state.replacement);state.candidate[i]=v;end
                QUBOGuidance.refresh!(state.other,g,state.candidate)
                result=QUBOGuidance.energy(g,state.other)-QUBOGuidance.energy(g,w)
            end
        elseif operation=="scope"
            for _ in 1:iterations
                QUBOGuidance.scope!(w,g,state.values,depth,state.rng;mode="conditional");result=length(w.chosen)
            end
        elseif operation=="proposal"
            for _ in 1:iterations
                result=QUBOGuidance.proposal!(w,g,state.values,depth,state.rng;mode="conditional").delta
            end
        else;throw(ArgumentError("unknown guide workload"));end
        result
    end
    function polynomial(g,values)
        z=[Float64(values[i]==v) for (i,v) in g.atoms]
        sum(g.linear.*z)+sum(g.coefficient[k]*z[g.left[k]]*z[g.right[k]] for k in eachindex(g.coefficient))
    end
    verify=(state,result)->begin
        isfinite(result) || return false
        if operation=="energy";return result≈polynomial(state.g,state.values)
        elseif operation in ("delta","full_move")
            candidate=copy(state.values);candidate[collect(state.ids)]=collect(state.replacement)
            return result≈polynomial(state.g,candidate)-polynomial(state.g,state.values)
        elseif operation=="scope";return result==min(depth,n) && allunique(state.w.chosen)
        else
            candidate=copy(state.values);candidate[state.w.chosen]=state.w.replacements
            return result<=1e-10 && isapprox(result,polynomial(state.g,candidate)-polynomial(state.g,state.values);atol=1e-10)
        end
    end
    (;prepare,operation=work,verify)
end

"Owned classical scoring callbacks; original validators check every prepared input."
function classical_scoring_case(parameters)
    isdefined(@__MODULE__,:HexalyReproduction) || Base.include(@__MODULE__,joinpath(@__DIR__,"../Hexaly/src/Reproduction.jl"))
    if !isdefined(@__MODULE__,:ClassicalScoringFixtures)
        fixtures_module=Module(:ClassicalScoringFixtures)
        reproduction=Base.invokelatest(getfield,@__MODULE__,:HexalyReproduction)
        problems=Base.invokelatest(getfield,reproduction,:ReproductionProblems)
        Core.eval(fixtures_module,:(const ReproductionProblems=$problems))
        Base.include(fixtures_module,joinpath(@__DIR__,"../Hexaly/test/fixtures.jl"))
        Core.eval(@__MODULE__,:(const ClassicalScoringFixtures=$fixtures_module))
    end
    Base.invokelatest(_classical_scoring_case,parameters)
end
function _classical_scoring_case(parameters)
    S=HexalyReproduction.ReproductionScoring;P=HexalyReproduction.ReproductionProblems
    family=Symbol(parameters["family"]);kind=Symbol(parameters["backend"])
    repetitions=parameters["repetitions"]
    # The bank may define new Julia methods. Create it before the runtime enters
    # the lifecycle; each prepare still creates private scoring buffers.
    Base.invokelatest(S.prepare_backend,kind)
    prepare=()->begin
        p=ClassicalScoringFixtures.fixtures()[family];ds=P.domains(p)
        inputs=(P.initial(p),[first(d) for d in ds],[last(d) for d in ds])
        backend=S.prepare_backend(kind)
        expected=Tuple(begin
            e=Base.invokelatest(S.error_value,backend,p,x)
            iszero(e)==P.validate(p,x).valid || error("scoring zero set differs from original problem")
            e
        end for x in inputs)
        (;p,backend,inputs,expected)
    end
    work=s->_classical_scoring_operation(s,repetitions)
    verify=(s,result)->isapprox(result,repetitions*sum(s.expected);atol=1e-8) &&
        all(i->iszero(s.expected[i])==P.validate(s.p,s.inputs[i]).valid,eachindex(s.inputs))
    (;prepare,operation=work,verify)
end
function _classical_scoring_operation(state,repetitions)
    checksum=0.
    for _ in 1:repetitions,x in state.inputs
        checksum+=HexalyReproduction.ReproductionScoring.error_value(state.backend,state.p,x)
    end
    checksum
end

"Real CBLS or typed MetaStrategist execution; fixed steps and fresh owned state per observation."
function solver_case(parameters)
    isdefined(@__MODULE__,:HexalyReproduction) || Base.include(@__MODULE__,joinpath(@__DIR__,"../Hexaly/src/Reproduction.jl"))
    Base.invokelatest(_solver_case,parameters)
end
function _solver_case(parameters)
    S=HexalyReproduction.ReproductionSolvers;P=HexalyReproduction.ReproductionProblems
    method=parameters["method"];width=parameters["width"];steps=parameters["steps"];seed=parameters["seed"]
    width<=Threads.nthreads() || throw(ArgumentError("one Julia thread per owned lane required"))
    p=P.problem(:bpp,Dict("weights"=>[[2],[2],[3]],"capacity"=>[4]))
    recipes=S.StrategyPanel.allocation(method,width)
    workers=[(;kind=l.backend==:icn_fused_all ? :icn_fused : l.backend,policy=l.policy,overrides=l.overrides,
        hybrid=l.hybrid,max_visits=l.max_visits,repair_every=l.repair_every,fragment_seconds=l.fragment_seconds,
        repair_fraction=l.repair_fraction,repair_mode=l.repair_mode,lp_solver=l.lp_solver,mip_lp_solver=l.mip_lp_solver,
        radius=l.radius,fragment_selection=l.fragment_selection,guide_mode=l.guide_mode,guide_depth=l.guide_depth,
        guide_every=l.guide_every,guide_exploration=l.guide_exploration,guide_fraction=l.guide_fraction,warm_start=true) for l in recipes]
    prepare=()->Tuple(S.prepare_cbls(p;worker...,seed=seed+i-1) for (i,worker) in enumerate(workers))
    work=lanes->S.portfolio(p;workers,seconds=60.,seed,max_steps=steps,prepared_lanes=lanes)
    verify=(lanes,results)->length(results)==width && all(r->r["steps"]<=steps &&
        all(e->P.validate(p,e["values"]).valid,r["trajectory"]),results)
    (;prepare,operation=work,verify)
end
