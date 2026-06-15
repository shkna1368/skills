# Changelog — performance-engineer

## [1.1.0] - 2026-06-15

### Added
- Dedicated async-profiler deep-dive section with full workflow (CPU, alloc, lock, wall-clock profiling)
- async-profiler installation instructions for macOS (Homebrew), Linux, Docker, and Kubernetes
- Multi-event recording support (start/stop API for precise timing with load tests)
- async-profiler results section in HTML report: top methods, allocation hotspots, lock contention, links to interactive flame graphs
- JFR output format support from async-profiler (`-o jfr`)
- K8s debug container workflow for async-profiler when not in image
- Expanded Quick Reference with 7 async-profiler commands
- Advanced options: thread filtering, kernel frames, sampling interval

### Changed
- async-profiler promoted to **preferred** Java profiler (over JFR/JProfiler) for production-safe profiling
- HTML report now includes async-profiler results section with flame graph links
- README updated with async-profiler as primary Java profiler and installation guide

## [1.0.0] - 2026-06-05

### Added
- 5-step workflow: load test → profile → diagnose → root cause → fix
- Language support: Java, Go, Rust, Python, Node.js, .NET
- Step 0: auto-detect environment (local/K8s), service chain, language per service
- Service chain discovery: tracing, Prometheus, OpenAPI, AsyncAPI, source scan
- Load sizing: breakpoint, soak, load, spike test strategies
- JFR, pprof, py-spy, clinic/0x, dotnet-trace, perf/flamegraph profiling
- Bottleneck detection: database, Kafka, Redis, REST, memory, concurrency, architecture
- Architecture patterns: sequential fan-out, missing circuit breaker, chatty communication
- Kubernetes support: kubectl exec/cp/debug, port-forward
- Profiling-ready docker-compose configuration (zero-setup profiling)
- Tool auto-detection with install instructions when missing
- Metrics-based fallback when profiling tools unavailable
- HTML report output with dark/light theme, gauges, language badges
- Safety & rollback protocol (circuit breaker, environment checks)
- Configuration red flags for Spring Boot, Quarkus, and all runtimes
- Runtime tuning reference for all 6 languages
