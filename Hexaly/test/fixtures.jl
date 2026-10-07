function fixtures()
    P=ReproductionProblems.problem
    distance=[[0.,1.,2.,3.],[1.,0.,1.,2.],[2.,1.,0.,1.],[3.,2.,1.,0.]]
    Dict(
        :tsp=>P(:tsp,Dict("distance"=>[r[1:3] for r in distance[1:3]])),
        :qap=>P(:qap,Dict("distance"=>[[0,2],[2,0]],"flow"=>[[0,3],[4,0]])),
        :cvrp=>P(:cvrp,Dict("distance"=>[r[1:3] for r in distance[1:3]],"demand"=>[0,2,2],"capacity"=>3,"vehicles"=>2)),
        :cvrptw=>P(:cvrptw,Dict("distance"=>[r[1:3] for r in distance[1:3]],"demand"=>[0,2,2],"capacity"=>4,"vehicles"=>2,
            "earliest"=>[0,0,0],"latest"=>[12,3,6],"service"=>[0,1,1])),
        :top=>P(:top,Dict("distance"=>distance,"prize"=>[0,4,5,0],"max_distance"=>4.,"vehicles"=>1)),
        :bpp=>P(:bpp,Dict("weights"=>[[2],[2],[3]],"capacity"=>[4])),
        :bppc=>P(:bppc,Dict("weights"=>[[2],[2],[3]],"capacity"=>[4],"conflicts"=>[[1,2]])),
        :vbp=>P(:vbp,Dict("weights"=>[[1,3],[3,1],[2,2]],"capacity"=>[4,4])),
        :mssc=>P(:mssc,Dict("coordinates"=>[[0.],[2.],[10.]],"clusters"=>2)),
        :rcpsp=>P(:rcpsp,Dict("duration"=>[2,3],"resource_use"=>[[1],[1]],"capacity"=>[1],"precedence"=>Vector{Int}[],"horizon"=>5)),
        :jssp=>P(:jssp,Dict("duration"=>[2,3],"machine"=>[1,1],"precedence"=>Vector{Int}[],"horizon"=>5)),
        :fjsp=>P(:fjsp,Dict("duration"=>[2,3],"alternatives"=>[[[1,2],[2,1]],[[1,3],[2,2]]],"precedence"=>[[1,2]],"horizon"=>5)),
        :salbp=>P(:salbp,Dict("duration"=>[2,2,3],"cycle"=>4,"precedence"=>[[1,3]])),
        :aircraft_landing=>P(:aircraft_landing,Dict("earliest"=>[0,0],"target"=>[2,3],"latest"=>[6,6],
            "separation"=>[[0,2],[3,0]],"early_cost"=>[1.,2.],"late_cost"=>[2.,1.])),
        :car_sequencing=>P(:car_sequencing,Dict("today_count"=>2,"history"=>[3],"colors"=>[1,2,1],"options"=>[[1],[0],[1]],
            "window"=>[2],"limit"=>[1],"priority"=>[1],"max_paint_batch"=>1,"objective_order"=>[1,2,3])),
        :maintenance=>P(:maintenance,Dict("horizon"=>2,"scenario_count"=>[2,2],"alpha"=>.5,"quantile"=>.5,
            "latest_start"=>[2,2],"duration"=>[[1,1],[1,1]],
            "resource_use_by_start"=>[[[[1.]],[[1.]]],[[[1.]],[[1.]]]],
            "risk_by_start"=>[[[[1.,3.]],[[2.,4.]]],[[[3.,1.]],[[4.,2.]]]],
            "capacity_lower"=>[[0.],[0.]],"capacity_upper"=>[[1.],[1.]],"exclusions"=>[[1,2,[1,2]]]))
    )
end
