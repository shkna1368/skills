# Microbench Skill — Help Guide

## What is this?

A skill that benchmarks Java methods using JMH (Java Microbenchmark Harness). It detects whether your project is Spring Boot or Quarkus, generates benchmark classes with stubbed dependencies, runs all JMH modes, analyzes source code for anti-patterns, and produces an HTML report with actionable fix recommendations.

## Why use it?

| Problem | Without this skill | With this skill |
|---------|-------------------|-----------------|
| "Which method is slow?" | Guess from logs | JMH gives precise µs/op per method |
| "N+1 query somewhere" | Add Hibernate logging, read thousands of lines | Auto-detects pattern, shows exact fix with JOIN FETCH |
| "Is this Thread.sleep a problem?" | "It's just 1ms..." | Shows 1ms × 100 items = 100ms total with proof |
| "Race condition under load" | Intermittent bugs in prod | Flags missing `@Version`/optimistic locking before it ships |
| "String concat in loop" | Invisible until profiling | Detected statically, suggests StringBuilder |

## When to use it

✅ Use when:
- You want to measure method-level performance before deploying
- You suspect a service method has hidden bottlenecks
- Reviewing code that touches data access or computation logic
- Comparing performance before/after a refactor

❌ Don't use when:
- You need end-to-end HTTP load testing (use performance-engineer skill instead)
- Code doesn't compile yet
- You need to benchmark native/OS-level operations

## How to use it

### Quick start

```
You: "Benchmark OrderService"
You: "Run microbench on inventory-service"
You: "Which methods in NotificationService are slow?"
You: "Benchmark the service layer of this project"
```

### What it does

1. **Detects framework** — reads `pom.xml` to identify Spring Boot or Quarkus
2. **Generates JMH benchmark** — creates test class with stubbed DB/Kafka/Redis
3. **Runs all modes** — throughput, average time, sampling, single-shot
4. **Analyzes source** — scans for N+1, Thread.sleep, synchronized, no-pagination, race conditions
5. **Generates HTML report** — dark/light theme, grouped by method, bottleneck analysis with before/after code

### Detected Anti-Patterns

| Pattern | Severity | What it finds |
|---------|----------|---------------|
| `blocking-sleep` | Critical | Thread.sleep() in loops |
| `n-plus-1-query` | Critical | Lazy loading in forEach |
| `synchronized-method` | High | Thread contention |
| `no-pagination` | High | findAll() without Pageable |
| `sync-kafka-send` | High | .get() on Kafka Future |
| `no-optimistic-locking` | High | Concurrent updates without @Version |
| `string-concat-in-loop` | Medium | String += in loop (O(n²)) |
| `unbounded-collection` | Medium | List/Map that never evicts |

### Report Features

- 🌓 Dark/light theme toggle
- 📊 Results grouped by method (click to expand all modes)
- 🔥 Bottleneck analysis with severity badges
- 🔧 Action plan with before/after code diffs
- 💡 Tooltips explaining every number and unit

## Supported Frameworks

| Framework | Detection | Benchmark approach |
|-----------|-----------|-------------------|
| Spring Boot | `spring-boot-starter-parent` in pom.xml | Stub repositories and producers via constructor |
| Quarkus | `quarkus-bom` in pom.xml | Stub via reflection on `@Inject` fields |

## Installation

```bash
npx skills add shkna1368/skills --skill microbench
```

## Author

**Shabab Koohi** — [GitHub](https://github.com/shkna1368)

## License

MIT — see [LICENSE](../LICENSE) for details.
