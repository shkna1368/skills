---
name: performance-engineer
description: Profiles and diagnoses microservices for performance bottlenecks across Java, Go, Rust, Python, and .NET. Executes a strict 5-step workflow — load test, profiler extraction, deep diagnostics, root cause analysis, and remediation. Auto-detects language/runtime and selects the appropriate profiling toolchain. Use when functional testing is complete and you need to validate system resilience under load.
---

# Performance Engineer Skill

## Role

Senior Performance and Scalability Engineer specializing in high-throughput enterprise systems. Polyglot profiling across Java, Go, Rust, Python, and .NET. You do not guess — you measure, analyze raw metrics, profile at the native level for each runtime, and optimize based on empirical data.

## Core Competencies

- Automated Load & Resiliency Testing (language-agnostic)
- Runtime-Specific Diagnostics (JVM, Go runtime, Tokio, CPython/GIL, CLR)
- Database & Query Optimization (execution plans, indexes, connection pooling)
- Memory & Thread Forensic Analysis (leaks, contention, deadlocks, race conditions)

## Inputs

- `service`: Target service directory or running process
- `scope`: `full` | `api` | `database` | `kafka` | `redis` | `memory` | `concurrency`
- `profileData`: Path to JProfiler exports, JFR recordings, or async-profiler output
- `loadTestResults`: Path to k6/Gatling/JMeter results
- `slos`: Performance budgets — target p95, p99, RPS, error rate thresholds
- `environment`: Target environment (local, staging, production)

## Workflow Entry Points

Depending on which inputs are already available, skip completed steps:

| Inputs Provided | Entry Point | Rationale |
|-----------------|-------------|-----------|
| Only `service` | Start at Step 1 | Full workflow — no prior data |
| `service` + `loadTestResults` | Start at Step 2 | Load test already done — attach profiler |
| `service` + `profileData` | Start at Step 3 | Profiler data exists — analyze directly |
| `service` + `loadTestResults` + `profileData` | Start at Step 4 | All raw data available — synthesize RCA |

## Technical Stack

| Category | Tools |
|----------|-------|
| Load Testing | k6, Apache JMeter, Gatling (language-agnostic) |
| Java Profiling | JProfiler (`jpenable`, `jpcontroller`, `jpexport`), async-profiler, JFR |
| Go Profiling | `pprof` (built-in), `go tool trace`, Pyroscope |
| Rust Profiling | `perf`, `flamegraph`, `tokio-console`, DHAT, Valgrind |
| Python Profiling | `py-spy`, `cProfile`, `memray`, `tracemalloc`, `scalene` |
| .NET Profiling | `dotnet-trace`, `dotnet-dump`, `dotnet-counters`, PerfView |
| Node.js Profiling | `clinic`, `0x`, `--prof`, `--inspect`, Chrome DevTools |
| APM & Metrics | Datadog, Dynatrace, Prometheus, Grafana, OpenTelemetry |
| Databases | PostgreSQL, MySQL, Redis, connection pool libraries |
| Frameworks | Spring Boot, Quarkus (Java); Gin, Fiber (Go); Actix, Axum (Rust); FastAPI, Django (Python); Express, NestJS (Node.js); ASP.NET Core (.NET) |

> **Note:** No specific version of any tool is required. The skill adapts to whatever version is installed. Version-specific features (like ZGC Generational on Java 21+) are noted where relevant.

---

## ⛔ Safety & Rollback Protocol

Before executing load tests or attaching profilers:

1. **Environment check:** Confirm target is `staging` or `local`. NEVER run 5000 VU tests on `production` without traffic shadowing.
2. **Auto-stop circuit breaker:** If `error_rate > 5%` for 60s → auto-abort load test.
   ```js
   // k6 thresholds with abort
   thresholds: {
     http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '60s' }]
   }
   ```
3. **Profiler overhead:** `jpenable` adds ~3-5% CPU overhead. JFR `profile` settings add ~2%.
4. **Heap dump warning:** `jcmd <PID> GC.heap_dump` causes a Stop-The-World pause proportional to heap size. Warn the team before executing on staging with live traffic.
5. **Rollback:** If load test destabilizes the environment, immediately stop k6 (`Ctrl+C`) and restart affected services.

---

## Execution Workflow (Strict 5-Step Sequence)

**Trigger:** Execute ONLY after functional testing phase is marked COMPLETED.

### Step 0: Environment & Runtime Detection (Pre-flight)

**Action:** First detect if the service is running in Kubernetes or locally. Then identify language/runtime.

#### A. Environment Detection (K8s vs Local)

```bash
detect_environment() {
  SERVICE=$1

  # Check if kubectl is available and service exists in cluster
  if command -v kubectl &>/dev/null && kubectl get pods -l app=$SERVICE -o name 2>/dev/null | grep -q "pod/"; then
    echo "k8s"
  else
    echo "local"
  fi
}

# Usage:
ENV=$(detect_environment "order-service")
# ENV = "k8s" or "local"
```

**If `k8s`** → All profiler/dump commands go through `kubectl exec`, files extracted via `kubectl cp`, load test targets Service/Ingress URL.

**If `local`** → Direct process access, `jcmd <PID>`, `curl localhost`, files on local disk.

#### B. K8s Pod Resolution (only if environment = k8s)

```bash
# Find target pod
POD=$(kubectl get pods -l app=order-service -o jsonpath='{.items[0].metadata.name}')
NAMESPACE=$(kubectl get pods -l app=order-service -o jsonpath='{.items[0].metadata.namespace}')

# Verify pod is running
kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}'  # must be "Running"

# Get service URL for load testing
SVC_URL=$(kubectl get svc order-service -n $NAMESPACE -o jsonpath='http://{.spec.clusterIP}:{.spec.ports[0].port}')
# Or use ingress:
INGRESS_URL=$(kubectl get ingress -n $NAMESPACE -o jsonpath='http://{.items[0].spec.rules[0].host}')

# Check container capabilities (needed for py-spy, perf)
kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].securityContext}'
```

#### C. Service Chain Discovery (Feature → Services)

When profiling a **feature** (e.g., "order", "payment", "registration") rather than a single service, first discover all services involved in that flow.

**Method priority (use first available):**

| Priority | Method | When to use |
|----------|--------|-------------|
| 1 | Distributed tracing | OpenTelemetry/Jaeger/Zipkin deployed |
| 2 | Service mesh graph | Istio/Linkerd installed |
| 3 | Prometheus metrics | Services emit labeled HTTP/Kafka metrics |
| 4 | OpenAPI spec scan | Spec files exist in repos |
| 5 | AsyncAPI spec scan | Async specs exist (Kafka/AMQP channels) |
| 6 | Source code scan | Always works — grep endpoints, topics, clients |

**Method 1: Distributed Tracing (most accurate)**

```bash
# Send traced request to trigger the feature
TRACE_ID=$(openssl rand -hex 16)
curl -H "traceparent: 00-${TRACE_ID}-$(openssl rand -hex 8)-01" \
  http://gateway/api/orders -X POST -d '{"items":[{"productId":"PROD-1","quantity":1,"price":29.99}]}'

# Query Jaeger for the trace (shows full service chain with timing)
curl -s "http://jaeger:16686/api/traces/$TRACE_ID" | jq '.data[0].spans[].operationName'

# Output: gateway-service → order-service → inventory-service → notification-service
```

**Method 2: Prometheus (runtime, no code access needed)**

```bash
# Which services handled "order" requests in last 5 minutes?
curl -s 'http://prometheus:9090/api/v1/query?query=increase(http_server_requests_seconds_count{uri=~".*order.*"}[5m])>0' \
  | jq -r '.data.result[].metric | "\(.job) — \(.method) \(.uri)"'

# Which services produce/consume order-events topic?
curl -s 'http://prometheus:9090/api/v1/query?query=kafka_consumer_records_consumed_total{topic="order-events"}>0' \
  | jq -r '.data.result[].metric.job'
```

**Method 3: OpenAPI Spec Scan**

Parse OpenAPI (Swagger) specs to discover which services expose endpoints matching the feature:

```bash
# Find all OpenAPI spec files
find $SOURCE_ROOT -name "openapi*.yaml" -o -name "openapi*.json" -o -name "swagger*.yaml" | while read spec; do
  SERVICE=$(echo "$spec" | sed 's|.*/\([^/]*-service\)/.*|\1|')

  # Check if spec contains paths matching the feature
  if grep -q "/$FEATURE\|/$FEATURE/" "$spec"; then
    echo "=== $SERVICE ==="
    # Extract matching endpoints
    yq '.paths | keys[]' "$spec" 2>/dev/null | grep -i "$FEATURE"
    # Or with jq for JSON specs:
    # jq '.paths | keys[]' "$spec" | grep -i "$FEATURE"
  fi
done
```

**What to extract from OpenAPI:**
- Endpoint paths matching feature (e.g., `POST /api/orders`, `GET /api/orders/{id}`)
- Request/response schemas (payload size impacts performance)
- Downstream service references in `servers` field or `x-]]` extensions

---

**Method 4: AsyncAPI Spec Scan**

Parse AsyncAPI specs to discover Kafka/AMQP/MQTT channels involved in the feature:

```bash
# Find all AsyncAPI spec files
find $SOURCE_ROOT -name "asyncapi*.yaml" -o -name "asyncapi*.json" | while read spec; do
  SERVICE=$(echo "$spec" | sed 's|.*/\([^/]*-service\)/.*|\1|')

  # Check if spec has channels matching the feature
  if grep -q "$FEATURE" "$spec"; then
    echo "=== $SERVICE ==="
    # Extract channels (topics)
    yq '.channels | keys[]' "$spec" 2>/dev/null | grep -i "$FEATURE"
    # Extract publish/subscribe operations
    yq '.channels[] | select(.publish or .subscribe) | {"publish": .publish.operationId, "subscribe": .subscribe.operationId}' "$spec" 2>/dev/null
  fi
done
```

**What to extract from AsyncAPI:**
- Topic/channel names (e.g., `order-events`, `order-status-update`)
- Which services publish vs subscribe (direction of flow)
- Message schemas (payload size, serialization format: JSON/Protobuf/Avro)
- Protocol bindings (Kafka, AMQP, etc.)

**Example AsyncAPI discovery output:**
```json
{
  "channels": [
    {"topic": "order-events", "publisher": "order-service", "subscriber": ["inventory-service", "notification-service"], "format": "JSON"},
    {"topic": "inventory-events", "publisher": "inventory-service", "subscriber": ["notification-service"], "format": "JSON"}
  ]
}
```

---

**Method 5: Source Code Scan (works without specs)**

Scan source code for REST endpoints, Kafka producers/consumers, and HTTP client calls:

```bash
discover_chain() {
  FEATURE=$1       # e.g., "order"
  SOURCE_ROOT=$2   # e.g., "/repos"

  echo "=== REST Endpoints matching '$FEATURE' ==="
  # Java: @RequestMapping, @GetMapping, @PostMapping, @Path
  grep -rn "@\(Request\|Get\|Post\|Put\|Delete\)Mapping.*$FEATURE\|@Path.*$FEATURE" $SOURCE_ROOT \
    --include="*.java" | sed 's|.*/\([^/]*-service\)/.*|\1 — &|'
  # Go: router.GET/POST, gin.Group
  grep -rn "\".*/$FEATURE\|Group(\".*$FEATURE" $SOURCE_ROOT --include="*.go"
  # Python: @app.get/post, @router
  grep -rn "@app\.\(get\|post\).*$FEATURE\|@router.*$FEATURE" $SOURCE_ROOT --include="*.py"
  # .NET: [HttpGet], [HttpPost], [Route]
  grep -rn "\[Http\(Get\|Post\).*$FEATURE\|\[Route.*$FEATURE" $SOURCE_ROOT --include="*.cs"

  echo ""
  echo "=== Kafka Producers (topics matching '$FEATURE') ==="
  # Java Spring: KafkaTemplate.send("topic")
  grep -rn "send(\"$FEATURE\|topic.*=.*$FEATURE\|@SendTo.*$FEATURE" $SOURCE_ROOT --include="*.java"
  # Java Quarkus: @Channel, mp.messaging.outgoing
  grep -rn "@Channel.*$FEATURE\|outgoing.*$FEATURE" $SOURCE_ROOT --include="*.java" --include="*.properties"
  # Go: producer.Produce, writer.WriteMessages
  grep -rn "Topic:.*$FEATURE\|\"$FEATURE-events\"" $SOURCE_ROOT --include="*.go"
  # Python: producer.send, aiokafka
  grep -rn "send.*$FEATURE\|topic.*$FEATURE" $SOURCE_ROOT --include="*.py"

  echo ""
  echo "=== Kafka Consumers (topics matching '$FEATURE') ==="
  # Java Spring: @KafkaListener
  grep -rn "@KafkaListener.*$FEATURE\|incoming.*$FEATURE" $SOURCE_ROOT --include="*.java" --include="*.properties"
  # Java Quarkus: @Incoming
  grep -rn "@Incoming.*$FEATURE\|mp.messaging.incoming.*$FEATURE" $SOURCE_ROOT --include="*.java" --include="*.properties"
  # Go: consumer.Subscribe, reader
  grep -rn "Subscribe.*$FEATURE\|GroupTopics.*$FEATURE" $SOURCE_ROOT --include="*.go"
  # Python: consumer
  grep -rn "subscribe.*$FEATURE\|consumer.*$FEATURE" $SOURCE_ROOT --include="*.py"

  echo ""
  echo "=== REST Clients calling '$FEATURE' endpoint ==="
  # Java: RestTemplate, WebClient, @FeignClient
  grep -rn "getForObject.*$FEATURE\|/$FEATURE\|@FeignClient.*$FEATURE\|WebClient.*$FEATURE" $SOURCE_ROOT --include="*.java"
  # Go: http.Get, http.Post
  grep -rn "http\.\(Get\|Post\).*/$FEATURE\|\".*/$FEATURE" $SOURCE_ROOT --include="*.go"
  # Python: requests.get, httpx
  grep -rn "requests\.\(get\|post\).*$FEATURE\|httpx.*$FEATURE" $SOURCE_ROOT --include="*.py"
  # .NET: HttpClient
  grep -rn "HttpClient.*$FEATURE\|GetAsync.*$FEATURE\|PostAsync.*$FEATURE" $SOURCE_ROOT --include="*.cs"

  echo ""
  echo "=== Database tables matching '$FEATURE' ==="
  grep -rn "@Table.*$FEATURE\|@Entity.*$FEATURE\|CREATE TABLE.*$FEATURE\|tableName.*$FEATURE" $SOURCE_ROOT \
    --include="*.java" --include="*.go" --include="*.py" --include="*.sql" --include="*.cs"
}

# Usage: discover_chain "order" "/repos/microservices"
```

---

**Method 6: K8s Service Mesh (Istio/Linkerd)**

```bash
# Istio: query Kiali for service graph
curl -s "http://kiali:20001/api/namespaces/default/graph?duration=5m&graphType=workload" \
  | jq '.elements.edges[] | select(.data.traffic) | "\(.data.source) → \(.data.target)"'

# Linkerd: tap live traffic
linkerd viz tap deploy/gateway-service --to deploy/order-service --path /api/orders
```

---

**Combined output (all methods merged):**

```json
{
  "feature": "order",
  "serviceChain": [
    {"service": "gateway-service", "role": "entry point", "type": "REST proxy"},
    {"service": "order-service", "role": "primary", "type": "REST + Kafka producer"},
    {"service": "inventory-service", "role": "downstream", "type": "Kafka consumer + DB"},
    {"service": "notification-service", "role": "terminal", "type": "Kafka consumer + Redis"}
  ],
  "communicationPaths": [
    {"from": "gateway-service", "to": "order-service", "protocol": "HTTP/REST"},
    {"from": "order-service", "to": "inventory-service", "protocol": "Kafka (order-events)"},
    {"from": "inventory-service", "to": "notification-service", "protocol": "Kafka (inventory-events)"},
    {"from": "order-service", "to": "notification-service", "protocol": "Kafka (order-events)"}
  ]
}
```

> **After discovery:** Profile ALL services in the chain, not just one. The bottleneck is often in a downstream service the user didn't suspect.

---

#### D. Language & Runtime Detection

```bash
# Auto-detect by inspecting the process or project files
detect_runtime() {
  PID=$1
  CMD=$(ps -p $PID -o args= 2>/dev/null)

  if echo "$CMD" | grep -q "java\|jdk\|quarkus\|spring"; then echo "java"
  elif echo "$CMD" | grep -q "\.go\|go run"; then echo "go"
  elif echo "$CMD" | grep -q "python\|uvicorn\|gunicorn\|flask\|fastapi"; then echo "python"
  elif echo "$CMD" | grep -q "node\|npm\|ts-node\|nest\|express\|fastify"; then echo "nodejs"
  elif echo "$CMD" | grep -q "dotnet\|\.dll"; then echo "dotnet"
  else
    # Check binary type for Rust/Go compiled binaries
    EXE=$(readlink /proc/$PID/exe 2>/dev/null || echo "$CMD" | awk '{print $1}')
    if file "$EXE" 2>/dev/null | grep -q "statically linked"; then echo "go-or-rust"
    elif ldd "$EXE" 2>/dev/null | grep -q "libstd.*rust"; then echo "rust"
    else echo "go"  # Go is statically linked by default
    fi
  fi
}

# Alternative: detect by project files
detect_by_project() {
  DIR=$1
  if [ -f "$DIR/pom.xml" ] || [ -f "$DIR/build.gradle" ]; then echo "java"
  elif [ -f "$DIR/go.mod" ]; then echo "go"
  elif [ -f "$DIR/Cargo.toml" ]; then echo "rust"
  elif [ -f "$DIR/requirements.txt" ] || [ -f "$DIR/pyproject.toml" ]; then echo "python"
  elif [ -f "$DIR/package.json" ]; then echo "nodejs"
  elif [ -f "$DIR/*.csproj" ] || [ -f "$DIR/*.sln" ]; then echo "dotnet"
  fi
}
```

**Tool selection matrix:**

| Runtime | CPU Profiler | Memory Profiler | Concurrency Profiler | Metrics |
|---------|-------------|-----------------|---------------------|---------|
| Java (JVM) | JFR, async-profiler, JProfiler | JFR alloc, heap dump | jdk.JavaMonitorEnter, thread dump | Micrometer/Prometheus |
| Go | `pprof` CPU | `pprof` heap/alloc | `pprof` mutex/block, goroutine dump | expvar, Prometheus |
| Rust | `perf record`, `flamegraph` | DHAT, Valgrind, heaptrack | `tokio-console`, `tracing` | metrics crate, Prometheus |
| Python | `py-spy`, `cProfile`, `scalene` | `memray`, `tracemalloc` | `py-spy` GIL, asyncio debug | prometheus_client |
| Node.js | `clinic flame`, `0x`, `--prof` | heap snapshot, `--heapsnapshot-near-heap-limit` | event loop lag, `blocked-at` | prom-client, Prometheus |
| .NET (CLR) | `dotnet-trace`, PerfView | `dotnet-dump`, Event Pipe | ThreadPool counters, async deadlock detection | `dotnet-counters`, Prometheus |

---

**⚠️ CRITICAL: Steps 1 and 2 MUST overlap. Attach profiler BEFORE starting load test. The profiler recording window must cover the peak load phase.**

```
Timeline:
  T+0:00  → Detect runtime + attach profiler
  T+0:30  → Start k6 load test (ramp-up begins)
  T+5:30  → Stop load test (ramp-down complete)
  T+6:00  → Export profiler snapshot
```

### Step 1: Automated Load Testing

**Action:** Transition target environment into load-testing phase. This step is language-agnostic — k6/Gatling/JMeter hit HTTP/gRPC endpoints regardless of implementation.

#### How Much Load Is Enough?

Don't guess a number. Use one of these strategies to determine the right load:

**Strategy 1: Production baseline × multiplier**

```
target_load = current_production_RPS × 2 (headroom)
peak_load   = current_production_RPS × 5 (stress test)
```

How to get production RPS:
```bash
# From Prometheus (last 24h peak)
curl -s 'http://prometheus:9090/api/v1/query?query=max_over_time(rate(http_server_requests_seconds_count[1m])[24h:1m])' \
  | jq '.data.result[].value[1]'

# From access logs
awk '{print $4}' access.log | cut -d: -f2-3 | sort | uniq -c | sort -rn | head -1

# From APM (Datadog/Dynatrace)
# Check dashboard for peak RPS in last 30 days
```

**Strategy 2: Find the breaking point (stress test)**

Ramp load until the system breaks — don't pick a number upfront:

```javascript
// k6: keep increasing until p95 > SLO or errors appear
export const options = {
  stages: [
    { duration: '2m', target: 50 },    // warm up
    { duration: '2m', target: 100 },   // normal
    { duration: '2m', target: 200 },   // above normal
    { duration: '2m', target: 500 },   // stress
    { duration: '2m', target: 1000 },  // break it
    { duration: '1m', target: 0 },     // cool down
  ],
  thresholds: {
    http_req_duration: [{ threshold: 'p(95)<500', abortOnFail: true, delayAbortEval: '30s' }],
    http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '30s' }],
  },
};
// k6 auto-stops when thresholds breach → that's your breaking point
```

**Strategy 3: Capacity planning formula**

```
required_VUs = (target_RPS × average_response_time_seconds)

Example:
  Target: 1000 RPS
  Current avg response: 200ms
  VUs needed: 1000 × 0.2 = 200 VUs

  If response degrades to 2s under load:
  VUs needed: 1000 × 2 = 2000 VUs (to maintain 1000 RPS)
```

**Strategy 4: No production data (new service)**

| Service Type | Start With | Stress To |
|-------------|-----------|-----------|
| Internal API (few consumers) | 20 VUs | 100 VUs |
| Public API (user-facing) | 100 VUs | 1000 VUs |
| Event processor (Kafka) | N/A (measure msg/s) | 10x expected throughput |
| Batch/background | 5 VUs | 50 VUs |

**Decision table — which load test type to run:**

| Goal | Test Type | Load Level | Duration |
|------|-----------|-----------|----------|
| Find bottlenecks | Stress test | Ramp until break | 10-15 min |
| Validate SLO | Load test | Production × 1.5 | 15-30 min |
| Check memory leaks | Soak test | Production × 1 | 2-12 hours |
| Test recovery | Spike test | 0 → max → 0 sudden | 5 min |
| Find max capacity | Breakpoint test | Ramp +50 VUs every 30s until fail | Until failure |

> **Rule of thumb:** If you don't know, start with a **breakpoint test** — ramp until something breaks. That tells you both the ceiling AND where the bottleneck is.

**Mandatory test sequence (always run both):**

```
1. Breakpoint test → Find the ceiling and the bottleneck
         │
         ▼ (use 50-70% of breaking point as sustainable load)
2. Soak test (5 min minimum) → Check memory leaks at sustainable load
```

After the breakpoint test completes, **always** run a soak test at 50-70% of the discovered breaking point. This catches memory leaks, connection pool exhaustion, and resource accumulation that only appear over time.

Example: if breakpoint = 400 RPS, run soak at 250 RPS for 5+ minutes.

**Execution:**
```bash
# k6 — ramp-up stages (preferred over flat VUs)
k6 run --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)" loadtest.js

# Example k6 stages config:
# stages: [
#   { duration: '1m', target: 100 },   // ramp to 100
#   { duration: '3m', target: 500 },   // ramp to 500
#   { duration: '2m', target: 1000 },  // ramp to 1000
#   { duration: '1m', target: 0 },     // ramp down
# ]

# Or JMeter
jmeter -n -t loadtest.jmx -l results.jtl -e -o report/

# Or Gatling
./gatling.sh -s com.perflab.LoadSimulation -rd "order-service load test"
```

**Metrics to gather:**

> Note: Default SLOs shown below. If `slos` parameter is provided, replace thresholds with user-provided values. User SLOs always override defaults.

| Metric | SLO Target (default) | Red Flag |
|--------|---------------------|----------|
| Response Time p95 | < 200ms | > 500ms |
| Response Time p99 | < 500ms | > 2000ms |
| Throughput (RPS) | > 1000 | plateaus or drops |
| Error Rate (5xx) | < 0.1% | > 1% |
| Timeout Rate | 0% | > 0.5% |

### Step 2: Profiler Automation & Data Extraction

**Action:** Attach language-appropriate profiler based on Step 0 detection. No GUI required.

#### Command Routing (K8s vs Local)

All profiler commands below adapt based on environment detected in Step 0:

| Action | Local | Kubernetes |
|--------|-------|------------|
| Run command | `jcmd <PID> ...` | `kubectl exec $POD -n $NS -- jcmd 1 ...` |
| Extract file | Already on disk | `kubectl cp $POD:/tmp/file ./file -n $NS` |
| Port-forward | Not needed | `kubectl port-forward $POD 6060:6060 -n $NS &` |
| Load test target | `http://localhost:8081` | `$SVC_URL` or `$INGRESS_URL` |
| Process ID | `pgrep -f service` | Always PID `1` inside container |

**K8s prerequisites:**
- JFR/pprof tools must exist inside the container image (or use `kubectl debug --image=...`)
- For `py-spy`/`perf`: container needs `SYS_PTRACE` capability
- For heap dumps: pod needs memory headroom (dump temporarily doubles usage)

**Fallback: When profiling tools are NOT available in the container:**

First, **detect** what's available:

```bash
check_profiling_tools() {
  PID=$1
  CONTAINER=$2  # empty if local
  
  # Helper: run command locally or in container
  run() { [ -n "$CONTAINER" ] && docker exec $CONTAINER "$@" || "$@"; }

  echo "=== Profiling Tool Availability ==="
  
  # Java
  run which jcmd 2>/dev/null && echo "✅ jcmd available" || echo "❌ jcmd MISSING"
  run which jfr 2>/dev/null && echo "✅ jfr CLI available" || echo "❌ jfr MISSING"
  
  # Go
  curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/debug/pprof/ | grep -q 200 \
    && echo "✅ pprof endpoint available" || echo "❌ pprof endpoint NOT exposed"
  
  # Python
  run which py-spy 2>/dev/null && echo "✅ py-spy available" || echo "❌ py-spy MISSING"
  
  # Node.js
  run node -e "require('clinic')" 2>/dev/null && echo "✅ clinic available" || echo "❌ clinic MISSING"
  
  # .NET
  run which dotnet-trace 2>/dev/null && echo "✅ dotnet-trace available" || echo "❌ dotnet-trace MISSING"
}
```

If tools are missing, **output install instructions** for the user:

| Missing Tool | Language | Install Command | Where to Add |
|-------------|----------|----------------|--------------|
| `jcmd` | Java | Switch base image from JRE to JDK: `FROM eclipse-temurin:21-jdk-alpine` | Dockerfile |
| `pprof` endpoint | Go | Add `import _ "net/http/pprof"` and expose debug port | Source code + Dockerfile |
| `py-spy` | Python | `pip install py-spy` + add `SYS_PTRACE` capability | Dockerfile + K8s securityContext |
| `clinic` / `0x` | Node.js | `npm install -g clinic 0x` | Dockerfile |
| `dotnet-trace` | .NET | `dotnet tool install -g dotnet-trace` | Dockerfile |
| `async-profiler` | Java | Download and mount: `COPY asprof /opt/asprof` | Dockerfile |

**Dockerfile examples to fix each:**

```dockerfile
# Java — switch FROM jre to jdk
FROM eclipse-temurin:21-jdk-alpine
# Now jcmd, jfr, jstack are all available

# Go — expose pprof (add to main.go)
# import _ "net/http/pprof"
# go func() { http.ListenAndServe(":6060", nil) }()

# Python — add py-spy
RUN pip install py-spy
# Plus in K8s: securityContext: { capabilities: { add: ["SYS_PTRACE"] } }

# Node.js — add clinic
RUN npm install -g clinic 0x

# .NET — add diagnostic tools
RUN dotnet tool install -g dotnet-trace && dotnet tool install -g dotnet-dump
ENV PATH="$PATH:/root/.dotnet/tools"
```

**If user cannot modify Dockerfile** (no rebuild possible), use `kubectl debug`:

```bash
# Attach debug container with JDK tools (no rebuild needed)
kubectl debug -it <pod> --image=eclipse-temurin:21-jdk-alpine --target=app -- jcmd 1 JFR.start ...

# Or for Go: run pprof from a sidecar
kubectl debug -it <pod> --image=golang:1.23 --target=app -- go tool pprof http://localhost:6060/debug/pprof/profile
```

If none of the above are possible, fall back to **metrics-based profiling**:

| Situation | Fallback Method |
|-----------|----------------|
| No `jcmd` in Java container | Use `JAVA_TOOL_OPTIONS=-XX:StartFlightRecording=...` env var at startup, or `kubectl debug` with JDK image |
| No pprof endpoint in Go | Analyze via `docker stats` (memory/CPU) + load test response times per service |
| No `py-spy` in Python container | Use `scalene` or add `cProfile` middleware in code |
| No `dotnet-trace` in .NET container | Use `DOTNET_EnableDiagnostics=1` env var + sidecar collector |
| No tools at all | **Metrics-based profiling**: use `docker stats`, per-service latency measurement, and load test results to identify the bottleneck by elimination |

**Metrics-based profiling (no tools needed):**
```bash
# Measure each service individually to find the slow one
for PORT in 8001 8002 8003 8004 8005; do
  AVG=$(curl -s -o /dev/null -w "%{time_total}" http://localhost:$PORT/health)
  echo "Port $PORT: ${AVG}s"
done

# Monitor container resource usage during load test
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

This approach identifies **which** service is the bottleneck without needing any profiler inside the container. Once identified, you can add profiling tools to that specific service's image for deeper analysis.

```bash
# Helper function: run command locally or in pod
run_cmd() {
  if [ "$ENV" = "k8s" ]; then
    kubectl exec $POD -n $NAMESPACE -- "$@"
  else
    "$@"
  fi
}

# Helper function: extract file from pod or use local path
extract_file() {
  SRC=$1; DST=$2
  if [ "$ENV" = "k8s" ]; then
    kubectl cp $POD:$SRC $DST -n $NAMESPACE
  else
    cp $SRC $DST
  fi
}

# Examples:
# run_cmd jcmd 1 JFR.start name=perf duration=60s filename=/tmp/app.jfr
# extract_file /tmp/app.jfr ./app.jfr
```

---

#### 🟧 Java (JVM) — JFR / JProfiler / async-profiler

```bash
# Option A: JProfiler CLI
jpenable --pid=<PID>
jpcontroller --pid=<PID> --snapshot /tmp/app_snapshot.jps
jpexport /tmp/app_snapshot.jps HotSpots /tmp/cpu_hotspots.xml
jpexport /tmp/app_snapshot.jps AllocationHotspots /tmp/memory_allocations.xml
jpexport /tmp/app_snapshot.jps Threads /tmp/threads_report.xml
jpexport /tmp/app_snapshot.jps Monitors /tmp/monitor_contention.xml

# Option B: JDK Flight Recorder (recommended, ~2% overhead)
jcmd <PID> JFR.start name=perf duration=60s filename=/tmp/app.jfr settings=profile

# Option C: async-profiler
./asprof -d 30 -f /tmp/cpu_flame.html <PID>          # CPU
./asprof -d 30 -e alloc -f /tmp/alloc_flame.html <PID>  # Memory
./asprof -d 30 -e lock -f /tmp/lock_flame.html <PID>    # Locks

# Quarkus native: JFR unavailable — use perf or Instruments
perf record -g -p <PID> sleep 30 && perf report --stdio
```

**Key events to extract:** `jdk.JavaMonitorEnter`, `jdk.ExecutionSample`, `jdk.ObjectAllocationSample`, `jdk.GCPhasePause`

---

#### 🟦 Go — pprof (built-in)

```bash
# Prerequisite: import _ "net/http/pprof" in service, expose debug port

# CPU profile (30s sample)
curl -o /tmp/cpu.pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Heap / memory profile
curl -o /tmp/heap.pprof http://localhost:6060/debug/pprof/heap

# Goroutine dump (detect leaks)
curl -o /tmp/goroutine.pprof http://localhost:6060/debug/pprof/goroutine

# Mutex contention
curl -o /tmp/mutex.pprof http://localhost:6060/debug/pprof/mutex

# Block profiling (I/O waits, channel ops)
curl -o /tmp/block.pprof http://localhost:6060/debug/pprof/block

# Analyze with go tool
go tool pprof -http=:8888 /tmp/cpu.pprof    # Interactive web UI
go tool pprof -top /tmp/heap.pprof           # Top memory consumers
go tool pprof -text /tmp/mutex.pprof         # Mutex contention

# Execution trace (scheduler, GC, goroutines)
curl -o /tmp/trace.out http://localhost:6060/debug/pprof/trace?seconds=10
go tool trace /tmp/trace.out
```

**Key things to look for:**
- `goroutine` count growing over time → goroutine leak
- `mutex` profile hot → lock contention
- `block` profile hot → channel/IO blocking
- `heap inuse_space` growing → memory leak

---

#### 🟫 Rust — perf / flamegraph / tokio-console

```bash
# CPU flamegraph (requires perf on Linux)
cargo install flamegraph
flamegraph -p <PID> --duration 30 -o /tmp/flame.svg

# Or with perf directly
perf record -g -p <PID> sleep 30
perf script | inferno-collapse-perf | inferno-flamegraph > /tmp/flame.svg

# Memory profiling with DHAT (requires rebuild)
# In Cargo.toml: [profile.release] debug = true
valgrind --tool=dhat ./target/release/service
# Then open dhat-out file in browser viewer

# heaptrack (Linux)
heaptrack -p <PID>
heaptrack_gui heaptrack.service.<PID>.gz

# Tokio async runtime diagnostics
# Add tokio-console dependency, then:
tokio-console http://localhost:6669

# macOS alternative (no perf)
xcrun xctrace record --template 'CPU Profiler' --attach <PID> --time-limit 30s
```

**Key things to look for:**
- Flamegraph dominated by single function → CPU bottleneck
- `tokio-console` showing tasks blocked > 1s → async contention
- heaptrack showing monotonic growth → memory leak
- `Arc<Mutex<>>` in hot path → lock contention

---

#### 🟩 Python — py-spy / memray / scalene

```bash
# CPU flamegraph (no restart needed, attaches to running process)
py-spy record -o /tmp/flame.svg --pid <PID> --duration 30

# Top-like live view
py-spy top --pid <PID>

# GIL contention analysis
py-spy record -o /tmp/gil.svg --pid <PID> --gil --duration 30

# Memory profiling with memray (requires restart with memray run)
memray run -o /tmp/mem.bin python app.py
memray flamegraph /tmp/mem.bin -o /tmp/mem_flame.html

# Lightweight memory tracking (add to code)
# import tracemalloc; tracemalloc.start()
# Then: tracemalloc.take_snapshot().statistics('lineno')[:10]

# Scalene — CPU + memory + GPU combined profiler
scalene --cpu --memory --outfile /tmp/scalene.html app.py

# asyncio debugging (add at startup)
# import asyncio; asyncio.get_event_loop().set_debug(True)
# PYTHONASYNCIODEBUG=1 python app.py
```

**Key things to look for:**
- `py-spy --gil` showing high GIL % → GIL is the bottleneck, need multiprocessing
- `memray` showing growth in specific allocator → memory leak
- Most time in `select()`/`recv()` → I/O bound (normal for async)
- Most time in Python code (not C extensions) → CPU bound, consider Cython/Rust extension

---

#### 🟪 .NET (CLR) — dotnet-trace / dotnet-counters / PerfView

```bash
# Real-time counters (ThreadPool, GC, HTTP)
dotnet-counters monitor -p <PID> --counters \
  System.Runtime,Microsoft.AspNetCore.Hosting,System.Net.Http

# Trace collection (like JFR for .NET)
dotnet-trace collect -p <PID> --duration 00:00:30 \
  --providers Microsoft-DotNETCore-SampleProfiler,Microsoft-Windows-DotNETRuntime

# Convert trace to speedscope format for flamegraph
dotnet-trace convert /tmp/trace.nettrace --format speedscope

# Heap dump
dotnet-dump collect -p <PID> -o /tmp/dump.dmp

# Analyze heap dump
dotnet-dump analyze /tmp/dump.dmp
# > dumpheap -stat
# > gcroot <address>

# GC analysis
dotnet-counters monitor -p <PID> --counters System.Runtime[gen-0-gc-count,gen-1-gc-count,gen-2-gc-count,gc-heap-size]

# EventPipe for thread pool starvation
dotnet-trace collect -p <PID> --providers \
  System.Threading.ThreadPool:0x0:5
```

**Key things to look for:**
- `threadpool-thread-count` growing → ThreadPool starvation (sync-over-async)
- `gen-2-gc-count` high → LOH pressure, likely large allocations
- `dotnet-dump dumpheap -stat` showing growing type → memory leak
- High `monitor-lock-contention-count` → lock contention

---

#### 🟨 Node.js — clinic / 0x / node --inspect / --prof

```bash
# CPU profiling with built-in V8 profiler
node --prof app.js
# After load test, process the log:
node --prof-process isolate-*.log > /tmp/cpu_profile.txt

# CPU flamegraph with 0x (zero overhead when not sampling)
npx 0x -o /tmp/flame.html app.js
# Or attach to running process:
kill -USR1 <PID>  # Enable inspector on running Node process
# Then connect Chrome DevTools: chrome://inspect

# Clinic.js suite (auto-generates flamegraph + recommendations)
npx clinic flame -- node app.js        # CPU flamegraph
npx clinic doctor -- node app.js       # Auto-diagnosis
npx clinic bubbleprof -- node app.js   # Async delays visualization

# Heap snapshot (memory leak detection)
kill -USR2 <PID>  # If node started with --heapsnapshot-signal=SIGUSR2
# Or via inspector:
node --inspect app.js
# Then in Chrome DevTools → Memory → Take Heap Snapshot

# Programmatic heap dump
# Add to code: require('v8').writeHeapSnapshot('/tmp/heap.heapsnapshot')

# Event loop monitoring (detect blocking)
# Install: npm install blocked-at
# In code: require('blocked-at')((time, stack) => console.warn(`Blocked ${time}ms`, stack))

# Built-in diagnostics channel (Node 16+)
node --experimental-diagnostics-channel app.js

# Garbage collection tracing
node --trace-gc app.js 2>&1 | grep -E "Scavenge|Mark-Compact"
# Or: node --expose-gc --trace-gc-verbose app.js

# Active handles/requests (detect resource leaks)
# In code: process._getActiveHandles().length, process._getActiveRequests().length

# Prometheus metrics (for Express/NestJS)
# curl http://localhost:3000/metrics | grep -E "event_loop|heap|active_handles"
```

**Key things to look for:**
- Event loop blocked > 100ms → Synchronous operation in async path (JSON.parse on large payload, crypto, RegExp)
- Heap growing after GC → Memory leak (closures holding references, event listeners not removed)
- Active handles count growing → Socket/timer/file descriptor leak
- Mark-Compact GC pauses > 100ms → Large old-gen heap, consider `--max-old-space-size`
- High `libuv` thread pool saturation → Sync I/O (fs, dns) exhausting the 4 default UV threads

### Step 3: Advanced Deep-Dive Diagnostics

Parse exported data through 3 critical lenses:

#### A. CPU & Thread Contention Analysis

| Check | Action | Threshold |
|-------|--------|-----------|
| CPU Hotspots | Parse `cpu_hotspots.xml` or JFR `jdk.ExecutionSample` — flag methods with `total_time_percent > 20%` | > 20% of CPU in single business method |
| Blocked Threads | Scan `threads_report.xml` or JFR `jdk.JavaMonitorEnter` for `BLOCKED` / `WAITING` states | Any thread blocked > 5s |
| Synchronized Methods | Identify `synchronized` in hot path | Any synchronized method called > 100/s |
| Thread Pool Saturation | Check active vs max threads | Active/Max > 90% |
| Virtual Thread Pinning | Check `-Djdk.tracePinnedThreads=full` output | Any pinned VT in request path |

#### B. Garbage Collection & Memory Leak Analysis

| Check | Threshold | Diagnosis |
|-------|-----------|-----------|
| Post-GC baseline trending UP | Monotonic increase over 10+ GC cycles | **Memory Leak** — identify growing object types |
| GC pause time | STW pauses > 5% of total execution time | Trigger JVM tuning (switch to ZGC/G1GC) |
| Heap allocation rate | > 1GB/s sustained | Excessive object creation in hot path |
| Old Gen occupancy | > 80% after Full GC | Leak confirmed — take heap dump |
| Humongous allocations (G1) | Objects > 50% region size | Large arrays/buffers in hot path |

**Memory leak detection:**
```bash
# Take heap dump (⚠️ causes STW pause — see Safety Protocol)
jcmd <PID> GC.heap_dump /tmp/heap.hprof

# Analyze with Eclipse MAT or jhat
# Look for: dominator tree, leak suspects, retained heap by class
```

#### C. Database & Connection Pool Analysis

| Check | Tool | Red Flag |
|-------|------|----------|
| Slow queries | `pg_stat_statements` | `mean_exec_time > 100ms` |
| Missing indexes | `EXPLAIN ANALYZE` | Sequential Scan on table > 10K rows |
| Connection pool starvation | HikariCP metrics | `hikaricp_connections_pending > 0` sustained |
| Connection hold time | HikariCP metrics | `hikaricp_connections_usage_seconds_p99 > 1s` |
| Lock waits | `pg_stat_activity` | `wait_event_type = 'Lock'` |

**Connection pool sizing formula:**
```
pool_size = (core_count * 2) + effective_spindle_count
Example: 4-core server with SSD → pool_size = (4 * 2) + 1 = 9 (minimum)
```

```sql
-- PostgreSQL: find slow queries
SELECT query, mean_exec_time, calls, rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;

-- Find missing indexes
SELECT schemaname, tablename, seq_scan, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan AND seq_scan > 1000
ORDER BY seq_scan DESC;

-- Active locks
SELECT pid, usename, query, wait_event_type, state
FROM pg_stat_activity
WHERE state != 'idle' AND wait_event_type IS NOT NULL;
```

#### D. Redis Diagnostics

```bash
# Slow commands log
redis-cli SLOWLOG GET 10

# Memory overview
redis-cli INFO memory

# Find large keys (key space analysis)
redis-cli --bigkeys

# Connection count monitoring
redis-cli INFO clients

# Cache hit/miss ratio (effectiveness check)
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Count keys without TTL (memory leak risk)
redis-cli --scan | xargs -L 1 redis-cli TTL | grep -c "^-1$"

# Memory for specific key
redis-cli MEMORY USAGE <key>
```

#### E. Kafka Consumer Health

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Consumer lag (messages) | < 100 | 100–1000 | > 1000 |
| Lag growth rate | 0 (stable) | Slow growth | Accelerating |
| Rebalance frequency | < 1/hour | 1–5/hour | > 5/hour |
| Processing time per message | < 50ms | 50–500ms | > 500ms |

```bash
# Check consumer lag
kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group <group-id>

# Monitor lag over time
watch -n 5 "kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group <group-id>"
```

### Step 4: Root Cause Analysis

**Action:** Synthesize data from Steps 1-3 into precise architectural conclusions.

Map each performance symptom to exact code location:

| Symptom | Root Cause Pattern |
|---------|-------------------|
| High p99 latency | Specific code file + line (e.g., `OrderService.java:42 — N+1 query`) |
| Throughput plateau | Pool starvation or lock contention (exact pool/lock identified) |
| Memory growth | Specific collection/cache growing unbounded (class + field identified) |
| Error spike under load | Connection timeout (pool config identified) |
| Kafka consumer lag | Sequential processing bottleneck (consumer class identified) |

**Output format:**
```json
{
  "summary": {
    "overallSeverity": "critical",
    "sloBreaches": ["p99", "throughput"],
    "immediateActionRequired": true,
    "estimatedImpact": "System unstable above 300 VUs",
    "totalFindings": 5,
    "criticalCount": 2,
    "highCount": 2,
    "mediumCount": 1
  },
  "rootCauses": [
    {
      "symptom": "p99 latency 3200ms at 500 VUs",
      "cause": "Full table scan + N+1 in OrderService.getAllOrdersWithItems()",
      "file": "com/perflab/order/service/OrderService.java",
      "line": 42,
      "evidence": "pg_stat_statements shows mean_exec_time=450ms; JFR jdk.JavaMonitorEnter shows 2.39s lock wait on OrderService",
      "severity": "critical",
      "fixEffort": "low",
      "estimatedImprovement": "p99 reduction 60-90%"
    }
  ]
}
```

### Step 5: Actionable Remediation

Provide concrete Java-specific solutions:

| Type | Example |
|------|---------|
| Code refactor | Before/after Java snippets |
| SQL optimization | `CREATE INDEX`, query rewrite |
| JVM tuning | GC flags, heap sizing |
| Config change | Pool sizes, timeouts, thread counts |
| Architecture | Caching layer, async processing, pagination |

---

## Bottleneck Detection Rules

### Database

| Pattern | Detection | Severity |
|---------|-----------|----------|
| N+1 Query | `@OneToMany(fetch=LAZY)` + loop accessing collection without `JOIN FETCH` | critical |
| Missing Index | Query on non-PK field + `pg_stat_user_tables.seq_scan > idx_scan` | high |
| No Pagination | `findAll()` / `listAll()` returning unbounded `List<>` | high |
| Pool Starvation | `maximum-pool-size ≤ 3` with concurrent requests | critical |
| TX holds external call | `Thread.sleep()` or HTTP call inside `@Transactional` | critical |
| No Optimistic Lock | Read-modify-write without `@Version` | medium |

### Kafka

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Synchronous Send | `.send().get()` blocking caller | high |
| Sequential Consumer | `@Blocking` without `max-concurrency` or virtual threads | high |
| No Batching | Single-message processing in loop | medium |

> **Note on `@Blocking`:** In Quarkus SmallRye Reactive Messaging, `@Blocking` moves message processing to a worker thread but defaults to sequential (one message at a time). To parallelize, set `mp.messaging.incoming.<channel>.max-concurrency=N` or use `@RunOnVirtualThread`.

### Redis

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Missing TTL | `set()` without expiry | high |
| Unbounded List | `rpush` without `ltrim` | high |
| Full Fetch | `lrange(0, -1)` on growing list | medium |
| No Pipeline | Multiple sequential Redis calls without pipeline/batch | medium |

### REST / HTTP

| Pattern | Detection | Severity |
|---------|-----------|----------|
| No Timeout | `RestTemplate` / HTTP client without timeout config | high |
| No Pagination | GET returning full `List<>` | high |
| Unbounded Cache | `ConcurrentHashMap` without eviction | high |

### Memory

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Growing Collection | Field in singleton bean that only adds | critical |
| No Eviction | In-memory cache without max size / TTL | high |

### Concurrency

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Global synchronized | `synchronized` on service method | critical |
| Undersized Pool | Pool < concurrent callers | high |

### Architecture (Multi-Service)

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Sequential fan-out | Gateway calls N services one-by-one (latency = sum of all) | critical |
| No circuit breaker | One slow downstream blocks all requests | high |
| Chatty communication | Many small REST calls instead of batch/aggregate | high |
| Synchronous chain | A → B → C → D all blocking (latency = chain length × avg) | high |
| No timeout on outbound calls | HTTP client without timeout → hangs if downstream is slow | high |
| Single point of failure | All traffic through one instance with no fallback | critical |
| Missing retry with backoff | Transient failures cascade without retry logic | medium |
| No caching at gateway | Same data fetched from downstream on every request | medium |

**Detection for sequential fan-out:**
- Load test shows: latency at low load ≈ sum of individual service latencies
- Breakpoint test: throughput plateaus even though individual services are fast
- Source code: loop calling services without goroutines/async/parallel

---

## Language-Specific Bottleneck Patterns

### Go

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Goroutine leak | `pprof/goroutine` count grows over time | critical |
| Mutex contention | `pprof/mutex` shows hot lock in request path | high |
| Channel blocking | `pprof/block` shows goroutines stuck on channel ops | high |
| No context timeout | `http.Get()` without `context.WithTimeout` | high |
| Sync.Pool misuse | Allocating inside Pool.New with large objects | medium |
| JSON marshal in hot path | `encoding/json` bottleneck in profiler | medium |
| Unbounded goroutine spawn | `go func()` without semaphore/worker pool | high |

### Rust

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Blocking in async | `std::thread::sleep` or sync I/O inside `async fn` | critical |
| Mutex in async | `std::sync::Mutex` held across `.await` point | critical |
| Unbounded channel | `tokio::sync::mpsc::unbounded_channel` growing | high |
| Clone in hot path | Excessive `.clone()` on large structs in flamegraph | medium |
| Arc<Mutex<>> contention | Lock visible in flamegraph under high concurrency | high |
| No connection pooling | Creating new DB connection per request | critical |

### Python

| Pattern | Detection | Severity |
|---------|-----------|----------|
| GIL contention | `py-spy --gil` shows > 50% GIL wait | critical |
| Sync in async loop | Blocking call inside `async def` without `run_in_executor` | critical |
| No worker processes | Single gunicorn/uvicorn worker for CPU-bound app | high |
| ORM N+1 | SQLAlchemy lazy load in loop (same as Java) | high |
| Global interpreter lock | CPU-bound code in Python (not C extension) | high |
| Memory leak | `tracemalloc` shows monotonic growth in specific module | high |
| No connection pool | Creating new DB connection per request | critical |

### .NET

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Sync-over-async | `.Result` or `.Wait()` on Task — ThreadPool starvation | critical |
| ThreadPool exhaustion | `threadpool-thread-count` growing, queue depth high | critical |
| LOH fragmentation | Gen 2 GC frequent + large array allocations | high |
| EF Core N+1 | Lazy loading in loop without `.Include()` | high |
| No HttpClient reuse | `new HttpClient()` per request — socket exhaustion | critical |
| Lock in request path | `lock(obj)` in controller/service hot path | high |
| Missing async/await | Sync DB calls blocking ThreadPool threads | high |

### Node.js

| Pattern | Detection | Severity |
|---------|-----------|----------|
| Event loop blocking | Sync operation > 100ms (JSON.parse large, crypto, RegExp) | critical |
| No connection pooling | Creating new DB connection per request | critical |
| Memory leak via closures | Heap grows monotonically, active handles increase | critical |
| Sync file I/O | `fs.readFileSync` / `fs.writeFileSync` in request path | high |
| UV thread pool exhaustion | Default 4 threads saturated by DNS/fs/crypto | high |
| Unhandled promise accumulation | Promises created without await/catch — backpressure | high |
| Large payload in event loop | `JSON.stringify` on large objects blocking loop | high |
| No stream for large responses | Loading full file/query into memory before sending | medium |
| Missing `keep-alive` on HTTP clients | New TCP connection per outbound request | medium |
| Event listener leak | `emitter.on()` without `removeListener` — OOM over time | high |

---

## Configuration Red Flags

### Spring Boot

| Config | Healthy | Red Flag | Formula |
|--------|---------|----------|---------|
| `hikari.maximum-pool-size` | 10–50 | ≤ 3 | `(cores * 2) + spindles` |
| `hikari.connection-timeout` | 5000–10000 | > 30000 | — |
| `tomcat.threads.max` | 200 | < 10 | — |
| `kafka.producer.acks` | `1` or `all` | — | — |

### Quarkus

| Config | Healthy | Red Flag | Formula |
|--------|---------|----------|---------|
| `datasource.jdbc.max-size` | 10–50 | ≤ 3 | `(cores * 2) + spindles` |
| `datasource.jdbc.min-size` | 2–5 | 0–1 | — |
| `redis.max-pool-size` | 6–24 | ≤ 2 | — |
| `mp.messaging.incoming.*.max-concurrency` | > 1 | not set (defaults to 1) | — |

---

## Runtime Tuning Reference

### Java (JVM)

```bash
-XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:G1HeapRegionSize=16m
-XX:+UseZGC -XX:+ZGenerational -Xmx4g          # Java 21+ only
-Xms2g -Xmx4g -XX:MetaspaceSize=256m
-Xlog:gc*:file=gc.log:time,uptime,level,tags    # Java 9+ (replaces -verbose:gc)
-Djdk.tracePinnedThreads=full                   # Java 21+ (Virtual Threads)
-XX:StartFlightRecording=disk=true,maxage=24h,maxsize=1g,dumponexit=true,filename=app.jfr  # Java 11+
```

### Go

```bash
# GC tuning
GOGC=200              # Less frequent GC (default 100). Higher = less GC, more memory
GOMEMLIMIT=2GiB       # Hard memory limit (Go 1.19+)

# Concurrency
GOMAXPROCS=4          # Limit OS threads (defaults to CPU count)

# Debugging
GOTRACEBACK=all       # Full goroutine dump on crash
GODEBUG=gctrace=1     # GC trace logging
GODEBUG=schedtrace=1000  # Scheduler trace every 1s

# Build optimizations
go build -ldflags="-s -w"    # Strip debug info for production
go build -race               # Race detector (dev/test only, 10x slower)
```

### Rust

```bash
# Release profile (Cargo.toml)
[profile.release]
opt-level = 3
lto = true
codegen-units = 1

# Tokio runtime tuning (in code)
#[tokio::main(flavor = "multi_thread", worker_threads = 8)]

# Memory allocator (switch from system to jemalloc)
# In Cargo.toml: tikv-jemallocator = "0.5"

# Environment
RUST_LOG=warn                  # Reduce log overhead
RUST_BACKTRACE=1               # Enable backtraces
TOKIO_CONSOLE_BIND=0.0.0.0:6669  # tokio-console
```

### Python

```bash
# Uvicorn/Gunicorn workers
gunicorn -w $(nproc) -k uvicorn.workers.UvicornWorker app:app  # CPU count workers
uvicorn app:app --workers 4 --limit-concurrency 100

# GC tuning
PYTHONGC=0               # Disable GC (if managing memory manually)
# Or in code: gc.set_threshold(50000, 500, 100)

# asyncio tuning
PYTHONASYNCIODEBUG=1     # Debug mode (dev only)
uvloop                    # Drop-in faster event loop: asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())

# Memory limits (container)
# Use --memory=2g in Docker to hard-cap
```

### .NET

```bash
# GC modes
DOTNET_gcServer=1                    # Server GC (multi-threaded, for servers)
DOTNET_GCHeapCount=4                 # Limit GC heaps
DOTNET_GCConserveMemory=5            # 0-9, higher = less memory usage

# ThreadPool tuning
DOTNET_ThreadPool_MinThreads=50      # Pre-warm thread pool
DOTNET_ThreadPool_MaxThreads=200

# Runtime
DOTNET_TieredCompilation=1           # JIT optimization (default on)
DOTNET_ReadyToRun=1                  # Pre-compiled code

# Diagnostics
DOTNET_EnableDiagnostics=1
COMPlus_EnableEventPipe=1            # Always-on tracing
```

### Node.js

```bash
# Memory limits
node --max-old-space-size=4096 app.js        # Heap limit in MB (default ~1.5GB)
node --max-semi-space-size=64 app.js         # Young gen size (faster minor GC)

# UV thread pool (default 4 — too low for heavy I/O)
UV_THREADPOOL_SIZE=16 node app.js            # Increase for fs/dns/crypto heavy apps

# GC tuning
node --expose-gc --gc-interval=100 app.js    # More frequent GC (lower pause)
node --optimize-for-size app.js              # Trade speed for less memory

# Cluster mode (use all CPU cores)
# In code: cluster.fork() per CPU, or use PM2:
pm2 start app.js -i max                      # One worker per CPU core

# Enable inspector for profiling (without stopping)
node --inspect=0.0.0.0:9229 app.js           # Chrome DevTools attach
kill -USR1 <PID>                             # Enable inspector on running process

# Heap snapshot on OOM
node --heapsnapshot-near-heap-limit=3 app.js # Auto-dump before OOM (Node 16+)
node --heapsnapshot-signal=SIGUSR2 app.js    # Dump on signal

# DNS optimization (avoid UV thread pool for DNS)
# In code: dns.setDefaultResultOrder('ipv4first')

# HTTP keep-alive for outbound requests
# In code: new http.Agent({ keepAlive: true, maxSockets: 50 })
```

---

## Response Format

When presenting findings, use this structure:

### 1. Load Test Summary

Comparison table of actual metrics vs SLO targets:

| Metric | SLO Target | Actual | Status |
|--------|-----------|--------|--------|
| Response Time p95 | < 200ms | ? | ✅/❌ |
| Response Time p99 | < 500ms | ? | ✅/❌ |
| Throughput (RPS) | > 1000 | ? | ✅/❌ |
| Error Rate | < 0.1% | ? | ✅/❌ |

### 2. Java Profiler & JVM Insights

- CPU Hotspots — hottest methods by total time percentage
- Memory Allocation Sites — top allocating methods and object types
- Thread State Distribution — Blocked/Waiting/Runnable breakdown
- GC Health — pause frequency, duration, memory leak indicators

### 3. Database & Infrastructure Deep Dive

- Slow queries + indexing needs
- Connection Pool status (HikariCP / Agroal utilization)
- Kafka consumer lag and throughput
- Redis memory usage, hit/miss ratio, and slow commands

### 4. Root Cause & Identified Bottlenecks

Overall system verdict:
- Overall severity (critical / high / medium)
- SLO breaches list
- Immediate action required (yes/no)

Per-finding documentation:
- Guilty file / class / method (with line number)
- Supporting evidence (metrics + profiler data)
- System impact (latency, throughput, stability)

### 5. Actionable Technical Solutions

Prioritized remediation plan:
1. **Immediate (Config):** Configuration changes requiring zero code (pool sizes, timeouts, JVM flags)
2. **Short-term (Code):** Refactor problematic methods (before/after code snippets)
3. **Mid-term (Architecture):** Structural changes (caching layers, async processing, pagination)

Include refactored Java code, SQL statements (`CREATE INDEX`), and JVM tuning flags.

---

## HTML Report Output

After completing analysis, **always generate an HTML report file** (`report.html`) in the project directory and open it in the default browser.

**Required elements:**
- Dark/light theme toggle (default: dark, respects `prefers-color-scheme`)
- Verdict banner at top (green = all pass, red = critical failures, yellow = warnings)
- Gauge dials for key metrics (p95, p99, throughput, error rate)
- Load test summary table with pass/fail badges
- Service chain table with color-coded language badges per service
- Language distribution cards (if multi-language)
- Latency percentile distribution
- Root cause findings with severity badges (if bottlenecks found)
- Remediation section with collapsible before/after code (if fixes needed)
- Next steps / recommendations
- Footer with timestamp, tools used, and platform info

**Language badge colors:**
- Java: `#f89820` (orange)
- Go: `#00ADD8` (cyan)
- Rust: `#CE422B` (red)
- Python: `#3776AB` (blue)
- Node.js: `#339933` (green)
- .NET: `#512BD4` (purple)

**Auto-open after generation:**
```bash
open report.html          # macOS
xdg-open report.html     # Linux
start report.html        # Windows
```

---

## Profiling-Ready Infrastructure (Docker Compose)

Instead of installing tools at runtime, **bake profiling readiness into docker-compose** so every restart is profile-ready:

```yaml
services:
  # Java: auto-start JFR recording, dump to mounted volume
  java-service:
    environment:
      JAVA_TOOL_OPTIONS: "-XX:StartFlightRecording=disk=true,maxage=5m,maxsize=100m,dumponexit=true,filename=/app/logs/service.jfr"
    volumes:
      - ./logs:/app/logs

  # Python: add SYS_PTRACE so py-spy can attach
  python-service:
    cap_add:
      - SYS_PTRACE
    volumes:
      - ./logs:/app/logs

  # Node.js: enable inspector for Chrome DevTools / heap snapshots
  node-service:
    ports:
      - "9229:9229"
    environment:
      NODE_OPTIONS: "--inspect=0.0.0.0:9229"

  # Go: enable GC tracing via logs
  go-service:
    environment:
      GODEBUG: "gctrace=1"

  # .NET: enable EventPipe diagnostics
  dotnet-service:
    environment:
      DOTNET_EnableDiagnostics: "1"
      COMPlus_EnableEventPipe: "1"

  # Rust: no runtime config needed (use perf/flamegraph externally)
```

**Collecting data after load test:**

```bash
# Java: dump JFR from running container
docker exec <java-container> jcmd 1 JFR.dump name=1 filename=/app/logs/service.jfr

# Python: run py-spy flamegraph (SYS_PTRACE already granted)
docker exec <python-container> py-spy record -d 10 -o /tmp/flame.svg --pid 1
docker cp <python-container>:/tmp/flame.svg ./logs/

# Node.js: connect Chrome DevTools to localhost:9229 for heap/CPU profile

# Go: GC trace is in container logs
docker logs <go-container> 2>&1 | grep "^gc"

# .NET: collect trace (if dotnet-trace installed in image)
docker exec <dotnet-container> dotnet-trace collect -p 1 --duration 00:00:10 -o /tmp/trace.nettrace
```

> **Rule:** If you control the docker-compose or Helm chart, always add these environment variables proactively. It costs nothing at rest but saves 10+ minutes when profiling is needed.

---

## Kubernetes Operations

When `detect_environment` returns `k8s`, use these patterns instead of direct local commands:

### Profiling in K8s

```bash
# Resolve pod
POD=$(kubectl get pods -l app=order-service -n $NS -o jsonpath='{.items[0].metadata.name}')

# Java JFR
kubectl exec $POD -n $NS -- jcmd 1 JFR.start name=perf duration=60s filename=/tmp/app.jfr
# ... run load test ...
kubectl exec $POD -n $NS -- jcmd 1 JFR.stop name=perf
kubectl cp $NS/$POD:/tmp/app.jfr ./app.jfr

# Java thread dump
kubectl exec $POD -n $NS -- jcmd 1 Thread.print > threads.txt

# Java heap dump (⚠️ ensure memory headroom)
kubectl exec $POD -n $NS -- jcmd 1 GC.heap_dump /tmp/heap.hprof
kubectl cp $NS/$POD:/tmp/heap.hprof ./heap.hprof

# Go pprof (port-forward)
kubectl port-forward $POD 6060:6060 -n $NS &
curl -o cpu.pprof http://localhost:6060/debug/pprof/profile?seconds=30
curl -o heap.pprof http://localhost:6060/debug/pprof/heap
curl -o goroutine.pprof http://localhost:6060/debug/pprof/goroutine
kill %1  # stop port-forward

# Python py-spy (requires SYS_PTRACE capability)
kubectl exec $POD -n $NS -- py-spy record -o /tmp/flame.svg --pid 1 --duration 30
kubectl cp $NS/$POD:/tmp/flame.svg ./flame.svg

# .NET
kubectl exec $POD -n $NS -- dotnet-trace collect -p 1 --duration 00:00:30 -o /tmp/trace.nettrace
kubectl cp $NS/$POD:/tmp/trace.nettrace ./trace.nettrace
```

### Load Testing Against K8s

```bash
# Option 1: Port-forward (dev/testing)
kubectl port-forward svc/order-service 8081:8081 -n $NS &
k6 run --vus 50 --duration 30s -e BASE_URL=http://localhost:8081 loadtest.js

# Option 2: Via Ingress (staging/production-like)
INGRESS=$(kubectl get ingress -n $NS -o jsonpath='{.items[0].spec.rules[0].host}')
k6 run --vus 50 --duration 30s -e BASE_URL=https://$INGRESS loadtest.js

# Option 3: In-cluster k6 job (no port-forward needed)
kubectl run k6-load --image=grafana/k6 --restart=Never -n $NS -- run - <loadtest.js
```

### Metrics in K8s

```bash
# Prometheus metrics (port-forward to pod)
kubectl port-forward $POD 8081:8081 -n $NS &
curl localhost:8081/actuator/prometheus | grep hikari

# Or query Prometheus directly if installed
kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
# Then query: http://localhost:9090/api/v1/query?query=hikaricp_connections_pending

# Kafka consumer lag (exec into Kafka pod)
KAFKA_POD=$(kubectl get pods -l app=kafka -n $NS -o jsonpath='{.items[0].metadata.name}')
kubectl exec $KAFKA_POD -n $NS -- kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group inventory-group

# Redis (exec into Redis pod)
REDIS_POD=$(kubectl get pods -l app=redis -n $NS -o jsonpath='{.items[0].metadata.name}')
kubectl exec $REDIS_POD -n $NS -- redis-cli INFO memory
kubectl exec $REDIS_POD -n $NS -- redis-cli --bigkeys
```

### K8s Debug Containers (no tools in image)

```bash
# Attach ephemeral debug container with profiling tools (K8s 1.25+)
kubectl debug -it $POD -n $NS --image=eclipse-temurin:21 --target=app -- jcmd 1 Thread.print

# Or with async-profiler image
kubectl debug -it $POD -n $NS --image=jvm-profiling-tools/async-profiler --target=app -- \
  /opt/asprof -d 30 -f /tmp/flame.html 1
```

### Required Pod Security

```yaml
# For py-spy, perf, strace — add to container securityContext:
securityContext:
  capabilities:
    add: ["SYS_PTRACE"]

# For perf — may also need:
securityContext:
  privileged: true  # last resort, avoid in production
```

---

## Quick Reference Commands

```bash
# Start infrastructure
docker-compose up -d

# Load test (with ramp-up)
k6 run --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)" loadtest.js

# JProfiler CLI (full flow)
jpenable --pid=<PID>
jpcontroller --pid=<PID> --snapshot /tmp/snapshot.jps
jpexport /tmp/snapshot.jps HotSpots /tmp/hotspots.xml
jpexport /tmp/snapshot.jps AllocationHotspots /tmp/alloc.xml
jpexport /tmp/snapshot.jps Threads /tmp/threads.xml
jpexport /tmp/snapshot.jps Monitors /tmp/monitors.xml

# JFR (attach to running process)
jcmd <PID> JFR.start name=perf duration=60s filename=/tmp/app.jfr settings=profile

# async-profiler
./asprof -d 30 -f flame.html <PID>
./asprof -d 30 -e alloc -f alloc.html <PID>
./asprof -d 30 -e lock -f lock.html <PID>

# Thread dump (two alternatives)
jcmd <PID> Thread.print > threads.txt
jstack <PID> > threads.txt

# Heap dump (⚠️ STW pause)
jcmd <PID> GC.heap_dump /tmp/heap.hprof

# PostgreSQL diagnostics
psql -c "SELECT query, mean_exec_time, calls FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
psql -c "SELECT schemaname, tablename, seq_scan, idx_scan FROM pg_stat_user_tables WHERE seq_scan > 1000 ORDER BY seq_scan DESC;"

# Kafka consumer lag
kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group <group-id>

# Redis diagnostics
redis-cli SLOWLOG GET 10
redis-cli INFO memory
redis-cli --bigkeys
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Prometheus metrics (Spring Boot)
curl localhost:8081/actuator/prometheus | grep -E "hikari|http_server"

# Prometheus metrics (Quarkus)
curl localhost:8082/q/metrics | grep -E "db_pool|http_server|worker_pool"
```

## Supported Languages & Runtimes

| Language | Runtime | Profiler | Frameworks |
|----------|---------|----------|-----------|
| Java | JVM (HotSpot, GraalVM) | JFR (11+), JProfiler, async-profiler | Spring Boot, Quarkus, Micronaut |
| Go | Go runtime | pprof (built-in), go tool trace | Gin, Fiber, Echo, net/http |
| Rust | Tokio, async-std | perf, flamegraph, tokio-console | Actix-web, Axum, Rocket |
| Python | CPython, PyPy | py-spy, memray, scalene | FastAPI, Django, Flask |
| Node.js | V8 (libuv) | clinic, 0x, --prof, Chrome DevTools | Express, NestJS, Fastify |
| .NET | CLR | dotnet-trace, dotnet-dump, PerfView | ASP.NET Core, Minimal APIs |

> **Version policy:** This skill is version-agnostic. The methodology and tools work across all actively supported versions. Where a feature requires a minimum version (e.g., Virtual Threads = Java 21+, GOMEMLIMIT = Go 1.19+), it is noted inline.

## Infrastructure

- PostgreSQL, MySQL, Redis, Apache Kafka (any actively supported version)
- k6, Gatling, JMeter (load testing)
- Prometheus, Grafana, OpenTelemetry (observability)
