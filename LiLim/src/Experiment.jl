module Experiment
using SHA, TOML, Dates, JuMP
using ..Benchmarks, ..Pilot, ..Hybrid

export run_case, warmup, save_record, digest
digest(path) = bytes2hex(sha256(read(path)))
function save_record(path,record)
    ispath(path) && error("refusing to replace evidence: $path")
    temporary = path*".partial"
    ispath(temporary) && error("partial evidence already exists")
    open(io->TOML.print(io,record;sorted=true),temporary,"w")
    mv(temporary,path)
end

"One equal-resource job. Reading, common insertion and incumbent validation count in its budget."
function run_case(path, method, budget, seed, policy; id=splitext(basename(path))[1])
    method in ("cbls","hybrid_specialized","hybrid_bridged","highs") || throw(ArgumentError("unknown method"))
    isfinite(budget) && budget > 0 || throw(ArgumentError("positive budget required"))
    started = time_ns()
    elapsed() = (time_ns()-started)/1e9
    remaining() = max(0.,budget-elapsed())
    p = read_benchmark(path,:li_lim;id)
    initial = Pilot.insertion(p;starts=policy["insertion_starts"],seed=policy["insertion_seed"])
    initial === nothing && error("common insertion did not produce a feasible start")
    validation = validate_solution(p,initial)
    validation.valid || error("common start failed independent validation")
    initial_seconds = elapsed()
    best = deepcopy(initial)
    best_quality = validation.objective
    eligible = initial_seconds <= budget
    trajectory = Any[]
    eligible && push!(trajectory,Dict("seconds"=>initial_seconds,"vehicles"=>best_quality.vehicles,
        "distance"=>best_quality.distance,"source"=>"common_insertion"))
    trace = Dict{String,Any}()
    callbacks = 0
    rejected_callbacks = 0
    function consider(routes, source)
        validated = validate_solution(p,routes)
        validated.valid || error("incumbent failed original validation")
        quality = validated.objective
        if remaining() > 0 && (quality.vehicles,quality.distance) < (best_quality.vehicles,best_quality.distance)
            best = deepcopy(routes); best_quality = quality
            push!(trajectory,Dict("seconds"=>elapsed(),"vehicles"=>quality.vehicles,
                "distance"=>quality.distance,"source"=>source))
        end
    end
    if remaining() > 0
        if method == "highs"
            build_started = time_ns()
            f = Pilot.model(p;threads=1,seed,seconds=remaining())
            trace["build_seconds"] = (time_ns()-build_started)/1e9
            trace["variables"] = num_variables(f.m)
            trace["constraints"] = num_constraints(f.m;count_variable_in_set_constraints=true)
            start_started = time_ns()
            Pilot.warmstart!(f,initial)
            trace["mip_start_seconds"] = (time_ns()-start_started)/1e9
            Pilot.observe_incumbents!(f,routes->begin
                callbacks += 1
                consider(routes,"highs_callback")
            end;expired=()->remaining()<=0,rejected=error->(rejected_callbacks+=1))
            if remaining() > 0
                set_time_limit_sec(f.m,remaining())
                solution,phases,solve_seconds = Pilot.solve!(f;seconds=remaining())
                trace["phases"] = phases
                trace["solve_seconds"] = solve_seconds
                solution === nothing || consider(solution,"highs_return")
            end
            trace["callbacks"] = callbacks
            trace["invalid_callback_solutions"] = rejected_callbacks
            trace["objective_policy"] = "fleet first; distance only after fleet optimality"
        else
            controller_started = elapsed()
            result = Hybrid.run_cbls(p,initial;seconds=budget,origin_ns=started,seed,
                hybrid=method!="cbls",bridged=method=="hybrid_bridged",
                max_visits=policy["max_visits"],repair_every=policy["repair_every"],
                fragment_seconds=policy["fragment_seconds"],repair_fraction=policy["repair_fraction"])
            trace = result.trace
            # Owned snapshots were validated inside the timed controller.
            # The controller shares the job's exact clock origin. A later
            # event cannot erase an earlier eligible solution.
            for event in result.trace["trajectory"]
                when = event["seconds"]
                if when <= budget
                    checked = validate_solution(p,event["routes"])
                    checked.valid || error("invalid controller snapshot")
                    checked.objective.vehicles==event["vehicles"] &&
                        checked.objective.distance==event["distance"] || error("snapshot objective mismatch")
                    push!(trajectory,Dict("seconds"=>when,"vehicles"=>event["vehicles"],
                        "distance"=>event["distance"],"source"=>"cbls_controller"))
                    best = deepcopy(event["routes"]); best_quality = checked.objective
                end
            end
            trace["controller_started_seconds"] = controller_started
        end
    end
    validate_solution(p,best).valid || error("invalid delivered solution")
    return Dict{String,Any}("instance"=>id,"method"=>method,"seed"=>seed,
        "budget_seconds"=>budget,"wall_seconds"=>elapsed(),"eligible"=>eligible,
        "vehicles"=>best_quality.vehicles,"distance"=>best_quality.distance,
        "initial_seconds"=>initial_seconds,"initial_vehicles"=>validation.objective.vehicles,
        "initial_distance"=>validation.objective.distance,"routes"=>best,
        "routes_source_node_ids"=>[[p.provenance["source_node_ids"][i] for i in route] for route in best],
        "trajectory"=>trajectory,"trace"=>trace,"source_sha256"=>digest(path),
        "finished_utc"=>string(now(UTC)),"threads"=>1)
end

const WARMUP_TEXT = """
3 1 1
0 0 0 0 0 100 0 0 0
1 1 1 1 0 100 0 0 2
2 2 1 -1 0 100 0 1 0
3 -1 1 1 0 100 0 0 4
4 -2 1 -1 0 100 0 3 0
5 0 10 1 0 100 0 0 6
6 0 11 -1 0 100 0 5 0
"""

function warmup(policy)
    # Exercise the actual wrapper and callback closure types on a synthetic
    # instance; remove its temporary reader input automatically.
    mktemp() do path,io
        write(io,WARMUP_TEXT); close(io)
        for method in ("cbls","hybrid_specialized","hybrid_bridged","highs")
            run_case(path,method,2.,41,policy;id="synthetic-warmup")
        end
    end
    nothing
end
end
