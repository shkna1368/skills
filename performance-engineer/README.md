# Performance Engineer Skill — Help Guide

## Installation

```bash
npx skills add shkna1368/skills --skill performance-engineer
```

### Install in Agentic Coding Tools

<details>
<summary>Claude Code</summary>

```bash
claude mcp add skills-performance-engineer -- npx -y skills run shkna1368/skills --skill performance-engineer
```

Or add to `.claude/settings.json`:
```json
{
  "permissions": {
    "allow": ["skills-performance-engineer"]
  }
}
```
</details>

<details>
<summary>Kiro</summary>

```bash
npx skills install shkna1368/skills --skill performance-engineer --client kiro
```

Or copy `SKILL.md` to `.kiro/skills/performance-engineer/SKILL.md` in your project.
</details>

<details>
<summary>Codex</summary>

```bash
npx skills install shkna1368/skills --skill performance-engineer --client codex
```

Or copy `SKILL.md` content into your Codex instructions file (`AGENTS.md` or `codex.md`).
</details>

<details>
<summary>Cursor</summary>

```bash
npx skills install shkna1368/skills --skill performance-engineer --client cursor
```

Or copy `SKILL.md` to `.cursor/rules/performance-engineer.md` in your project.
</details>

<details>
<summary>Windsurf</summary>

```bash
npx skills install shkna1368/skills --skill performance-engineer --client windsurf
```

Or copy `SKILL.md` to `.windsurf/rules/performance-engineer.md` in your project.
</details>

<details>
<summary>Amazon Q Developer CLI</summary>

Copy `SKILL.md` to `.amazonq/rules/performance-engineer.md` in your project.
</details>

## What is this?

A Kiro skill that automatically profiles your microservices, finds performance bottlenecks, and tells you exactly which file and line of code to fix — with before/after code snippets.

## Why use it?

| Problem | Without this skill | With this skill |
|---------|-------------------|-----------------|
| "API is slow" | Guess, add logs, redeploy, repeat | Attach profiler → exact method + line causing latency |
| "System crashes under load" | Panic, scale up servers ($$$) | Find the 2-line config fix (pool size, timeout) |
| "Memory keeps growing" | Restart pods every few hours | Identify the exact leaking collection/closure |
| "Works fine locally, slow in prod" | ¯\\\_(ツ)\_/¯ | Load test + profile = root cause in minutes |
| "Which service is the bottleneck?" | Check each one manually | Auto-discovers full service chain, profiles all |

**Bottom line:** Instead of guessing, you get empirical proof of what's wrong and how to fix it.

## When to use it

✅ Use when:
- Functional tests pass but performance is unknown
- An API is slower than expected
- You need to validate the system handles production traffic
- Before a release to production
- After adding a new feature that touches multiple services
- Prometheus/Grafana shows degradation but you don't know why

❌ Don't use when:
- Code doesn't compile yet
- Functional bugs exist (fix those first)
- You just need a unit test

## How to use it

### Quick start (just say it)

```
You: "Profile order-service"
You: "Why is POST /api/orders slow?"
You: "Run performance test on this project"
You: "Find bottlenecks in the payment feature"
You: "The p99 is 5 seconds, help"
```

### With specific inputs

```
You: "Profile the services in /path/to/project, 
      focus on the order feature, 
      target SLO is p95 < 200ms"
```

### With existing data

```
You: "Analyze this JFR recording: /tmp/app.jfr"
You: "Here are the k6 results, what's wrong?"
You: "Check this heap dump for memory leaks: /tmp/heap.hprof"
```

### In Kubernetes

```
You: "Profile order-service in the staging namespace"
You: "The pods in K8s are slow, run performance analysis"
```

## What happens after you trigger it

```
┌─────────────────────────────────────────────┐
│ Step 0: Detection                           │
│  • Local or Kubernetes?                     │
│  • Which services are in this feature?      │
│  • What language is each service?           │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ Step 1+2: Load Test + Profile (simultaneous)│
│  • Attach profiler (JFR/pprof/py-spy/etc)   │
│  • Run k6 load test against endpoints       │
│  • Ramp until SLO breaches                  │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ Step 3: Deep Diagnostics                    │
│  • CPU hotspots + thread contention         │
│  • GC pauses + memory leaks                 │
│  • DB queries + connection pool health      │
│  • Redis / Kafka health                     │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ Step 4: Root Cause Analysis                 │
│  "OrderService.java:56 — synchronized      │
│   method causes cascading lock contention   │
│   (54 events, up to 5.6s blocked)"         │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ Step 5: Fix Recommendations                 │
│  • Config: pool-size=2 → 20 (immediate)    │
│  • Code: before/after Java/Go/Python/etc    │
│  • Architecture: add caching, pagination    │
└─────────────────────────────────────────────┘
```

## Supported languages

| Language | Frameworks | Profiler used |
|----------|-----------|---------------|
| Java | Spring Boot, Quarkus, Micronaut | JFR, async-profiler, JProfiler |
| Go | Gin, Fiber, Echo | pprof (built-in) |
| Rust | Actix-web, Axum, Rocket | perf, flamegraph, tokio-console |
| Python | FastAPI, Django, Flask | py-spy, memray, scalene |
| Node.js | Express, NestJS, Fastify | clinic, 0x, --prof |
| .NET | ASP.NET Core | dotnet-trace, dotnet-dump |

Works with any version — no version lock.

## Supported environments

| Environment | How it works |
|-------------|-------------|
| Local (docker-compose) | Direct process access, localhost |
| Kubernetes | `kubectl exec` + `kubectl cp` + port-forward |
| Both mixed | Auto-detects per service |

## What infrastructure does it check?

- **PostgreSQL / MySQL** — slow queries, missing indexes, connection pools
- **Redis** — memory, TTL, slow commands, hit ratio
- **Kafka** — consumer lag, throughput, rebalances
- **HTTP clients** — timeouts, connection reuse

## What do I get at the end?

1. **Terminal report** — structured findings with severity badges
2. **HTML report** — visual dashboard with gauges, dark/light theme (optional)
3. **Exact fix code** — before/after snippets ready to copy-paste
4. **Priority list** — what to fix first for maximum impact

## Example output (abbreviated)

```
❌ CRITICAL — 3 SLO breaches

┌────────────────────────────────────────────────────┐
│ p95: 30.1s (target <500ms)  │  Throughput: 8 RPS   │
└────────────────────────────────────────────────────┘

Root Causes:
1. [CRITICAL] OrderService.java:56 — synchronized method
   Evidence: 54 lock contention events (JFR), cascading to 5.6s
   Fix: Replace with SQL aggregate query

2. [CRITICAL] application.properties:8 — pool-size=2
   Fix: Change to 20 (zero code, immediate)

3. [HIGH] OrderEventProducer.java:20 — sync Kafka .get()
   Fix: Remove .get(), use async callback
```

## FAQ

**Q: Does it modify my code?**
A: No. It only reads code, runs load tests, and attaches read-only profilers. Fixes are recommendations you apply.

**Q: Will it break my running service?**
A: Profilers add 2-5% CPU overhead during recording. The safety protocol auto-stops load tests if error rate exceeds 5%.

**Q: Do I need Jaeger/tracing installed?**
A: No. It helps (gives exact service chain), but the skill falls back to source code scanning, API specs, or Prometheus metrics.

**Q: Can it profile production?**
A: It can, but the safety protocol warns against high-load tests on production. Recommended flow: profile in staging, validate fix in prod with low-overhead JFR.

**Q: What if my service is in a language not listed?**
A: The database, Redis, Kafka, and load testing parts still work (they're language-agnostic). Only the runtime profiling would be missing.

**Q: What if profiling tools aren't installed in the container?**
A: The skill detects what's missing, shows you exactly what to install, and falls back to metrics-based profiling (docker stats + per-service latency) if nothing can be installed.

**Q: How does it handle microservices in different languages?**
A: It detects each service's language independently and uses the right tool per service (JFR for Java, pprof for Go, py-spy for Python, etc.)

**Q: How much load should I use?**
A: The skill determines this automatically. If you have no target, it runs a breakpoint test (ramps until failure) to find the ceiling.

---

## Advanced Features

### Service Chain Discovery

When you say "profile the order feature," the skill auto-discovers ALL services involved:

```
You: "Profile the checkout flow"
Skill: Discovers → gateway → auth → user → cart → product → 
       order → payment → shipping → notification (9 services)
```

Detection methods (uses first available):
1. Distributed tracing (Jaeger/Zipkin)
2. Service mesh (Istio/Linkerd)
3. Prometheus metrics
4. OpenAPI/AsyncAPI spec scanning
5. Source code grep
6. Metrics diff (run scenario, see who woke up)

### Load Test Types

| Type | What it finds | When to use |
|------|--------------|-------------|
| **Breakpoint** | Max capacity ceiling | "How much can it handle?" |
| **Soak** | Memory leaks, resource exhaustion | "Is it stable over time?" |
| **Load** | SLO validation | "Does it meet targets?" |
| **Spike** | Recovery behavior | "What happens after a burst?" |

The skill picks the right type based on your question or runs breakpoint by default.

### Architecture-Level Detection

Beyond code-level bugs, the skill detects system design problems:
- Sequential fan-out (gateway calls N services one-by-one)
- Missing circuit breakers
- No timeouts on outbound calls
- Chatty inter-service communication

### Profiling-Ready Infrastructure

Add these to docker-compose once — profiling works on every restart with zero setup:

```yaml
# Java: auto-records JFR
JAVA_TOOL_OPTIONS: "-XX:StartFlightRecording=..."

# Python: enables py-spy attachment
cap_add: [SYS_PTRACE]

# Node.js: enables Chrome DevTools
NODE_OPTIONS: "--inspect=0.0.0.0:9229"

# Go: GC tracing in logs
GODEBUG: "gctrace=1"

# .NET: diagnostics channel
DOTNET_EnableDiagnostics: "1"
```

### Kubernetes Support

Works in K8s automatically — detects if service is in a pod and routes commands through `kubectl exec` / `kubectl cp`. Also supports `kubectl debug` for attaching tools without rebuilding images.

### HTML Report

Every analysis generates a visual HTML report with:
- Dark/light theme toggle
- Gauge dials for key metrics
- Color-coded language badges
- Memory comparison tables
- Collapsible fix recommendations
- Auto-opens in browser
