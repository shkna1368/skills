# Energy Consumption Analysis

Analyzes a project's energy consumption through static code analysis and runtime resource measurement under load. Produces an HTML report with dark/light mode support showing energy waste patterns, resource usage metrics, and optimization recommendations.

---

## Role

You are an Energy Efficiency Engineer specializing in sustainable software development. You identify code patterns that waste computational resources (CPU, memory, I/O, network) and measure actual runtime energy consumption under realistic load.

---

## Trigger

Use this skill when asked to: analyze energy consumption, check energy efficiency, find energy waste, measure resource usage, or generate an energy report for a project.

---

## Platform Support

All scripts work on:
- **macOS** (native bash)
- **Linux** (native bash)
- **Windows** (Git Bash, WSL, or MSYS2)

Requirements: Bash 4+, Python 3.6+, Docker (for runtime analysis)

---

## Workflow

### Phase 0 — Install Prerequisites

Run the installer to check and install required dependencies:

```bash
bash ~/.kiro/skills/energy-consumption/install.sh
```

This will:
- Detect your OS (macOS, Linux, Windows)
- Check for: `python3`, `docker`, `docker-compose`, `curl`
- Check for load testing tools: `hey`, `ab`, or `wrk`
- Auto-install missing tools via `brew` (macOS), `apt`/`dnf`/`pacman` (Linux), or print `winget` commands (Windows)

### Phase 1 — Static Analysis

Run the static analysis script to scan source code for energy-wasting patterns:

```bash
bash ~/.kiro/skills/energy-consumption/static-analysis.sh <project_root>
```

This detects:
- **Busy loops / polling**: `while(true)`, tight loops without sleep, spin waits
- **Inefficient I/O**: unbuffered reads/writes, file opens inside loops, missing connection pooling
- **Memory waste**: large allocations in loops, missing stream processing, loading entire files into memory
- **N+1 queries**: database calls inside loops, missing batch operations
- **Redundant computation**: repeated calculations, missing caching, unnecessary serialization/deserialization
- **Network waste**: chatty protocols, missing compression, no connection reuse, sequential HTTP calls that could be batched
- **Concurrency issues**: thread-per-request without pooling, unbounded thread creation
- **Idle resource holding**: connections/handles kept open unnecessarily, missing timeouts

Output: `energy-report/static-analysis.json`

### Phase 2 — Dockerfile Analysis

Scan Dockerfiles for wasteful image patterns:

```bash
bash ~/.kiro/skills/energy-consumption/dockerfile-analysis.sh <project_root>
```

This detects:
- **No multi-stage build**: build tools left in final image (critical)
- **Large base images**: using ubuntu/debian instead of alpine/slim/distroless (high)
- **COPY without .dockerignore**: pulling in unnecessary files (high)
- **Too many RUN layers**: not combining commands (medium)
- **Unclean package cache**: apt-get without cleanup (medium)
- **Dev dependencies in prod**: npm install without --production (medium)
- **No HEALTHCHECK**: missing container health monitoring (low)
- **Unpinned tags**: using `:latest` instead of specific version (low)
- **Layer cache breaking**: COPY . before dependency install (low)

Output: `energy-report/dockerfile-analysis.json`

### Phase 3 — Runtime Analysis (Idle → Load Test → Measure)

Run the runtime analysis script which **measures idle, applies a load test, then measures under load**:

```bash
bash ~/.kiro/skills/energy-consumption/runtime-analysis.sh <project_root> [endpoint] [duration_sec] [concurrency]
```

**Arguments:**
| Arg | Default | Description |
|-----|---------|-------------|
| project_root | `.` | Path to the project |
| endpoint | `http://localhost:8000` | Endpoint to load test |
| duration_sec | `30` | How long to run the load test |
| concurrency | `10` | Number of concurrent connections |

**Flow:**
1. Detects available load tool: `hey` → `ab` → `wrk` → `curl` (fallback)
2. Verifies endpoint is reachable (auto-starts docker-compose if needed)
3. **Measures idle** — captures baseline docker stats before load
4. **Applies load test** at the specified concurrency and duration
5. **Measures under load** — captures docker stats after load
6. Calculates: energy, CO₂ emissions, cost estimate, idle vs load delta

**Output includes:**
- Per-container CPU%, memory, network I/O, block I/O
- Load test RPS, latency, total requests
- Energy estimate in Joules (TDP-based model)
- **Idle vs. load comparison** (delta CPU, delta memory, efficiency ratio)

Output: `energy-report/runtime-analysis.json`

### Phase 4 — Container Analysis (Docker / Kubernetes)

Measure energy consumption of running Docker containers or Kubernetes pods:

```bash
# Docker containers
bash ~/.kiro/skills/energy-consumption/container-analysis.sh docker [name-filter] [duration] [project_dir]

# Kubernetes pods
bash ~/.kiro/skills/energy-consumption/container-analysis.sh k8s [namespace] [duration] [project_dir]
```

**Examples:**
```bash
# All Docker containers, 30s measurement
bash ~/.kiro/skills/energy-consumption/container-analysis.sh docker "" 30 ./my-project

# Only containers matching "microservice"
bash ~/.kiro/skills/energy-consumption/container-analysis.sh docker microservice 30 ./my-project

# Kubernetes pods in "production" namespace
bash ~/.kiro/skills/energy-consumption/container-analysis.sh k8s production 60 ./my-project
```

**What it measures:**
- Multiple samples over the duration (avoids point-in-time bias)
- Per-container/pod: avg CPU, avg/peak memory, network I/O, block I/O, PIDs
- Per-container/pod energy in Joules (CPU + memory + I/O components)
- Total energy and Watt-hours per hour projection
- For K8s: resource requests/limits vs actual usage

Output: `energy-report/container-analysis.json`

### Phase 5 — Report Generation

Generate the HTML report combining all findings:

```bash
bash ~/.kiro/skills/energy-consumption/generate-report.sh <project_root>
```

Produces `energy-report/energy-report.html` with:
- Executive summary with combined energy grade (A-F)
- **CO₂ emissions estimate** (grams CO₂ based on 400g/kWh global average)
- **Monthly cost estimate** (based on AWS $0.05/kWh pricing)
- **Trend over time** (historical score comparison with ↑↓ arrows)
- **Load test results** (tool, RPS, latency, total requests)
- **Idle vs. load comparison** (delta CPU, memory, efficiency ratio)
- Runtime metrics with per-service energy breakdown
- Energy per request (mJ/request)
- Container analysis with per-container energy
- Dockerfile analysis findings
- Static analysis findings grouped by severity
- **Recommendations** from all data sources:
  - Static analysis advice (code patterns)
  - Runtime advice (data-driven, based on measurements)
  - Container advice (right-sizing, scale-to-zero)
  - **Runtime-specific tips** (JVM/GraalVM, Rust, Node.js, Python, Go)
  - General best practices
- Responsive design with dark/light mode toggle

Also saves to `energy-report/history.json` for trend tracking across runs.

### Phase 6 — Open Report

```bash
open energy-report/energy-report.html        # macOS
xdg-open energy-report/energy-report.html    # Linux
start energy-report/energy-report.html       # Windows
```

---

## Full Example

```bash
PROJECT=~/my-project
bash ~/.kiro/skills/energy-consumption/install.sh
bash ~/.kiro/skills/energy-consumption/static-analysis.sh "$PROJECT"
bash ~/.kiro/skills/energy-consumption/dockerfile-analysis.sh "$PROJECT"
bash ~/.kiro/skills/energy-consumption/runtime-analysis.sh "$PROJECT" http://localhost:8000 30 10
bash ~/.kiro/skills/energy-consumption/container-analysis.sh docker "" 30 "$PROJECT"
bash ~/.kiro/skills/energy-consumption/generate-report.sh "$PROJECT"
open "$PROJECT/energy-report/energy-report.html"
```

---

## Output Structure

```
<project_root>/energy-report/
├── static-analysis.json       # Code pattern findings
├── dockerfile-analysis.json   # Dockerfile waste findings
├── runtime-analysis.json      # Runtime measurements (idle + load)
├── container-analysis.json    # Per-container energy breakdown
├── history.json               # Historical trend data
└── energy-report.html         # Final HTML report
```

---

## Scoring

| Grade | Score | Meaning |
|-------|-------|---------|
| A | 90-100 | Excellent energy efficiency |
| B | 75-89 | Good, minor improvements possible |
| C | 60-74 | Moderate waste detected |
| D | 40-59 | Significant energy waste |
| F | 0-39 | Critical efficiency problems |

**Combined score** = 40% static analysis + 60% runtime efficiency.

Runtime scoring penalizes: high memory per service, high CPU per container, high energy per request, excessive I/O.

---

## Recommended Load Tools

Install one for best results (in priority order):

| Tool | Install |
|------|---------|
| hey | `go install github.com/rakyll/hey@latest` |
| ab | `apt install apache2-utils` / `brew install httpd` |
| wrk | `apt install wrk` / `brew install wrk` |
| curl | Built-in (fallback, less accurate) |

---

## Notes

- Static analysis works on any language (pattern-based regex scanning)
- Runtime analysis requires Docker and a running application
- Energy is measured **under realistic load**, not idle
- The report is self-contained HTML (no external dependencies)
- All scripts use only `bash`, `python3`, `find`, `grep`, `curl`, `docker` — available on all platforms
- History is tracked in `history.json` — run multiple times to see trends
- CO₂ estimate uses 400g CO₂/kWh (global average grid intensity)
- Cost estimate uses $0.05/kWh (AWS average compute pricing)
