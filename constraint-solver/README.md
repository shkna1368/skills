# Constraint Solver Skill

> Solve constraint satisfaction and optimization problems using four solvers in parallel: **OR-Tools**, **Timefold**, **Choco Solver**, and **Z3**. Results exported as a responsive HTML report with dark/light theme.

## Metadata

- **Author:** Shabab Koohi
- **Version:** 1.0.0
- **License:** MIT
- **Domain:** Optimization / Constraint Satisfaction / Scheduling / Planning

## What It Does

Give this skill a problem description (or a data file), and it generates a single Python script that:

1. Reads your input data (Excel, CSV, JSON, or text)
2. Solves the problem with all 4 solvers in parallel
3. Exports a `result.html` with side-by-side results from each solver

## Who Is It For

- Developers solving scheduling, routing, or resource allocation problems
- Teams evaluating which solver fits their use case
- Anyone needing quick constraint satisfaction solutions without deep solver expertise

## Supported Problem Types

| Problem | Example |
|---------|---------|
| Scheduling | Nurse rostering, shift planning, timetabling |
| Routing | Vehicle routing (VRP), delivery optimization |
| Resource Allocation | Task assignment, bin packing, network slicing |
| Planning | Sprint planning, project scheduling, portfolio optimization |
| Logic / Verification | SAT/SMT problems, protocol verification, config validation |

## Requirements

- Python 3.10–3.12 (Timefold does not support 3.13+)
- Java 17+ (for Timefold and Choco)

```bash
pip install timefold ortools z3-solver pandas openpyxl

# Choco Solver JARs
curl -sL -o choco-solver.jar "https://repo1.maven.org/maven2/org/choco-solver/choco-solver/4.10.14/choco-solver-4.10.14-jar-with-dependencies.jar"
curl -sL -o gson.jar "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar"
```

## Usage

1. Copy `SKILL.md` into your AI assistant's skill/prompt configuration
2. Describe your problem or provide a data file
3. The skill generates a Python solver script
4. Run the script — results open in your browser

## Example Output

The skill generates an interactive HTML report showing results from all 4 solvers side by side. Here's what the output looks like:

👉 **[View the full 100-problem showcase](https://htmlpreview.github.io/?https://github.com/shkna1368/skills/blob/main/constraint-solver/100-problems.html)**

The report covers **100 real-world problems** across 10 domains:

| Domain | Example Problems |
|--------|-----------------|
| Workforce & HR | Nurse scheduling, call center shifts, technician dispatch |
| Transportation | Vehicle routing, fleet assignment, school bus routing |
| Manufacturing | Job shop scheduling, line balancing, cutting stock |
| Warehousing | Bin packing, slotting, container packing |
| Telecom | Frequency assignment, 5G network slicing, spectrum allocation |
| Cloud | VM placement, K8s pod scheduling, container orchestration |
| Healthcare | OR scheduling, patient flow |
| Finance | Portfolio optimization |
| Software | Sprint planning, CI/CD pipeline |
| Verification | Protocol validation, config checking |

Each problem shows expandable results with assignments from OR-Tools, Z3, Choco, and Timefold — all in a responsive dark/light theme interface.

## Solver Strengths

| Solver | Best For |
|--------|----------|
| **OR-Tools** | Optimization with objectives, VRP, proving optimality |
| **Timefold** | Many soft constraints, scheduling, timetabling |
| **Choco** | Feasibility problems, conditional constraints |
| **Z3** | Logic/verification, symbolic reasoning, SAT/SMT |

## Structure

```
constraint-solver/
├── SKILL.md              # The skill definition (use this)
├── README.md             # This file
├── CHANGELOG.md          # Version history
├── references/
│   └── solver-api.md     # API patterns for all solvers
├── nurses.xlsx           # Example input data
└── 100-problems.html     # Example output report
```
