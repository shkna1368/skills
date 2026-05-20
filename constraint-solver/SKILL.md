---
name: constraint-solver
description: "Solve constraint satisfaction problems using four solvers in parallel: Google OR-Tools, Timefold, Choco Solver (Java), and Z3 (Microsoft). Export results as a responsive HTML report with dark/light theme. Use this skill for scheduling, planning, routing, resource allocation, verification, or logic problems. Trigger phrases: 'constraint satisfaction', 'optimization', 'scheduling', 'planning problem', 'vehicle routing', 'timetabling', 'bin packing', 'frequency assignment', 'network slicing', 'resource allocation', 'sprint planning', 'project scheduling', 'portfolio optimization', 'task assignment', 'nurse scheduling', 'verification', 'logic problem', 'symbolic reasoning', 'SAT', 'SMT'. Do NOT use for simple sorting or filtering."
metadata:
  owner: group:default/da
  version: "1.0.0"
tags:
  - bos
  - pdu-da
  - coding
  - optimization
  - constraint-satisfaction
  - timefold
  - ortools
  - choco
  - z3
  - python
  - telecom
---

# Constraint Solver (OR-Tools + Timefold + Choco + Z3)

Solve constraint problems with **four** solvers in parallel. Export results as HTML with dark/light theme.

## Requirements

- **Python 3.10–3.12** (Timefold does not support 3.13+)
- **Java 17+** runtime (Timefold + Choco both use JVM)
- OR-Tools has no extra dependencies

```bash
# Install Python solvers
pip install timefold ortools z3-solver

# Download Choco Solver + Gson JARs
curl -sL -o choco-solver.jar "https://repo1.maven.org/maven2/org/choco-solver/choco-solver/4.10.14/choco-solver-4.10.14-jar-with-dependencies.jar"
curl -sL -o gson.jar "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar"

# Verify
python -c "from ortools.sat.python import cp_model; print('OR-Tools OK')"
python -c "from timefold.solver import SolverFactory; print('Timefold OK')"
python -c "from z3 import *; print('Z3 OK')"
java -cp choco-solver.jar org.chocosolver.solver.Model && echo "Choco OK"
```

If Java is missing, install it:
```bash
# macOS
brew install openjdk@17

# Ubuntu/Debian
sudo apt install openjdk-17-jre

# Verify
java -version
```

## Workflow

When the user describes a problem or provides a data file, generate a **single Python file** that:

1. Reads input data (from file or inline)
2. Solves with all 4 solvers
3. Exports `result.html` and opens it

## Supported Input Formats

The agent reads the user's data file and extracts problem parameters:

| Format | Library | Example |
|--------|---------|---------|
| Excel (.xlsx) | `pandas` + `openpyxl` | `pd.read_excel("data.xlsx")` |
| CSV | `pandas` or `csv` | `pd.read_csv("data.csv")` |
| JSON | `json` | `json.load(open("data.json"))` |
| Text/TSV | built-in | `open("data.txt").readlines()` |

When user provides a file, add to pip install: `pip install pandas openpyxl`

Common data patterns:
- **Employee list**: name, skills, availability, max_hours
- **Task list**: id, duration, dependencies, required_skill
- **Distance matrix**: location pairs with distances/times
- **Demand table**: time periods with required coverage
- **Constraint rules**: text description of hard/soft rules

## Generated File Structure

```python
import time, webbrowser, os

# ============================================================
# PROBLEM DATA
# ============================================================
# ... shared data ...

# ============================================================
# OR-TOOLS
# ============================================================
def solve_ortools():
    from ortools.sat.python import cp_model
    t0 = time.time()
    # ... solve ...
    return {"result": ..., "time": time.time() - t0}

# ============================================================
# TIMEFOLD
# ============================================================
def solve_timefold():
    from timefold.solver import SolverFactory
    from timefold.solver.config import Duration
    t0 = time.time()
    # ... solve ...
    return {"result": ..., "time": time.time() - t0}

# ============================================================
# CHOCO SOLVER (Java via subprocess)
# ============================================================
def solve_choco():
    import subprocess, json, tempfile, os
    java_code = """..."""  # generate Java source
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "Solver.java"), "w") as f:
            f.write(java_code)
        subprocess.run(["javac", "-cp", "choco-solver.jar", os.path.join(tmp, "Solver.java")], check=True)
        r = subprocess.run(["java", "-cp", f"choco-solver.jar:{tmp}", "Solver"],
                          capture_output=True, text=True, timeout=30)
        return json.loads(r.stdout)

# ============================================================
# Z3 SOLVER (SMT/SAT)
# ============================================================
def solve_z3():
    from z3 import *
    t0 = time.time()
    # ... solve ...
    return {"result": ..., "time": time.time() - t0}

# ============================================================
# RUN & EXPORT
# ============================================================
ort = solve_ortools()
tf = solve_timefold()
ch = solve_choco()
z3r = solve_z3()

html = f"""..."""  # build HTML with all 3 results
with open("result.html", "w") as f:
    f.write(html)
webbrowser.open("file://" + os.path.abspath("result.html"))
```

## HTML Template

The exported HTML shows **only results** — no timing, no performance, no comparison.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Solver Results</title>
<style>
:root {
  --bg: #fff; --fg: #1a1a2e; --card: #f8f9fa; --border: #e0e0e0;
  --accent: #2563eb; --accent2: #7c3aed; --table-header: #f1f5f9;
  --shadow: rgba(0,0,0,0.08);
}
[data-theme="dark"] {
  --bg: #0f172a; --fg: #e2e8f0; --card: #1e293b; --border: #334155;
  --accent: #60a5fa; --accent2: #a78bfa; --table-header: #1e293b;
  --shadow: rgba(0,0,0,0.3);
}
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:-apple-system,sans-serif; background:var(--bg); color:var(--fg); padding:2rem; transition:all .3s; }
.container { max-width:1000px; margin:0 auto; }
h1 { font-size:1.8rem; margin-bottom:.5rem; }
h2 { color:var(--accent); margin:1.5rem 0 .8rem; }
.subtitle { opacity:.7; margin-bottom:1.5rem; }
.card { background:var(--card); border:1px solid var(--border); border-radius:.75rem; padding:1.5rem; margin:1rem 0; box-shadow:0 2px 8px var(--shadow); }
.grid { display:grid; grid-template-columns:1fr 1fr 1fr 1fr; gap:1rem; }
@media(max-width:768px) { .grid{grid-template-columns:1fr;} }
table { width:100%; border-collapse:collapse; font-size:.85rem; }
th,td { padding:.5rem .75rem; border-bottom:1px solid var(--border); text-align:left; }
th { background:var(--table-header); font-weight:600; }
.tag { display:inline-block; padding:.15rem .5rem; border-radius:1rem; font-size:.7rem; font-weight:600; }
.tag-ort { background:#dbeafe; color:#1e40af; }
.tag-tf { background:#ede9fe; color:#5b21b6; }
.tag-ch { background:#d1fae5; color:#065f46; }
.tag-z3 { background:#fef3c7; color:#92400e; }
[data-theme="dark"] .tag-ort { background:#1e3a5f; color:#93c5fd; }
[data-theme="dark"] .tag-tf { background:#2e1065; color:#c4b5fd; }
[data-theme="dark"] .tag-ch { background:#064e3b; color:#6ee7b7; }
[data-theme="dark"] .tag-z3 { background:#451a03; color:#fcd34d; }
.theme-toggle { position:fixed; top:1rem; right:1rem; background:var(--card); border:1px solid var(--border); border-radius:2rem; padding:.5rem 1rem; cursor:pointer; font-size:1.2rem; z-index:100; }
</style>
</head>
<body>
<button class="theme-toggle" onclick="toggleTheme()">🌓</button>
<div class="container">
  <h1>Problem Title</h1>
  <p class="subtitle">Problem description</p>

  <div class="grid">
    <div class="card">
      <h3><span class="tag tag-ort">OR-Tools</span></h3>
      <!-- results table only -->
    </div>
    <div class="card">
      <h3><span class="tag tag-tf">Timefold</span></h3>
      <!-- results table only -->
    </div>
    <div class="card">
      <h3><span class="tag tag-ch">Choco</span></h3>
      <!-- results table only -->
    </div>
    <div class="card">
      <h3><span class="tag tag-z3">Z3</span></h3>
      <!-- results table only -->
    </div>
  </div>
</div>
<script>
function toggleTheme(){
  const h=document.documentElement;
  h.setAttribute('data-theme',h.getAttribute('data-theme')==='dark'?'light':'dark');
  localStorage.setItem('theme',h.getAttribute('data-theme'));
}
(()=>{
  const s=localStorage.getItem('theme')||(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');
  document.documentElement.setAttribute('data-theme',s);
})();
</script>
</body>
</html>
```

**Rules for the HTML output:**
- Show ALL data — every assignment, every entity, every constraint result
- For schedules: show the full grid (all nurses × all days × all shifts)
- For routing: show every vehicle's complete route with all stops
- For assignments: show every item and what it was assigned to
- Include an **Objective Value** row for each solver when the problem has an optimization goal
- NO timing, NO performance bars, NO speedup numbers
- NO "winner" or comparison language
- Three cards side by side with complete results from each solver

## Objective & Metrics

Every problem MUST have an objective function. Without it, solvers return any valid solution (which may be terrible).

### How to add objective per solver:

**OR-Tools** — declare in model:
```python
model.minimize(max_var - min_var)  # or model.maximize(...)
```

**Timefold** — use soft constraints (solver minimizes total penalty automatically):
```python
cf.for_each(Entity)
  .group_by(key, ConstraintCollectors.count())
  .filter(lambda k, c: c > threshold)
  .penalize(HardSoftScore.ONE_SOFT, lambda k, c: c - threshold)
  .as_constraint("Fairness")
```

**Choco** — use `setObjective` in Java:
```java
IntVar obj = model.intVar("obj", 0, 1000);
model.setObjective(Model.MINIMIZE, obj);
// Solver iterates to find optimal
while (model.getSolver().solve()) { /* best so far */ }
// Last solution found is optimal
```

### Common objectives by problem type:

| Problem | Objective | Formula |
|---|---|---|
| Scheduling | Fairness | `minimize(max_shifts - min_shifts)` |
| VRP / Routing | Travel cost | `minimize(total_distance)` |
| Bin packing | Bins used | `minimize(num_bins)` |
| Frequency | Spectrum cost | `minimize(distinct_frequencies)` |
| Network slicing | Latency | `minimize(sum_latency)` |
| Task assignment | Makespan | `minimize(max_completion_time)` |

### In the HTML, always show:
```html
<p class="obj">Objective: {value}</p>
```
This lets the user immediately see which solver found the better solution.

## OR-Tools Patterns

### CP-SAT (scheduling, assignment, graph coloring)

```python
from ortools.sat.python import cp_model
model = cp_model.CpModel()
x = model.new_int_var(0, n, "x")
model.add(x != y)
model.add_exactly_one(vars)
model.add_at_most_one(vars)
model.minimize(penalty)
solver = cp_model.CpSolver()
solver.parameters.max_time_in_seconds = 10
status = solver.solve(model)
```

### Routing (VRP)

```python
from ortools.constraint_solver import routing_enums_pb2, pywrapcp
manager = pywrapcp.RoutingIndexManager(num_locations, num_vehicles, depot)
routing = pywrapcp.RoutingModel(manager)
# RegisterTransitCallback, AddDimensionWithVehicleCapacity, Solve
```

## Z3 Solver Patterns (Microsoft SMT/SAT solver)

```python
from z3 import *

# Variables
x = Int('x')                    # integer
b = Bool('b')                   # boolean
xs = [Int(f'x_{i}') for i in range(n)]  # array

# Constraints
s = Solver()
s.add(x != y)                   # inequality
s.add(x + y <= 10)              # arithmetic
s.add(Distinct(xs))             # all different
s.add(And(x > 0, y > 0))       # logical AND
s.add(Or(x == 1, x == 2))      # logical OR
s.add(If(b, x == 1, x == 0))   # conditional
s.add(Implies(b, x > 5))       # implication

# Solve
if s.check() == sat:
    m = s.model()
    result = m[x].as_long()

# Optimization
opt = Optimize()
opt.add(x + y <= 10)
opt.minimize(x)                 # or opt.maximize(x)
if opt.check() == sat:
    m = opt.model()
```

Z3 strengths: logic/verification, symbolic reasoning, proving UNSAT, bit-vectors, real arithmetic.

## Choco Solver Patterns (Java — full power via subprocess)

Data flow: `Excel → Python (pandas) → data.json → Java Choco → result.json → Python`

Python wrapper:
```python
import subprocess, json, tempfile, os

def solve_choco(problem_data, java_code):
    """Run Java Choco with data passed via JSON file."""
    with tempfile.TemporaryDirectory() as tmp:
        # Write problem data as JSON for Java to read
        data_path = os.path.join(tmp, "data.json")
        with open(data_path, "w") as f:
            json.dump(problem_data, f)
        
        # Write and compile Java solver
        src = os.path.join(tmp, "Solver.java")
        with open(src, "w") as f:
            f.write(java_code)
        subprocess.run(["javac", "-cp", "choco-solver.jar:gson.jar", src], check=True)
        
        # Run — pass data.json as argument
        r = subprocess.run(
            ["java", "-cp", f"choco-solver.jar:gson.jar:{tmp}", "Solver", data_path],
            capture_output=True, text=True, timeout=30)
        return json.loads(r.stdout)
```

Java Choco template (reads JSON input, outputs JSON result):
```java
import org.chocosolver.solver.Model;
import org.chocosolver.solver.variables.IntVar;
import org.chocosolver.solver.variables.BoolVar;
import com.google.gson.*;
import java.nio.file.*;

public class Solver {
    public static void main(String[] args) throws Exception {
        // Read problem data from JSON
        String json = Files.readString(Path.of(args[0]));
        JsonObject data = JsonParser.parseString(json).getAsJsonObject();
        JsonArray items = data.getAsJsonArray("items");
        int N = items.size();  // dynamic — works with any size

        Model model = new Model("Problem");

        // Build variables dynamically from data
        IntVar[] x = model.intVarArray("x", N, 0, 10);

        // Add constraints from data
        for (int i = 0; i < N; i++) {
            JsonObject item = items.get(i).getAsJsonObject();
            int maxVal = item.get("max").getAsInt();
            model.arithm(x[i], "<=", maxVal).post();
        }

        // Conditional constraints (Choco's strength)
        model.ifThenElse(
            model.arithm(x[0], "=", 1),
            model.arithm(x[1], ">=", 3),
            model.arithm(x[1], "=", 0)
        );

        // Optimize
        IntVar obj = model.intVar("obj", 0, 1000);
        model.setObjective(Model.MINIMIZE, obj);
        
        // Solve
        model.getSolver().limitTime("15s");
        StringBuilder result = new StringBuilder("{\"assignments\":[");
        if (model.getSolver().solve()) {
            for (int i = 0; i < N; i++) {
                if (i > 0) result.append(",");
                result.append(x[i].getValue());
            }
        }
        result.append("]}");
        System.out.println(result);
    }
}
```

Requirements for Choco:
```bash
# Download Choco + Gson JARs
curl -sL -o choco-solver.jar "https://repo1.maven.org/maven2/org/choco-solver/choco-solver/4.10.14/choco-solver-4.10.14-jar-with-dependencies.jar"
curl -sL -o gson.jar "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar"
```

Key Java Choco features (not available in Python solvers):
- `model.ifThen(condition, constraint)` — conditional constraints
- `model.ifThenElse(cond, then, else)` — full conditional
- `model.element(value, array, index)` — array indexing
- `model.scalar(vars, coeffs, "<=", limit)` — weighted sum
- `model.setObjective(Model.MINIMIZE, var)` — optimization

## Timefold Patterns

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
```

- Use `@dataclass` + `Annotated[Type, PlanningVariable]`
- Use `Duration(seconds=N)` NOT `timedelta`
- Never use `if obj` in constraint lambdas
- `if_not_exists` for "every X must get at least one Y"

## Solver Strengths

| Problem Type | Best Solver | Why |
|---|---|---|
| Optimization with objective (min/max) | **OR-Tools** | Proves OPTIMAL, handles complex objectives |
| Many soft constraints, scheduling | **Timefold** | Declarative constraints, natural for timetabling |
| Logic, verification, symbolic reasoning | **Z3** | SMT solver, proves SAT/UNSAT, handles real arithmetic |
| Simple constraint satisfaction (no objective) | **Choco** | Fast for feasibility, conditional constraints |
| VRP / Routing | **OR-Tools** | Dedicated routing library |
| Sprint planning, capacity allocation | **OR-Tools** | Handles knapsack-style problems well |
| Portfolio / financial | **OR-Tools** | Linear objectives with constraints |
| Protocol verification, config validation | **Z3** | Symbolic reasoning, bit-vectors |

Note: Z3 excels at proving satisfiability/unsatisfiability and logic problems. For pure optimization with large search spaces, OR-Tools is faster.

## References

- [references/solver-api.md](references/solver-api.md) — API patterns for all 3 solvers
