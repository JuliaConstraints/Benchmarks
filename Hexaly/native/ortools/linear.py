"""OR-Tools CP-SAT adapter for exact, integer-only JuMP linear models.

Python is the SDK boundary used by the pinned OR-Tools distribution. No
benchmark orchestration, original validation, or data preparation happens here.
"""
import sys
import tomllib
from ortools.sat.python import cp_model
import ortools


def main():
    if ortools.__version__ != "9.14.6206":
        raise RuntimeError("OR-Tools version differs from the frozen protocol")
    with open(sys.argv[1], "rb") as stream:
        request = tomllib.load(stream)
    model = cp_model.CpModel()
    variables = [model.new_int_var(v["lower"], v["upper"], str(i))
                 for i, v in enumerate(request["variables"])]
    for row in request["constraints"]:
        expression = sum(c * variables[i - 1]
                         for i, c in zip(row["indices"], row["coefficients"]))
        if "lower" in row:
            model.add(expression >= row["lower"])
        if "upper" in row:
            model.add(expression <= row["upper"])
    objective = request["objective"]
    model.minimize(sum(c * variables[i - 1]
                       for i, c in zip(objective["indices"], objective["coefficients"]))
                   + objective["constant"])
    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = request["seconds"]
    solver.parameters.num_search_workers = request["threads"]
    solver.parameters.random_seed = request["seed"]
    status = solver.solve(model)
    values = ([solver.value(v) for v in variables]
              if status in (cp_model.OPTIMAL, cp_model.FEASIBLE) else [])
    # A minimal TOML result keeps the native boundary independent of JSON packages.
    with open(sys.argv[2], "w", encoding="utf-8") as stream:
        stream.write('status = "' + solver.status_name(status) + '"\n')
        stream.write("values = " + repr(values) + "\n")
        stream.write("bound = " + repr(solver.best_objective_bound) + "\n")
        stream.write("seconds = " + repr(solver.wall_time) + "\n")


if __name__ == "__main__":
    main()
