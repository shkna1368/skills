#!/bin/bash
# Runtime Energy Analysis — applies load test then measures resource consumption
# Cross-platform: Linux, macOS, Windows (Git Bash / WSL)
set -euo pipefail

PROJECT_ROOT="${1:-.}"
ENDPOINT="${2:-http://localhost:8000}"
DURATION="${3:-30}"
CONCURRENCY="${4:-10}"
METHOD="${5:-}"
BODY="${6:-}"
OUTPUT_DIR="$PROJECT_ROOT/energy-report"
OUTPUT_FILE="$OUTPUT_DIR/runtime-analysis.json"

mkdir -p "$OUTPUT_DIR"

# --- Auto-detect method and body if not provided ---
if [ -z "$METHOD" ]; then
  # Check if the project has a README with a curl example
  if grep -q "POST.*api/" "$PROJECT_ROOT/README.md" 2>/dev/null; then
    METHOD="POST"
    BODY=$(grep -A2 '\-d ' "$PROJECT_ROOT/README.md" 2>/dev/null | grep -oE '\{[^}]+\}' | head -1 || echo "")
    [ -z "$BODY" ] && BODY=$(grep "\-d '" "$PROJECT_ROOT/README.md" 2>/dev/null | grep -oE "'\{[^']+\}'" | head -1 | tr -d "'" || echo "")
    echo "🔎 Auto-detected POST endpoint from README"
    [ -n "$BODY" ] && echo "   Payload: ${BODY:0:80}..."
  else
    METHOD="GET"
  fi
fi

# --- Discover all endpoints and ports ---
echo "🔎 Discovering endpoints..."
DISCOVERED_ENDPOINTS="$OUTPUT_DIR/.discovered-endpoints.txt"
> "$DISCOVERED_ENDPOINTS"

# 1. Scan docker-compose for exposed ports
COMPOSE_FILE=""
[ -f "$PROJECT_ROOT/docker-compose.yml" ] && COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
[ -f "$PROJECT_ROOT/docker-compose.yaml" ] && COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yaml"
[ -f "$PROJECT_ROOT/compose.yml" ] && COMPOSE_FILE="$PROJECT_ROOT/compose.yml"
if [ -n "$COMPOSE_FILE" ]; then
  grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?' "$COMPOSE_FILE" 2>/dev/null | grep -oE '[0-9]+:[0-9]+' | while read -r mapping; do
    HOST_PORT=$(echo "$mapping" | cut -d: -f1)
    echo "http://localhost:$HOST_PORT" >> "$DISCOVERED_ENDPOINTS"
  done
fi

# 2. Scan source code for route definitions
grep -rE '"(/api/[a-z/_-]+)"' "$PROJECT_ROOT" --include="*.go" --include="*.java" --include="*.py" --include="*.rs" --include="*.ts" --include="*.js" --include="*.cs" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target --exclude-dir=vendor --exclude-dir=energy-report \
  2>/dev/null | grep -oE '"/api/[a-z/_-]+"' | tr -d '"' | sort -u | while read -r route; do
    echo "ROUTE:$route" >> "$DISCOVERED_ENDPOINTS"
done

# 3. Look for health/readiness endpoints
grep -rE '"/(health|ready|alive|ping)[^"]*"' "$PROJECT_ROOT" --include="*.go" --include="*.java" --include="*.py" --include="*.rs" --include="*.ts" --include="*.js" --include="*.cs" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target --exclude-dir=vendor --exclude-dir=energy-report \
  2>/dev/null | grep -oE '"/(health|ready|alive|ping)[^"]*"' | tr -d '"' | sort -u | while read -r hc; do
    echo "HEALTH:$hc" >> "$DISCOVERED_ENDPOINTS"
done

# Summary
DISCOVERED_PORTS=$(grep -c "^http" "$DISCOVERED_ENDPOINTS" || true)
DISCOVERED_ROUTES=$(grep -c "^ROUTE:" "$DISCOVERED_ENDPOINTS" || true)
DISCOVERED_HEALTH=$(grep -c "^HEALTH:" "$DISCOVERED_ENDPOINTS" || true)
echo "   Found: $DISCOVERED_PORTS ports, $DISCOVERED_ROUTES routes, $DISCOVERED_HEALTH health endpoints"

# --- Cross-platform detection ---
detect_os() {
  case "$(uname -s 2>/dev/null || echo Windows)" in
    Darwin*)  echo "macos" ;;
    Linux*)   echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) echo "windows" ;;
    *)        echo "linux" ;;
  esac
}

OS=$(detect_os)
echo "⚡ Runtime Energy Analysis"
echo "   OS: $OS | Project: $PROJECT_ROOT"
echo "   Endpoint: $METHOD $ENDPOINT | Duration: ${DURATION}s | Concurrency: $CONCURRENCY"
[ -n "$BODY" ] && echo "   Body: ${BODY:0:80}..."

# --- Find a load testing tool ---
find_load_tool() {
  if command -v hey &>/dev/null; then echo "hey"
  elif command -v ab &>/dev/null; then echo "ab"
  elif command -v wrk &>/dev/null; then echo "wrk"
  elif command -v curl &>/dev/null; then echo "curl"
  else echo "none"
  fi
}

LOAD_TOOL=$(find_load_tool)
echo "   Load tool: $LOAD_TOOL"

# --- Ensure app is running ---
echo "🔗 Checking if application is running..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ENDPOINT" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "000" ]; then
  echo "⚠️  Endpoint $ENDPOINT not reachable. Starting application..."
  if [ -f "$PROJECT_ROOT/docker-compose.yml" ] || [ -f "$PROJECT_ROOT/docker-compose.yaml" ] || [ -f "$PROJECT_ROOT/compose.yml" ]; then
    (cd "$PROJECT_ROOT" && docker-compose up -d 2>/dev/null || docker compose up -d 2>/dev/null || true)
    echo "   Waiting 30s for services to start..."
    sleep 30
  fi
fi

# Verify all discovered service ports are responding
echo "   Verifying services..."
SERVICES_UP=0
SERVICES_DOWN=0
while read -r svc_url; do
  [ -z "$svc_url" ] && continue
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$svc_url" 2>/dev/null || echo "000")
  if [ "$code" != "000" ]; then
    SERVICES_UP=$((SERVICES_UP + 1))
  else
    SERVICES_DOWN=$((SERVICES_DOWN + 1))
  fi
done < <(grep "^http" "$DISCOVERED_ENDPOINTS" 2>/dev/null || true)
echo "   Services responding: $SERVICES_UP up, $SERVICES_DOWN down"

# Validate main endpoint with actual method/body
echo "   Validating main endpoint..."
if [ -n "$BODY" ]; then
  VALIDATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X "$METHOD" -H "Content-Type: application/json" -d "$BODY" "$ENDPOINT" 2>/dev/null || echo "000")
else
  VALIDATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X "$METHOD" "$ENDPOINT" 2>/dev/null || echo "000")
fi
echo "   Main endpoint: HTTP $VALIDATE_CODE"
if [ "$VALIDATE_CODE" -ge 500 ] 2>/dev/null; then
  echo "⚠️  Endpoint returned $VALIDATE_CODE — services may not be ready."
fi

# --- Snapshot resource usage at IDLE (before any load) ---
echo "📊 Capturing idle baseline (no load)..."
get_docker_stats() {
  docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" 2>/dev/null || echo ""
}

STATS_IDLE=$(get_docker_stats)

# --- Apply load test ---
echo "🔥 Applying load test (${DURATION}s, concurrency=$CONCURRENCY)..."
LOAD_START=$(python3 -c "import time; print(time.time())")
LOAD_OUTPUT="$OUTPUT_DIR/.load-output.txt"

case "$LOAD_TOOL" in
  hey)
    if [ -n "$BODY" ]; then
      hey -z "${DURATION}s" -c "$CONCURRENCY" -m "$METHOD" -H "Content-Type: application/json" -d "$BODY" "$ENDPOINT" > "$LOAD_OUTPUT" 2>&1 || true
    else
      hey -z "${DURATION}s" -c "$CONCURRENCY" -m "$METHOD" "$ENDPOINT" > "$LOAD_OUTPUT" 2>&1 || true
    fi
    ;;
  ab)
    TOTAL_REQ=$((DURATION * CONCURRENCY * 10))
    if [ -n "$BODY" ]; then
      echo "$BODY" > "$OUTPUT_DIR/.ab-body.json"
      ab -t "$DURATION" -c "$CONCURRENCY" -n "$TOTAL_REQ" -p "$OUTPUT_DIR/.ab-body.json" -T "application/json" "$ENDPOINT/" > "$LOAD_OUTPUT" 2>&1 || true
      rm -f "$OUTPUT_DIR/.ab-body.json"
    else
      ab -t "$DURATION" -c "$CONCURRENCY" -n "$TOTAL_REQ" "$ENDPOINT/" > "$LOAD_OUTPUT" 2>&1 || true
    fi
    ;;
  wrk)
    if [ -n "$BODY" ]; then
      # wrk needs a lua script for POST
      cat > "$OUTPUT_DIR/.wrk-post.lua" << WRKEOF
wrk.method = "$METHOD"
wrk.headers["Content-Type"] = "application/json"
wrk.body = [[$BODY]]
WRKEOF
      wrk -t"$CONCURRENCY" -c"$CONCURRENCY" -d"${DURATION}s" -s "$OUTPUT_DIR/.wrk-post.lua" "$ENDPOINT" > "$LOAD_OUTPUT" 2>&1 || true
      rm -f "$OUTPUT_DIR/.wrk-post.lua"
    else
      wrk -t"$CONCURRENCY" -c"$CONCURRENCY" -d"${DURATION}s" "$ENDPOINT" > "$LOAD_OUTPUT" 2>&1 || true
    fi
    ;;
  curl)
    for i in $(seq 1 "$CONCURRENCY"); do
      if [ -n "$BODY" ]; then
        (for _ in $(seq 1 $((DURATION * 2))); do curl -s -o /dev/null -X "$METHOD" -H "Content-Type: application/json" -d "$BODY" "$ENDPOINT"; done) &
      else
        (for _ in $(seq 1 $((DURATION * 2))); do curl -s -o /dev/null -X "$METHOD" "$ENDPOINT"; done) &
      fi
    done
    sleep "$DURATION"
    wait 2>/dev/null || true
    echo "Completed curl-based load test" > "$LOAD_OUTPUT"
    ;;
  none)
    echo "⚠️  No load tool found. Install 'hey' (recommended): go install github.com/rakyll/hey@latest"
    echo "   Measuring idle state instead."
    sleep "$DURATION"
    echo "No load tool available" > "$LOAD_OUTPUT"
    ;;
esac

LOAD_END=$(python3 -c "import time; print(time.time())")
LOAD_DURATION=$(python3 -c "print(round($LOAD_END - $LOAD_START, 2))")
echo "   Load test completed in ${LOAD_DURATION}s"

# --- Snapshot resource usage DURING/AFTER load ---
echo "📊 Capturing post-load measurements..."
STATS_AFTER=$(get_docker_stats)

# --- Parse load test results ---
parse_load_results() {
  local tool="$1" file="$2"
  case "$tool" in
    hey)
      RPS=$(grep "Requests/sec" "$file" | awk '{print $2}' || echo "0")
      AVG_LATENCY=$(grep "Average" "$file" | head -1 | awk '{print $2}' || echo "0")
      TOTAL_REQS=$(grep "^\[200\]" "$file" | awk '{print $2}' || grep "200 responses" "$file" | awk '{print $1}' || echo "0")
      [ -z "$TOTAL_REQS" ] || [ "$TOTAL_REQS" = "0" ] && TOTAL_REQS=$(grep "^  Total:" "$file" | awk '{print $2}' || echo "0")
      ;;
    ab)
      RPS=$(grep "Requests per second" "$file" | awk '{print $4}' || echo "0")
      AVG_LATENCY=$(grep "Time per request.*mean\)" "$file" | head -1 | awk '{print $4}' || echo "0")
      TOTAL_REQS=$(grep "Complete requests" "$file" | awk '{print $3}' || echo "0")
      ;;
    wrk)
      RPS=$(grep "Requests/sec" "$file" | awk '{print $2}' || echo "0")
      AVG_LATENCY=$(grep "Latency" "$file" | awk '{print $2}' || echo "0")
      TOTAL_REQS=$(grep "requests in" "$file" | awk '{print $1}' || echo "0")
      ;;
    *)
      RPS="0"; AVG_LATENCY="0"; TOTAL_REQS="0"
      ;;
  esac
  echo "$RPS|$AVG_LATENCY|$TOTAL_REQS"
}

LOAD_RESULTS=$(parse_load_results "$LOAD_TOOL" "$LOAD_OUTPUT")
LOAD_RPS=$(echo "$LOAD_RESULTS" | cut -d'|' -f1)
LOAD_LATENCY=$(echo "$LOAD_RESULTS" | cut -d'|' -f2)
LOAD_TOTAL_REQS=$(echo "$LOAD_RESULTS" | cut -d'|' -f3)

# Clean up numeric values
LOAD_RPS=$(echo "$LOAD_RPS" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "0")
LOAD_LATENCY=$(echo "$LOAD_LATENCY" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "0")
LOAD_TOTAL_REQS=$(echo "$LOAD_TOTAL_REQS" | grep -oE '[0-9]+' | head -1 || echo "0")
[ -z "$LOAD_RPS" ] && LOAD_RPS="0"
[ -z "$LOAD_LATENCY" ] && LOAD_LATENCY="0"
[ -z "$LOAD_TOTAL_REQS" ] && LOAD_TOTAL_REQS="0"

# --- Count project files ---
TOTAL_SOURCE_FILES=$(find "$PROJECT_ROOT" -type f \( -name "*.go" -o -name "*.java" -o -name "*.py" -o -name "*.rs" -o -name "*.ts" -o -name "*.js" -o -name "*.cs" \) ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/target/*" ! -path "*/vendor/*" ! -path "*/energy-report/*" 2>/dev/null | wc -l | tr -d ' ')
TOTAL_LINES=$(find "$PROJECT_ROOT" -type f \( -name "*.go" -o -name "*.java" -o -name "*.py" -o -name "*.rs" -o -name "*.ts" -o -name "*.js" -o -name "*.cs" \) ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/target/*" ! -path "*/vendor/*" ! -path "*/energy-report/*" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')

# Disk usage (cross-platform)
if [ "$OS" = "macos" ] || [ "$OS" = "linux" ]; then
  DISK_USAGE=$(du -sm "$PROJECT_ROOT" 2>/dev/null | awk '{print $1}' || echo "0")
else
  DISK_USAGE=$(du -sm "$PROJECT_ROOT" 2>/dev/null | awk '{print $1}' || echo "0")
fi

# --- Generate JSON with Python (cross-platform) ---
echo "📝 Generating runtime analysis report..."
python3 << PYEOF
import json, re, subprocess, sys
from datetime import datetime, timezone

def parse_size(s):
    """Parse size string like '490.4MiB', '2.377GiB', '14.81kB' to MB"""
    m = re.match(r'([\d.]+)\s*(GiB|MiB|KiB|GB|MB|KB|kB|B)', s.strip())
    if not m: return 0.0
    val, unit = float(m.group(1)), m.group(2)
    if unit in ('GiB', 'GB'): return val * 1024
    if unit in ('MiB', 'MB'): return val
    if unit in ('KiB', 'KB', 'kB'): return val / 1024
    return val / (1024*1024)

def parse_stats(stats_text):
    """Parse docker stats output, return (services_list, total_cpu, total_mem_mb)"""
    svcs = []
    t_cpu = 0.0
    t_mem = 0.0
    t_net_in = 0.0
    t_net_out = 0.0
    t_blk_in = 0.0
    t_blk_out = 0.0
    for line in stats_text.strip().split('\n'):
        if not line.strip():
            continue
        parts = line.split(',')
        if len(parts) < 5:
            continue
        name = re.sub(r'^.*microservice-', '', parts[0]).rstrip('-1').rstrip('-')
        cpu = float(parts[1].replace('%', '') or 0)
        mem_str = parts[2].split('/')[0].strip()
        mem_mb = parse_size(mem_str)
        net_parts = parts[3].split('/')
        net_in = parse_size(net_parts[0]) if len(net_parts) >= 2 else 0
        net_out = parse_size(net_parts[1]) if len(net_parts) >= 2 else 0
        block_parts = parts[4].split('/')
        block_in = parse_size(block_parts[0]) if len(block_parts) >= 2 else 0
        block_out = parse_size(block_parts[1]) if len(block_parts) >= 2 else 0
        t_cpu += cpu
        t_mem += mem_mb
        t_net_in += net_in
        t_net_out += net_out
        t_blk_in += block_in
        t_blk_out += block_out
        svcs.append({
            "name": name,
            "cpu_percent": round(cpu, 2),
            "memory_mb": round(mem_mb, 1),
            "net_in_mb": round(net_in, 3),
            "net_out_mb": round(net_out, 3),
            "block_in_mb": round(block_in, 1),
            "block_out_mb": round(block_out, 1)
        })
    svcs.sort(key=lambda x: -x["memory_mb"])
    return svcs, t_cpu, t_mem, t_net_in, t_net_out, t_blk_in, t_blk_out

# Parse idle stats
_, idle_cpu, idle_mem, _, _, _, _ = parse_stats('''$STATS_IDLE''')

# Parse load stats
services, total_cpu, total_mem_mb, total_net_in, total_net_out, total_block_in, total_block_out = parse_stats('''$STATS_AFTER''')

# Energy estimates
duration = float($LOAD_DURATION)
cpu_energy = total_cpu / 100 * 15 * duration
mem_energy = total_mem_mb / 1024 * 0.3725 * duration
io_energy = (total_block_in + total_block_out) * 0.005
total_energy = cpu_energy + mem_energy + io_energy

# Idle energy estimate
idle_cpu_energy = idle_cpu / 100 * 15 * duration
idle_mem_energy = idle_mem / 1024 * 0.3725 * duration
idle_energy = idle_cpu_energy + idle_mem_energy

efficiency_ratio = round(total_energy / idle_energy, 2) if idle_energy > 0 else 0.0

report = {
    "project": "$PROJECT_ROOT",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "os": "$OS",
    "command": "Idle snapshot → Load test → docker stats measurement",
    "load_test": {
        "tool": "$LOAD_TOOL",
        "method": "$METHOD",
        "endpoint": "$ENDPOINT",
        "has_body": True if '''$BODY''' else False,
        "duration_seconds": duration,
        "concurrency": int($CONCURRENCY),
        "requests_per_second": float($LOAD_RPS),
        "avg_latency": "$LOAD_LATENCY",
        "total_requests": int($LOAD_TOTAL_REQS),
        "validation_http_code": $VALIDATE_CODE,
        "services_up": $SERVICES_UP,
        "services_down": $SERVICES_DOWN
    },
    "discovered_endpoints": {
        "ports": $DISCOVERED_PORTS,
        "routes": $DISCOVERED_ROUTES,
        "health_checks": $DISCOVERED_HEALTH
    },
    "project_metrics": {
        "containers_running": len(services),
        "source_files": int($TOTAL_SOURCE_FILES),
        "total_lines": int($TOTAL_LINES),
        "disk_usage_mb": int($DISK_USAGE)
    },
    "runtime_metrics": {
        "total_cpu_percent": round(total_cpu, 2),
        "total_memory_mb": round(total_mem_mb, 1),
        "total_network_in_mb": round(total_net_in, 3),
        "total_network_out_mb": round(total_net_out, 3),
        "total_block_io_in_mb": round(total_block_in, 1),
        "total_block_io_out_mb": round(total_block_out, 1),
        "startup_wall_clock_seconds": duration,
        "max_rss_bytes": int(total_mem_mb * 1048576),
        "wall_clock_seconds": duration,
        "user_time_seconds": 0,
        "system_time_seconds": 0,
        "page_faults": 0,
        "io_blocks_read": 0,
        "io_blocks_written": 0,
        "voluntary_context_switches": 0,
        "involuntary_context_switches": 0
    },
    "per_service_metrics": services,
    "energy_estimate": {
        "cpu_energy_joules": round(cpu_energy, 2),
        "memory_energy_joules": round(mem_energy, 2),
        "io_energy_joules": round(io_energy, 2),
        "total_estimated_joules": round(total_energy, 2),
        "note": f"Energy measured UNDER LOAD ({$CONCURRENCY} concurrent, {duration:.0f}s). TDP model: 15W CPU, 0.3725W/GB RAM, 5mJ/MB I/O."
    },
    "idle_vs_load": {
        "idle_cpu_percent": round(idle_cpu, 2),
        "idle_memory_mb": round(idle_mem, 1),
        "load_cpu_percent": round(total_cpu, 2),
        "load_memory_mb": round(total_mem_mb, 1),
        "delta_cpu_percent": round(total_cpu - idle_cpu, 2),
        "delta_memory_mb": round(total_mem_mb - idle_mem, 1),
        "idle_energy_joules": round(idle_energy, 2),
        "load_energy_joules": round(total_energy, 2),
        "efficiency_ratio": efficiency_ratio
    }
}

with open("$OUTPUT_FILE", "w") as f:
    json.dump(report, f, indent=2)

print(f"✅ Runtime analysis complete: $OUTPUT_FILE")
print(f"   Load: {$LOAD_RPS} req/s, {$LOAD_TOTAL_REQS} total requests")
print(f"   CPU: {total_cpu:.1f}% | Memory: {total_mem_mb:.0f}MB | Energy: {total_energy:.1f}J")
print(f"   Services measured: {len(services)}")
PYEOF

rm -f "$LOAD_OUTPUT"
