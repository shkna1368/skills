# Changelog — performance-engineer

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
