---
name: microbench
description: Benchmarks Java methods using JMH in Spring Boot and Quarkus projects. Detects framework, generates benchmark classes, runs them, and produces an HTML report with light/dark theme.
---

# Microbench Skill

## Description

Benchmarks Java methods using JMH (Java Microbenchmark Harness). Automatically detects whether the target project is Spring Boot or Quarkus, generates appropriate benchmark classes, executes them, and produces a styled HTML report with light/dark theme toggle.

## Inputs

- `projectPath`: Root directory of the Java project to benchmark
- `targetClass`: Fully qualified class name containing methods to benchmark (e.g., `com.perflab.order.service.OrderService`)
- `targetMethods`: List of method names to benchmark (empty = all public methods)
- `warmupIterations`: JMH warmup iterations (default: 3)
- `measurementIterations`: JMH measurement iterations (default: 5)
- `forks`: Number of JVM forks (default: 1)
- `mode`: Benchmark mode — `thrpt` (throughput), `avgt` (average time), `sample`, `all` (default: `avgt`)

## Framework Detection

Detect the framework by reading `pom.xml` or `build.gradle`:

| Indicator | Framework |
|-----------|-----------|
| `spring-boot-starter-parent` in parent | Spring Boot |
| `quarkus-bom` in dependencyManagement | Quarkus |
| `io.quarkus` plugin | Quarkus |
| `spring-boot-maven-plugin` | Spring Boot |

## Steps

1. **Detect Framework** — Read `pom.xml`/`build.gradle` to determine Spring Boot or Quarkus
2. **Analyze Target Class** — Read the source file, identify public methods, their dependencies and parameters
3. **Generate Benchmark** — Create a JMH benchmark class under `src/test/java` with proper `@State`, `@Setup`, and `@Benchmark` annotations
4. **Add JMH Dependencies** — Add `jmh-core` and `jmh-generator-annprocess` to the project's build file if not present
5. **Run Benchmark** — Execute via `mvn exec:java` or the JMH runner, capture JSON output
6. **Generate HTML Report** — Parse JMH JSON results and render a styled HTML report
7. **Open Report** — Open the HTML file in the default browser

## Benchmark Generation Rules

### Spring Boot

- Use `@State(Scope.Benchmark)` for the benchmark class
- Mock external dependencies (DB, Kafka, Redis) — benchmark pure logic only
- For `@Service` classes: instantiate directly with mocked dependencies
- For methods with `@Transactional`: benchmark the computation logic, not the DB round-trip

### Quarkus

- Use `@State(Scope.Benchmark)` for the benchmark class
- For `@ApplicationScoped` beans: instantiate directly with mocked dependencies
- For Panache repositories: mock the repository calls, benchmark service logic

### Common Rules

- Methods with `Thread.sleep()`: benchmark with sleep removed (note this in report)
- Methods needing DB data: create in-memory test data in `@Setup`
- Methods with external calls (HTTP, Kafka): mock the external call, benchmark internal logic
- Always include a baseline `@Benchmark` method that does nothing (for overhead measurement)

## JMH Dependencies

```xml
<!-- Add to pom.xml -->
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-core</artifactId>
    <version>1.37</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-generator-annprocess</artifactId>
    <version>1.37</version>
    <scope>test</scope>
</dependency>
```

## Running

```bash
# Compile and run benchmarks
mvn clean test-compile exec:java \
  -Dexec.mainClass="org.openjdk.jmh.Main" \
  -Dexec.classpathScope="test" \
  -Dexec.args="-rf json -rff benchmark-result.json <BenchmarkClassName>"
```

## HTML Report

Generate an HTML file (`microbench-report.html`) with:

- **Dark/light theme** toggle (respects `prefers-color-scheme`, manual toggle button)
- **Summary bar** at top: project name, framework, date, total methods benchmarked
- **Results table**: method name, mode, score, score error, units, ops/sec
- **Bar chart**: visual comparison of method performance (CSS-only, no JS libs)
- **Bottleneck badges**: flag methods that are significantly slower than others
- **Method details**: collapsible sections with benchmark parameters used

### Report Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Microbench Report</title>
  <style>
    :root {
      --bg: #ffffff; --text: #1a1a1a; --card: #f8f9fa;
      --border: #e0e0e0; --accent: #2563eb; --bar: #3b82f6;
      --fast: #16a34a; --medium: #ca8a04; --slow: #dc2626;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f172a; --text: #e2e8f0; --card: #1e293b;
        --border: #334155; --accent: #60a5fa; --bar: #3b82f6;
        --fast: #22c55e; --medium: #eab308; --slow: #ef4444;
      }
    }
    [data-theme="light"] { --bg: #ffffff; --text: #1a1a1a; --card: #f8f9fa; --border: #e0e0e0; --accent: #2563eb; }
    [data-theme="dark"] { --bg: #0f172a; --text: #e2e8f0; --card: #1e293b; --border: #334155; --accent: #60a5fa; }
    * { box-sizing: border-box; }
    body { background: var(--bg); color: var(--text); font-family: system-ui, -apple-system, sans-serif; margin: 0; padding: 2rem; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }
    .header h1 { margin: 0; font-size: 1.5rem; }
    .theme-toggle { cursor: pointer; padding: 0.5rem 1rem; border-radius: 6px; border: 1px solid var(--border); background: var(--card); color: var(--text); font-size: 0.875rem; }
    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
    .summary-card { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; text-align: center; }
    .summary-card .value { font-size: 1.5rem; font-weight: bold; color: var(--accent); }
    .summary-card .label { font-size: 0.75rem; text-transform: uppercase; opacity: 0.7; }
    table { width: 100%; border-collapse: collapse; background: var(--card); border-radius: 8px; overflow: hidden; border: 1px solid var(--border); }
    th, td { padding: 0.75rem 1rem; text-align: left; border-bottom: 1px solid var(--border); }
    th { font-size: 0.75rem; text-transform: uppercase; opacity: 0.7; }
    .bar-cell { position: relative; }
    .bar { height: 24px; border-radius: 4px; background: var(--bar); opacity: 0.8; }
    .badge { padding: 2px 8px; border-radius: 4px; font-size: 0.7rem; font-weight: bold; }
    .badge.fast { background: var(--fast); color: white; }
    .badge.medium { background: var(--medium); color: white; }
    .badge.slow { background: var(--slow); color: white; }
    details { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; margin-top: 1rem; }
    summary { cursor: pointer; font-weight: bold; }
  </style>
</head>
<body>
  <div class="header">
    <h1>⚡ Microbench Report</h1>
    <button class="theme-toggle" onclick="toggleTheme()">🌓 Theme</button>
  </div>
  <div class="summary">
    <div class="summary-card"><div class="value">PROJECT</div><div class="label">Project</div></div>
    <div class="summary-card"><div class="value">FRAMEWORK</div><div class="label">Framework</div></div>
    <div class="summary-card"><div class="value">N</div><div class="label">Methods</div></div>
    <div class="summary-card"><div class="value">DATE</div><div class="label">Date</div></div>
  </div>
  <table>
    <thead><tr><th>Method</th><th>Mode</th><th>Score</th><th>Error</th><th>Units</th><th>Visual</th><th>Rating</th></tr></thead>
    <tbody>
      <!-- rows populated from JMH JSON -->
    </tbody>
  </table>
  <details><summary>📋 Benchmark Parameters</summary>
    <p>Warmup: X iterations | Measurement: Y iterations | Forks: Z</p>
  </details>
  <script>
    function toggleTheme() {
      const h = document.documentElement;
      h.setAttribute('data-theme', h.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    }
  </script>
</body>
</html>
```

## Performance Rating

Rate each method based on relative performance within the benchmark run:

| Rating | Condition |
|--------|-----------|
| 🟢 Fast | Within 2x of the fastest method |
| 🟡 Medium | 2x–10x slower than fastest |
| 🔴 Slow | >10x slower than fastest |

## Output

- `benchmark-result.json` — Raw JMH output
- `microbench-report.html` — Styled HTML report
- Console summary with top bottlenecks

After generating the report, open it:

```bash
open microbench-report.html          # macOS
xdg-open microbench-report.html     # Linux
```
