# Changelog

## [1.2.0] - 2026-06-05

### Added
- `microbench` skill: benchmark Java methods using JMH with anti-pattern detection
  - Supports Spring Boot and Quarkus (auto-detected from pom.xml)
  - All JMH modes: throughput, average time, sampling, single-shot
  - Source code analysis: N+1 queries, Thread.sleep, synchronized, no-pagination, race conditions
  - HTML report with dark/light theme, grouped results, bottleneck analysis
  - Action plan with before/after code diffs for each detected issue

## [1.1.0] - 2026-06-05

### Added
- `performance-engineer` skill: profile and diagnose microservices for performance bottlenecks
  - Supports Java, Go, Rust, Python, Node.js, and .NET
  - 5-step workflow: load test → profile → diagnose → root cause → fix
  - Auto-detects language, environment (local/K8s), and service chain
  - Generates HTML report with dark/light theme and gauges
  - Profiling-ready docker-compose configuration
  - Breakpoint, soak, load, and spike test strategies
  - Architecture-level bottleneck detection (sequential fan-out, missing circuit breakers)

## [1.0.0] - 2026-05-20

### Added
- `constraint-solver` skill: solve problems with OR-Tools, Timefold, Choco, and Z3 in parallel
