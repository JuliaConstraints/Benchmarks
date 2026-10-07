#!/usr/bin/env python3
"""OR-Tools 9.14 Routing GLS and generalized CP-SAT for Li-Lim PDPTW.

This runner uses OR-Tools' official Python RoutingModel because that is the
interface used by the public Hexaly comparison. Install the pinned dependency
from requirements.txt in an isolated Python environment. Every exported route
and every captured incumbent is rechecked by the original Julia validator.

The default Routing search remains single-threaded. Parallel Routing uses
independent processes with distinct GLS coefficients. The CP-SAT profile uses
the official generalized RoutingModel translator, with CP local search disabled.
Its workers share one explicitly bounded CPU allocation. Both profiles use the
same conservative integer model and original Julia solution validation.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import sys
import time

EXPECTED_VERSION = "9.14.6206"
DISTANCE_SCALE = 1_000_000
TIME_SCALE = 10_000
SCHEMA = "li-lim-ortools-native/1"
CPSAT_SCHEMA = "li-lim-ortools-cpsat-native/1"


def parse_exchange(path: pathlib.Path):
    tokens = iter(path.read_text(encoding="utf-8").split())
    try:
        schema = next(tokens)
        if schema != "lilim-common-start/1":
            raise ValueError(f"unsupported exchange schema: {schema}")
        node_count, capacity, fleet = int(next(tokens)), int(next(tokens)), int(next(tokens))
        if node_count < 2 or capacity <= 0 or fleet <= 0:
            raise ValueError("invalid node, capacity, or fleet count")
        nodes = []
        for expected_id in range(1, node_count + 1):
            node_id = int(next(tokens))
            if node_id != expected_id:
                raise ValueError("exchange nodes are not in canonical order")
            x, y = float(next(tokens)), float(next(tokens))
            demand = int(next(tokens))
            earliest, latest, service = (float(next(tokens)), float(next(tokens)), float(next(tokens)))
            pickup = int(next(tokens))
            nodes.append({
                "id": node_id, "x": x, "y": y, "demand": demand,
                "earliest": earliest, "latest": latest, "service": service,
                "pickup": pickup,
            })
        start_routes = []
        for _ in range(fleet):
            count = int(next(tokens))
            route = [int(next(tokens)) for _ in range(count)]
            if any(node < 2 or node > node_count for node in route):
                raise ValueError("common-start route contains a non-customer ID")
            start_routes.append(route)
        try:
            next(tokens)
            raise ValueError("unexpected trailing input")
        except StopIteration:
            pass
    except StopIteration as error:
        raise ValueError("truncated common-start exchange") from error

    for delivery in nodes[1:]:
        pickup_id = delivery["pickup"]
        if pickup_id:
            if pickup_id < 2 or pickup_id > node_count:
                raise ValueError(f"invalid pickup reference for node {delivery['id']}")
            pickup = nodes[pickup_id - 1]
            if pickup["demand"] <= 0 or delivery["demand"] >= 0:
                raise ValueError("pickup/delivery demand signs are inconsistent")
            if pickup["demand"] + delivery["demand"] != 0:
                raise ValueError("pickup and delivery quantities differ")

    return nodes, capacity, fleet, start_routes


def distance_matrix(nodes):
    return [
        [math.hypot(a["x"] - b["x"], a["y"] - b["y"]) for b in nodes]
        for a in nodes
    ]


def route_quality(routes, distances):
    used = 0
    total_distance = 0.0
    for route in routes:
        if not route:
            continue
        used += 1
        sequence = [0, *[node_id - 1 for node_id in route], 0]
        total_distance += sum(distances[a][b] for a, b in zip(sequence, sequence[1:]))
    return used, total_distance


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("nonfinite result value")
        return repr(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, str):
        return quote(value)
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


def write_result(path, fields, events, schema=SCHEMA):
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(f"schema = {quote(schema)}\n")
        for key, value in fields.items():
            stream.write(f"{key} = {toml_value(value)}\n")
        stream.write("\n")
        for event in events:
            stream.write("[[trajectory]]\n")
            stream.write(f"seconds = {event['seconds']!r}\n")
            stream.write(f"vehicles = {event['vehicles']}\n")
            stream.write(f"distance = {event['distance']!r}\n")
            stream.write("routes = [")
            stream.write(", ".join("[" + ", ".join(map(str, route)) + "]" for route in event["routes"]))
            stream.write("]\n\n")


def run(args):
    from ortools import __version__ as ortools_version
    from ortools.constraint_solver import pywrapcp, routing_enums_pb2

    if ortools_version != EXPECTED_VERSION:
        raise RuntimeError(f"expected OR-Tools {EXPECTED_VERSION}, found {ortools_version}")
    nodes, capacity, fleet, start_routes = parse_exchange(args.input)
    distances = distance_matrix(nodes)
    manager = pywrapcp.RoutingIndexManager(len(nodes), fleet, 0)
    routing = pywrapcp.RoutingModel(manager)

    def distance_callback(from_index, to_index):
        start = manager.IndexToNode(from_index)
        end = manager.IndexToNode(to_index)
        return int(round(distances[start][end] * DISTANCE_SCALE))

    distance_callback_index = routing.RegisterTransitCallback(distance_callback)
    routing.SetArcCostEvaluatorOfAllVehicles(distance_callback_index)

    max_edge_cost = max(
        int(math.ceil(value * DISTANCE_SCALE)) for row in distances for value in row
    )
    lexicographic_vehicle_penalty = max_edge_cost * (len(nodes) + fleet) + 1
    routing.SetFixedCostOfAllVehicles(lexicographic_vehicle_penalty)

    def demand_callback(from_index):
        node = manager.IndexToNode(from_index)
        return nodes[node]["demand"]

    demand_callback_index = routing.RegisterUnaryTransitCallback(demand_callback)
    routing.AddDimensionWithVehicleCapacity(
        demand_callback_index,
        0,
        [capacity] * fleet,
        True,
        "Capacity",
    )

    def time_callback(from_index, to_index):
        start = manager.IndexToNode(from_index)
        end = manager.IndexToNode(to_index)
        transit = nodes[start]["service"] + distances[start][end]
        return int(math.ceil(transit * TIME_SCALE - 1e-9))

    time_callback_index = routing.RegisterTransitCallback(time_callback)
    largest_due = max(node["latest"] for node in nodes)
    total_service = sum(node["service"] for node in nodes)
    max_edge = max(max(row) for row in distances)
    horizon = int(math.ceil(
        (largest_due + total_service + (len(nodes) + fleet) * max_edge + 1) * TIME_SCALE
    ))
    routing.AddDimension(time_callback_index, horizon, horizon, False, "Time")
    time_dimension = routing.GetDimensionOrDie("Time")
    depot_earliest = int(math.ceil(nodes[0]["earliest"] * TIME_SCALE - 1e-9))
    depot_latest = int(math.floor(nodes[0]["latest"] * TIME_SCALE + 1e-9))
    for vehicle in range(fleet):
        time_dimension.CumulVar(routing.Start(vehicle)).SetRange(depot_earliest, depot_latest)
        time_dimension.CumulVar(routing.End(vehicle)).SetRange(0, depot_latest)
    for node in nodes[1:]:
        index = manager.NodeToIndex(node["id"] - 1)
        earliest = int(math.ceil(node["earliest"] * TIME_SCALE - 1e-9))
        latest = int(math.floor(node["latest"] * TIME_SCALE + 1e-9))
        time_dimension.CumulVar(index).SetRange(earliest, latest)

    solver = routing.solver()
    for delivery in nodes[1:]:
        if delivery["pickup"] == 0:
            continue
        pickup_index = manager.NodeToIndex(delivery["pickup"] - 1)
        delivery_index = manager.NodeToIndex(delivery["id"] - 1)
        routing.AddPickupAndDelivery(pickup_index, delivery_index)
        solver.Add(routing.VehicleVar(pickup_index) == routing.VehicleVar(delivery_index))
        solver.Add(time_dimension.CumulVar(pickup_index) <= time_dimension.CumulVar(delivery_index))

    def routes_from_values(value):
        result = []
        for vehicle in range(fleet):
            route = []
            index = routing.Start(vehicle)
            while not routing.IsEnd(index):
                index = value(routing.NextVar(index))
                if routing.IsEnd(index):
                    break
                route.append(manager.IndexToNode(index) + 1)
            result.append(route)
        return result

    initial_quality = route_quality(start_routes, distances)
    best_quality = initial_quality
    events = []
    max_sampled_threads = 0

    def sample_threads():
        nonlocal max_sampled_threads
        if sys.platform.startswith("linux"):
            max_sampled_threads = max(max_sampled_threads, len(os.listdir("/proc/self/task")))

    def elapsed():
        return max(0.0, (time.time_ns() - args.trial_start_epoch_ns) / 1e9)

    def capture(routes):
        nonlocal best_quality
        quality = route_quality(routes, distances)
        if quality >= best_quality:
            return
        sample_threads()
        best_quality = quality
        events.append({
            "seconds": elapsed(),
            "vehicles": quality[0],
            "distance": quality[1],
            "routes": [route for route in routes if route],
        })

    def at_solution():
        capture(routes_from_values(lambda variable: variable.Value()))

    # Routing's SWIG solution monitor is not a CP-SAT worker-thread callback.
    # CP-SAT exports its final incumbent after returning to the Python caller.
    if args.engine == "routing":
        routing.AddAtSolutionCallback(at_solution)
    parameters = pywrapcp.DefaultRoutingSearchParameters()
    parameters.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    parameters.guided_local_search_lambda_coefficient = args.gls_lambda
    # Routing can invoke CP-SAT for scheduling or fallback. Bound those calls
    # as well; BLAS/OpenMP limits alone do not constrain CP-SAT's own pool.
    parameters.sat_parameters.ClearField("num_search_workers")
    parameters.sat_parameters.num_workers = args.workers
    if args.engine == "cpsat":
        parameters.use_cp = pywrapcp.BOOL_FALSE
        parameters.use_cp_sat = pywrapcp.BOOL_FALSE
        parameters.use_generalized_cp_sat = pywrapcp.BOOL_TRUE
        parameters.fallback_to_cp_sat_size_threshold = 0
        parameters.sat_parameters.random_seed = args.seed
        parameters.sat_parameters.log_search_progress = args.verify_cpsat
        parameters.sat_parameters.log_to_stdout = args.verify_cpsat
        parameters.report_intermediate_cp_sat_solutions = False
    parameters.log_search = False
    parameters.time_limit.FromNanoseconds(max(0, int((args.seconds - elapsed()) * 1e9)))
    # Some search options are frozen when the model closes. Set GLS before
    # restoring the shared start, which otherwise closes with default options.
    routing.CloseModelWithParameters(parameters)
    initial_assignment = routing.ReadAssignmentFromRoutes(
        [[manager.NodeToIndex(node_id - 1) for node_id in route] for route in start_routes],
        True,
    )
    remaining = max(0.0, args.seconds - elapsed())
    search_nanoseconds = max(0, int(remaining * 1e9))
    parameters.time_limit.FromNanoseconds(search_nanoseconds)
    start_elapsed = elapsed()
    sample_threads()
    cpu_started = time.process_time()
    started_ns = time.perf_counter_ns()
    if search_nanoseconds == 0:
        solution = None
        status = "no_search_budget"
    elif initial_assignment is None:
        solution = routing.SolveWithParameters(parameters)
        status = "solution" if solution is not None else "no_solution"
    else:
        solution = routing.SolveFromAssignmentWithParameters(initial_assignment, parameters)
        status = "solution" if solution is not None else "no_solution"
    solver_seconds = (time.perf_counter_ns() - started_ns) / 1e9
    solver_cpu_seconds = time.process_time() - cpu_started
    sample_threads()
    if solution is None:
        final_routes = start_routes
    else:
        final_routes = routes_from_values(lambda variable: solution.Value(variable))
        capture(final_routes)

    final_quality = route_quality(final_routes, distances)
    final_seconds = elapsed()
    events.sort(key=lambda event: event["seconds"])
    fields = {
        "ortools_version": ortools_version,
        "python_version": sys.version.split()[0],
        "seed_label": args.seed,
        "seed_used_by_routing_search": False,
        "engine": args.engine,
        "guided_local_search": args.engine == "routing",
        "gls_lambda": args.gls_lambda,
        "internal_search_threads": args.workers,
        "seed_used_by_cp_sat": args.engine == "cpsat",
        "cp_local_search_enabled": args.engine == "routing",
        "generalized_cp_sat_enabled": args.engine == "cpsat",
        "trajectory_observation": "routing callbacks" if args.engine == "routing" else "final incumbent only; target time is an upper bound",
        "process_id": os.getpid(),
        "affinity_supported": hasattr(os, "sched_getaffinity"),
        "affinity_cpus": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else [],
        "max_sampled_native_threads": max_sampled_threads,
        "native_thread_observation": "callback samples; not a continuous peak measurement" if args.engine == "routing" else "before/after search samples; not a peak measurement",
        "native_thread_limits": [f"{key}={os.environ.get(key, 'unset')}" for key in (
            "OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "MKL_NUM_THREADS",
            "BLIS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")],
        "solver_cpu_seconds": solver_cpu_seconds,
        "common_start_accepted": initial_assignment is not None,
        "solver_status": status,
        "seconds": final_seconds,
        "solver_seconds": solver_seconds,
        "search_start_seconds": start_elapsed,
        "vehicles": final_quality[0],
        "distance": final_quality[1],
        "routes": [route for route in final_routes if route],
        "distance_scale": DISTANCE_SCALE,
        "time_scale": TIME_SCALE,
        "objective_policy": "lexicographic vehicles then distance using a dominating fixed vehicle cost",
    }
    write_result(args.output, fields, events, CPSAT_SCHEMA if args.engine == "cpsat" else SCHEMA)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--trial-start-epoch-ns", type=int, required=True)
    parser.add_argument("--engine", choices=("routing", "cpsat"), default="routing")
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--gls-lambda", type=float, default=0.1)
    parser.add_argument("--verify-cpsat", action="store_true")
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or args.seconds < 0:
        parser.error("--seconds must be finite and nonnegative")
    if args.seed <= 0 or args.trial_start_epoch_ns <= 0:
        parser.error("--seed and --trial-start-epoch-ns must be positive")
    if args.workers < 1 or (args.engine == "routing" and args.workers != 1):
        parser.error("Routing requires one internal worker; CP-SAT requires positive workers")
    if not math.isfinite(args.gls_lambda) or args.gls_lambda <= 0:
        parser.error("--gls-lambda must be finite and positive")
    run(args)


if __name__ == "__main__":
    main()
