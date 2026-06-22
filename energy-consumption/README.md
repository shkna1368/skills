# Energy Consumption Skill — Help Guide

## What is this?

A skill that measures how much energy your software project consumes through static code analysis, Dockerfile scanning, and real-time runtime measurement under load. It auto-discovers endpoints, starts your app, applies a load test, measures per-service energy, and produces an HTML report with CO₂ emissions, cloud cost estimates, region recommendations, and fun comparisons.

## Why use it?

| Problem | Without this skill | With this skill |
|---------|-------------------|--------------------|
| "How much energy does my app use?" | No idea, hope for the best | Measured in Joules with per-service breakdown |
| "Which service wastes the most?" | Profile manually for hours | Instant ranking by energy consumption |
| "Where should I deploy for lowest CO₂?" | Pick a random region | Region comparison table with 98% savings possible |
| "Are my Dockerfiles wasteful?" | Guess | 9 anti-patterns detected with fix advice |
| "N+1 queries wasting energy?" | Hunt through code | Auto-detected with file:line and severity |
| "What does this cost in cloud?" | AWS bill surprise | Estimate before deploying ($/month per region) |

## When to use it

✅ Use when:
- You want to measure actual energy consumption of microservices
- Before deploying to production (choose greenest region)
- During code review (static energy waste detection)
- In CI/CD pipelines (track energy trends over releases)
- Optimizing cloud costs
- Generating sustainability reports for stakeholders

❌ Don't use when:
- Project doesn't have Docker/containers
- You need pure performance benchmarking (use microbench skill)
- You need security analysis (use redteam skill)

## How to use it

### Quick start

```
You: "Analyze energy consumption of this project"
You: "Check energy efficiency"
You: "Run energy report"
You: "How much CO₂ does my app produce?"
```

### Manual run (all phases)

```bash
PROJECT=./my-project

# Phase 0: Install prerequisites
bash energy-consumption/install.sh

# Phase 1: Static code analysis
bash energy-consumption/static-analysis.sh "$PROJECT"

# Phase 2: Dockerfile analysis
bash energy-consumption/dockerfile-analysis.sh "$PROJECT"

# Phase 3: Runtime (auto-discovers endpoints, starts app, load tests, measures)
bash energy-consumption/runtime-analysis.sh "$PROJECT" http://localhost:8000/api/endpoint 30 10

# Phase 4: Container energy (Docker or K8s)
bash energy-consumption/container-analysis.sh docker "" 30 "$PROJECT"
# OR for Kubernetes:
bash energy-consumption/container-analysis.sh k8s production 60 "$PROJECT"

# Phase 5: Generate HTML report
bash energy-consumption/generate-report.sh "$PROJECT"

# Phase 6: Open
open "$PROJECT/energy-report/energy-report.html"
```

### Runtime analysis auto-detection

The runtime script automatically:
1. **Finds endpoints** from docker-compose ports + source code routes + README curl examples
2. **Detects HTTP method & body** from README (finds POST examples with JSON payloads)
3. **Starts the app** if not running (docker-compose up -d)
4. **Verifies all services** are responding before testing
5. **Measures idle → applies load → measures under load**

No manual configuration needed for most projects.

## What it detects

### Static Analysis (10+ patterns)
| Pattern | Severity | Energy Impact |
|---------|----------|---------------|
| Busy loops / polling | High | CPU waste |
| I/O inside loops | High | Disk/network thrash |
| N+1 queries | High | Database overload |
| Missing connection pooling | Medium | Resource exhaustion |
| Thread-per-request | Medium | Memory + CPU waste |
| Large allocations in loops | Medium | Memory pressure |
| Chatty HTTP calls | Medium | Network waste |
| Missing connection reuse | Medium | Connection overhead |
| Unbuffered I/O | Low | Suboptimal throughput |
| Missing compression | Low | Bandwidth waste |
| Redundant serialization | Low | CPU + memory waste |

### Dockerfile Analysis (9 anti-patterns)
| Pattern | Severity | Waste |
|---------|----------|-------|
| No multi-stage build | Critical | 500MB+ bloat |
| Large base images | High | 200-500MB |
| COPY without .dockerignore | High | 100MB+ |
| Too many RUN layers | Medium | Cache inefficiency |
| Unclean package cache | Medium | 50-100MB |
| Dev deps in production | Medium | 50-200MB |
| No HEALTHCHECK | Low | No auto-recovery |
| Unpinned tags (:latest) | Low | Reproducibility |
| Layer cache breaking | Low | Slow builds |

## Report features

- **Combined grade A-F** (40% static + 60% runtime)
- **CO₂ emissions** per month (region-aware carbon intensity)
- **Cloud cost estimate** (AWS, Azure, GCP pricing per region)
- **Region comparison** — deploy to greenest region with % savings
- **Per-service energy breakdown** (Joules per container)
- **Energy per request** (mJ/request)
- **Idle vs load comparison** (delta CPU, memory, efficiency ratio)
- **Load test results** (RPS, latency, total requests)
- **Historical trend** (score over time with ↑↓ arrows)
- **Runtime-specific tips** (JVM/GraalVM, Rust, Node.js, Python, Go)
- **🎉 Fun facts** — hamsters, SpaceX rockets, pizza ovens, burritos
- **🔥 Wall of Shame** — roasts your worst services
- **🏅 Achievement badges** — earned based on actual metrics
- **Responsive HTML** with dark/light mode toggle

## Platform support

| OS | Support |
|----|---------|
| macOS | ✅ Native bash |
| Linux | ✅ Native bash |
| Windows | ✅ Git Bash, WSL, MSYS2 |

## Requirements

- Bash 4+
- Python 3.6+
- Docker + Docker Compose
- curl
- Load testing tool (optional): `hey` (recommended), `ab`, `wrk`

## Output

```
<project>/energy-report/
├── static-analysis.json       # Code pattern findings
├── dockerfile-analysis.json   # Dockerfile waste findings
├── runtime-analysis.json      # Runtime measurements (idle + load)
├── container-analysis.json    # Per-container energy breakdown
├── history.json               # Historical trend data
└── energy-report.html         # Final HTML report
```

## Configuration

Edit `cloud-profiles.json` to customize:
- Cloud provider pricing (AWS, Azure, GCP, custom)
- Region-specific carbon intensity (g CO₂/kWh)
- Country-level emission factors
- Default region for calculations

## Scoring

| Grade | Score | Meaning |
|-------|-------|---------|
| A | 90-100 | Excellent energy efficiency |
| B | 75-89 | Good, minor improvements possible |
| C | 60-74 | Moderate waste detected |
| D | 40-59 | Significant energy waste |
| F | 0-39 | Critical efficiency problems |
