# Solver API Reference

## OR-Tools (CP-SAT)

```python
from ortools.sat.python import cp_model

model = cp_model.CpModel()

# Variables
x = model.new_int_var(0, 10, "x")
b = model.new_bool_var("b")
xs = [model.new_bool_var(f"x_{i}") for i in range(n)]

# Constraints
model.add(x != y)
model.add(x + y <= capacity)
model.add_exactly_one(xs)
model.add_at_most_one(xs)
model.add_all_different(vars)
model.add_max_equality(max_var, list_of_vars)
model.add_min_equality(min_var, list_of_vars)

# Objective
model.minimize(expr)
model.maximize(expr)

# Solve
solver = cp_model.CpSolver()
solver.parameters.max_time_in_seconds = 10
solver.parameters.num_workers = 8
status = solver.solve(model)
# status: OPTIMAL, FEASIBLE, INFEASIBLE
value = solver.value(x)
```

### OR-Tools VRP (Routing)

```python
from ortools.constraint_solver import routing_enums_pb2, pywrapcp

manager = pywrapcp.RoutingIndexManager(num_locations, num_vehicles, depot)
routing = pywrapcp.RoutingModel(manager)

cb_idx = routing.RegisterTransitCallback(distance_callback)
routing.SetArcCostEvaluatorOfAllVehicles(cb_idx)

d_idx = routing.RegisterUnaryTransitCallback(demand_callback)
routing.AddDimensionWithVehicleCapacity(d_idx, 0, capacities, True, "Cap")

params = pywrapcp.DefaultRoutingSearchParameters()
params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
params.time_limit.FromSeconds(10)
solution = routing.SolveWithParameters(params)
```

---

---

## Z3 (Microsoft SMT/SAT)

```python
from z3 import *

# Variables
x = Int('x')
b = Bool('b')
xs = [Int(f'x_{i}') for i in range(n)]

# Solver (satisfiability)
s = Solver()
s.add(x != y)
s.add(And(x >= 0, x < 10))
s.add(Implies(b, x > 5))
s.add(If(b, x == 1, x == 0))
s.add(Distinct(xs))
s.set('timeout', 10000)  # ms
if s.check() == sat:
    m = s.model()
    val = m[x].as_long()

# Optimizer (min/max)
opt = Optimize()
opt.add(x + y <= 10)
opt.minimize(x)
if opt.check() == sat:
    m = opt.model()
```

---

## Choco Solver (Java via subprocess)

```java
import org.chocosolver.solver.Model;
import org.chocosolver.solver.variables.IntVar;
import org.chocosolver.solver.variables.BoolVar;

public class Solver {
    public static void main(String[] args) {
        Model model = new Model("Problem");

        // Variables
        IntVar x = model.intVar("x", 0, 10);
        IntVar[] xs = model.intVarArray("xs", 5, 0, 10);
        BoolVar b = model.boolVar("b");

        // Constraints
        model.allDifferent(xs).post();
        model.arithm(x, "!=", y).post();
        model.arithm(x, "<=", 5).post();
        model.sum(xs, "<=", capacity).post();
        model.scalar(xs, coeffs, "<=", limit).post();

        // Conditional constraints (KEY ADVANTAGE over pychoco)
        model.ifThen(
            model.arithm(x, "=", value),
            model.arithm(y, ">=", minVal)
        );
        model.ifThenElse(
            model.arithm(x, "=", d),
            model.arithm(contrib, "=", points),
            model.arithm(contrib, "=", 0)
        );

        // Element (array indexing)
        model.element(value, array, index).post();

        // Optimization
        model.setObjective(Model.MINIMIZE, obj);
        while (model.getSolver().solve()) {
            // each call finds a better solution
            bestValue = obj.getValue();
        }

        // Output as JSON for Python to parse
        System.out.println("{\"result\":" + x.getValue() + "}");
    }
}
```

Python wrapper:
```python
import subprocess, json, tempfile, os

def solve_choco(problem_data, java_code):
    with tempfile.TemporaryDirectory() as tmp:
        # Write data as JSON for Java
        data_path = os.path.join(tmp, "data.json")
        with open(data_path, "w") as f:
            json.dump(problem_data, f)
        # Compile and run
        src = os.path.join(tmp, "Solver.java")
        with open(src, "w") as f:
            f.write(java_code)
        subprocess.run(["javac", "-cp", "choco-solver.jar:gson.jar", src], check=True)
        r = subprocess.run(["java", "-cp", f"choco-solver.jar:gson.jar:{tmp}", "Solver", data_path],
                          capture_output=True, text=True, timeout=30)
        return json.loads(r.stdout)
```

---

## Timefold

```python
from typing import Annotated
from dataclasses import dataclass, field
from timefold.solver.domain import (
    planning_entity, planning_solution, PlanningId, PlanningVariable,
    PlanningEntityCollectionProperty, ProblemFactCollectionProperty,
    PlanningScore, ValueRangeProvider,
)
from timefold.solver.score import HardSoftScore, constraint_provider, ConstraintFactory, Joiners, ConstraintCollectors
from timefold.solver import SolverFactory
from timefold.solver.config import SolverConfig, ScoreDirectorFactoryConfig, TerminationConfig, Duration

# Domain
@dataclass
class Fact:
    id: Annotated[int, PlanningId]

@planning_entity
@dataclass
class Entity:
    id: Annotated[int, PlanningId]
    value: Annotated[Fact | None, PlanningVariable] = field(default=None)

@planning_solution
@dataclass
class Solution:
    facts: Annotated[list[Fact], ProblemFactCollectionProperty, ValueRangeProvider]
    entities: Annotated[list[Entity], PlanningEntityCollectionProperty]
    score: Annotated[HardSoftScore | None, PlanningScore] = field(default=None)

# Constraints
@constraint_provider
def constraints(cf: ConstraintFactory):
    return [
        # Hard: conflict
        cf.for_each(Entity).join(Entity,
            Joiners.equal(lambda e: e.value),
            Joiners.less_than(lambda e: e.id))
        .penalize(HardSoftScore.ONE_HARD).as_constraint("Conflict"),

        # Soft: minimize load (optimization)
        cf.for_each(Entity)
        .group_by(lambda e: e.value, ConstraintCollectors.count())
        .penalize(HardSoftScore.ONE_SOFT, lambda v, c: c * c)
        .as_constraint("Balance"),

        # if_not_exists (ensure assignment)
        cf.for_each(Fact)
        .if_not_exists(Entity, Joiners.equal(lambda f: f, lambda e: e.value))
        .penalize(HardSoftScore.ONE_HARD).as_constraint("Must assign"),
    ]

# Solve
config = SolverConfig(
    solution_class=Solution, entity_class_list=[Entity],
    score_director_factory_config=ScoreDirectorFactoryConfig(constraint_provider_function=constraints),
    termination_config=TerminationConfig(spent_limit=Duration(seconds=10))
)
solution = SolverFactory.create(config).build_solver().solve(problem)
```

### Timefold Pitfalls
- `Duration(seconds=N)` NOT `timedelta`
- Never `if obj` in constraint lambdas
- Python 3.10–3.12 only
- `group_by` won't see unassigned — use `if_not_exists`
