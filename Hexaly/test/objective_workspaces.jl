const OWNED_OBJECTIVE_FAMILIES=(:tsp,:qap,:cvrp,:cvrptw,:top,:mssc,:car_sequencing,:maintenance)

function objective_outcome(callback,p,x)
    try
        (:value,callback(p,x))
    catch caught
        (:exception,typeof(caught))
    end
end

@testset "Owned objectives retain original values on infeasible domain assignments" begin
    for family in OWNED_OBJECTIVE_FAMILIES
        p=deepcopy(CASES[family]);a=prepare_backend(:direct);b=prepare_backend(:direct)
        actual=(p,x)->search_objective_value(a,p,x)
        for tuple in Iterators.product(domains(p)...)
            x=collect(tuple);saved=copy(x)
            @test isequal(actual(p,x),objective_value(p,x))
            @test isequal(search_objective_value(b,p,x),objective_value(p,x))
            @test x==saved
        end
        for x in (Int[],fill(NaN,length(domains(p))),fill(0,length(domains(p))),
                  fill(0.5,length(domains(p))),fill(Inf,length(domains(p))))
            @test isequal(objective_outcome(actual,p,x),objective_outcome(objective_value,p,x))
        end
        @test a.workspace!==b.workspace
        @test a.workspace.integers!==b.workspace.integers
    end
end

@testset "MSSC dense reductions preserve exact rounding and owned bounded caches" begin
    rng=Xoshiro(814);backend=prepare_backend(:direct);other=prepare_backend(:direct)
    for n in (3,7,17,64),dimension in (1,2,5),clusters in (1,2,3)
        p=problem(:mssc,Dict("coordinates"=>randn(rng,n,dimension),"clusters"=>clusters))
        for _ in 1:24
            x=rand(rng,1:clusters,n);expected=objective_value(p,x)
            @test isequal(search_objective_value(backend,p,x),expected)
            @test isequal(search_objective_value(other,p,x),expected)
            @test length(backend.workspace.objective_workspace.coordinate_cache)<=8
        end
        left=backend.workspace.objective_workspace;right=other.workspace.objective_workspace
        @test left!==right
        @test left.coordinates!==right.coordinates
        @test left.ids!==right.ids
        @test left.center!==right.center
        @test allunique(objectid(v) for v in left.coordinate_cache)
        p.data["coordinates"].+=.125
        x=first.(domains(p))
        @test isequal(search_objective_value(backend,p,x),objective_value(p,x))
    end
end

@testset "Edited data, domains and unsupported arithmetic retain original behavior" begin
    for family in OWNED_OBJECTIVE_FAMILIES
        p=deepcopy(CASES[family]);backend=prepare_backend(:direct)
        actual=(p,x)->search_objective_value(backend,p,x)
        x=initial(p);actual(p,x)
        if family in (:tsp,:qap,:cvrp,:cvrptw,:top)
            p.data["distance"].+=1
            @test isequal(actual(p,x),objective_value(p,x))
            p.data["distance"]=BigFloat.(p.data["distance"])
            @test isequal(objective_outcome(actual,p,x),objective_outcome(objective_value,p,x))
            family==:qap && (p.data["flow"]=BigInt.(p.data["flow"]))
        elseif family==:mssc
            p.data["coordinates"]=BigFloat.(p.data["coordinates"])
            @test isequal(actual(p,x),objective_value(p,x))
            p.data["clusters"]+=1;x=fill(p.data["clusters"],length(x))
        elseif family==:car_sequencing
            p.data["history"]=reverse(p.data["history"])
            p.data["window"][1]+=2
            @test isequal(actual(p,x),objective_value(p,x))
            p.data["today_count"]-=1;resize!(x,p.data["today_count"])
        else
            p.data["risk_by_start"][1][x[1]][1].+=.25
            @test isequal(actual(p,x),objective_value(p,x))
            p.data["latest_start"][1]=1
        end
        @test isequal(objective_outcome(actual,p,x),objective_outcome(objective_value,p,x))
        if family in (:cvrp,:cvrptw,:top)
            p.data["vehicles"]+=1;x[length(x)÷2+1:end].=p.data["vehicles"]
            @test isequal(objective_outcome(actual,p,x),objective_outcome(objective_value,p,x))
        end
    end
    for value in (Int64(2)^40,typemax(Int64),UInt64(2)^63)
        p=deepcopy(CASES[:qap]);p.data["distance"]=fill(value,2,2);p.data["flow"]=fill(value,2,2)
        backend=prepare_backend(:direct);actual=(p,x)->search_objective_value(backend,p,x)
        @test objective_outcome(actual,p,[1,2])==objective_outcome(objective_value,p,[1,2])
    end
end

@testset "Maintenance scenarios are refilled and privately owned" begin
    p=deepcopy(CASES[:maintenance]);a=prepare_backend(:direct);b=prepare_backend(:direct)
    for x in ([1,1],[1,2],[2,1],[2,2],[1,1]),quantile in (0.,.25,.5,.75,1.)
        p.data["quantile"]=quantile
        @test isequal(search_objective_value(a,p,x),objective_value(p,x))
        @test isequal(search_objective_value(b,p,x),objective_value(p,x))
    end
    left=a.workspace.objective_workspace;right=b.workspace.objective_workspace
    @test left.risk!==right.risk
    @test left.means!==right.means
    @test left.excess!==right.excess
    @test left.sort_scratch!==right.sort_scratch
    @test all(left.risk[i]!==right.risk[i] for i in eachindex(left.risk))
    @test allunique(objectid(v) for v in left.risk)
end

@testset "Large maintenance scenarios retain original quantiles and reuse sort scratch" begin
    rng=Xoshiro(842);p=deepcopy(CASES[:maintenance]);backend=prepare_backend(:direct)
    for count in (17,257,1024,17,1024)
        p.data["scenario_count"].=count
        for intervention in p.data["risk_by_start"],start in intervention
            start[1]=randn(rng,count)
        end
        for x in ([1,1],[1,2],[2,2]),quantile in (0.,.5,1.)
            p.data["quantile"]=quantile
            @test isequal(search_objective_value(backend,p,x),objective_value(p,x))
        end
        function measured_risk(backend,p,x)
            search_objective_value(backend,p,x)
            @allocated for _ in 1:32;search_objective_value(backend,p,x);end
        end
        measured_risk(backend,p,[1,2])
        @test measured_risk(backend,p,[1,2])==0
    end
    p.data["scenario_count"].=4
    for special in ([0.,-0.,Inf,1.],[NaN,0.,-Inf,1.],[3.,3.,-2.,-2.])
        for intervention in p.data["risk_by_start"],start in intervention;start[1]=copy(special);end
        for quantile in (0.,.25,.5,.75,1.)
            p.data["quantile"]=quantile
            @test isequal(search_objective_value(backend,p,[1,2]),objective_value(p,[1,2]))
        end
    end
end
