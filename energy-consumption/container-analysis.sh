#!/bin/bash
# Container Energy Analysis — measures energy consumption of Docker containers or Kubernetes pods
# Cross-platform: Linux, macOS, Windows (Git Bash / WSL)
set -euo pipefail

MODE="${1:-docker}"  # "docker" or "k8s"
TARGET="${2:-}"      # container name/pattern or k8s namespace
DURATION="${3:-30}"  # measurement duration in seconds
OUTPUT_DIR="${4:-.}/energy-report"
OUTPUT_FILE="$OUTPUT_DIR/container-analysis.json"

mkdir -p "$OUTPUT_DIR"

echo "🐳 Container Energy Analysis"
echo "   Mode: $MODE | Target: ${TARGET:-all} | Duration: ${DURATION}s"

# ─── DOCKER MODE ───
measure_docker() {
  local filter="${TARGET:-}"
  
  echo "📊 Capturing container metrics over ${DURATION}s..."
  
  # Take multiple samples over the duration
  SAMPLES=5
  INTERVAL=$((DURATION / SAMPLES))
  [ "$INTERVAL" -lt 1 ] && INTERVAL=1
  
  STATS_FILE="$OUTPUT_DIR/.docker-stats-samples.json"
  echo "[]" > "$STATS_FILE"
  
  for i in $(seq 1 $SAMPLES); do
    echo "   Sample $i/$SAMPLES..."
    if [ -n "$filter" ]; then
      SAMPLE=$(docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}","net":"{{.NetIO}}","block":"{{.BlockIO}}","pids":"{{.PIDs}}"}' $(docker ps --filter "name=$filter" -q) 2>/dev/null || echo "")
    else
      SAMPLE=$(docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}","net":"{{.NetIO}}","block":"{{.BlockIO}}","pids":"{{.PIDs}}"}' 2>/dev/null || echo "")
    fi
    echo "$SAMPLE" >> "$STATS_FILE"
    [ "$i" -lt "$SAMPLES" ] && sleep "$INTERVAL"
  done

  # Get container details (image, uptime, size)
  CONTAINER_INFO=$(docker ps --format '{"name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","size":"{{.Size}}"}' $([ -n "$filter" ] && echo "--filter name=$filter") 2>/dev/null || echo "")

  # Generate JSON report
  python3 << PYEOF
import json, re, sys
from datetime import datetime, timezone

def parse_size(s):
    m = re.match(r'([\d.]+)\s*(GiB|MiB|KiB|GB|MB|KB|kB|B)', s.strip())
    if not m: return 0.0
    val, unit = float(m.group(1)), m.group(2)
    if unit in ('GiB', 'GB'): return val * 1024
    if unit in ('MiB', 'MB'): return val
    if unit in ('KiB', 'KB', 'kB'): return val / 1024
    return val / (1024*1024)

# Parse all samples
samples_raw = open("$STATS_FILE").read()
containers = {}

for line in samples_raw.strip().split('\n'):
    line = line.strip()
    if not line or line == '[]': continue
    try:
        d = json.loads(line)
    except: continue
    name = d.get("name","")
    if not name: continue
    if name not in containers:
        containers[name] = {"cpu_samples":[], "mem_samples":[], "net_in":0, "net_out":0, "block_in":0, "block_out":0, "pids":0}
    
    cpu = float(d.get("cpu","0").replace("%","") or 0)
    containers[name]["cpu_samples"].append(cpu)
    
    mem_str = d.get("mem","0MiB / 0MiB").split("/")[0]
    containers[name]["mem_samples"].append(parse_size(mem_str))
    
    net_parts = d.get("net","0B / 0B").split("/")
    containers[name]["net_in"] = parse_size(net_parts[0]) if len(net_parts)>=2 else 0
    containers[name]["net_out"] = parse_size(net_parts[1]) if len(net_parts)>=2 else 0
    
    block_parts = d.get("block","0B / 0B").split("/")
    containers[name]["block_in"] = parse_size(block_parts[0]) if len(block_parts)>=2 else 0
    containers[name]["block_out"] = parse_size(block_parts[1]) if len(block_parts)>=2 else 0
    
    containers[name]["pids"] = int(d.get("pids",0) or 0)

# Calculate per-container energy
duration = $DURATION
services = []
total_energy = 0

for name, data in containers.items():
    avg_cpu = sum(data["cpu_samples"]) / len(data["cpu_samples"]) if data["cpu_samples"] else 0
    avg_mem = sum(data["mem_samples"]) / len(data["mem_samples"]) if data["mem_samples"] else 0
    peak_mem = max(data["mem_samples"]) if data["mem_samples"] else 0
    
    cpu_energy = avg_cpu / 100 * 15 * duration  # 15W TDP
    mem_energy = avg_mem / 1024 * 0.3725 * duration  # 0.3725W per GB
    io_energy = (data["block_in"] + data["block_out"]) * 0.005  # 5mJ per MB
    svc_energy = round(cpu_energy + mem_energy + io_energy, 2)
    total_energy += svc_energy
    
    services.append({
        "name": name,
        "avg_cpu_percent": round(avg_cpu, 2),
        "avg_memory_mb": round(avg_mem, 1),
        "peak_memory_mb": round(peak_mem, 1),
        "net_in_mb": round(data["net_in"], 3),
        "net_out_mb": round(data["net_out"], 3),
        "block_in_mb": round(data["block_in"], 1),
        "block_out_mb": round(data["block_out"], 1),
        "pids": data["pids"],
        "energy_joules": svc_energy,
        "energy_breakdown": {
            "cpu_joules": round(cpu_energy, 2),
            "memory_joules": round(mem_energy, 2),
            "io_joules": round(io_energy, 2)
        }
    })

services.sort(key=lambda x: -x["energy_joules"])

report = {
    "mode": "docker",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "measurement_duration_seconds": duration,
    "samples_taken": $SAMPLES,
    "total_containers": len(services),
    "total_energy_joules": round(total_energy, 2),
    "total_memory_mb": round(sum(s["avg_memory_mb"] for s in services), 1),
    "total_cpu_percent": round(sum(s["avg_cpu_percent"] for s in services), 2),
    "energy_per_hour_wh": round(total_energy / duration * 3600 / 3600, 2),
    "containers": services
}

with open("$OUTPUT_FILE", "w") as f:
    json.dump(report, f, indent=2)

print(f"✅ Docker energy analysis complete: $OUTPUT_FILE")
print(f"   Containers: {len(services)} | Total Energy: {total_energy:.1f}J ({report['energy_per_hour_wh']:.2f} Wh/hour)")
print(f"   Top consumers:")
for s in services[:5]:
    print(f"     {s['name']}: {s['energy_joules']}J (CPU:{s['avg_cpu_percent']}%, Mem:{s['avg_memory_mb']:.0f}MB)")
PYEOF

  rm -f "$STATS_FILE"
}

# ─── KUBERNETES MODE ───
measure_k8s() {
  local namespace="${TARGET:-default}"
  
  if ! command -v kubectl &>/dev/null; then
    echo "❌ kubectl not found. Install it: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi

  echo "📊 Measuring Kubernetes pods in namespace: $namespace"
  
  # Check if metrics-server is available
  if ! kubectl top pods -n "$namespace" &>/dev/null; then
    echo "❌ metrics-server not available. Install it:"
    echo "   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    exit 1
  fi

  # Take multiple samples
  SAMPLES=5
  INTERVAL=$((DURATION / SAMPLES))
  [ "$INTERVAL" -lt 1 ] && INTERVAL=1
  
  STATS_FILE="$OUTPUT_DIR/.k8s-stats-samples.txt"
  > "$STATS_FILE"
  
  for i in $(seq 1 $SAMPLES); do
    echo "   Sample $i/$SAMPLES..."
    kubectl top pods -n "$namespace" --no-headers 2>/dev/null >> "$STATS_FILE"
    echo "---" >> "$STATS_FILE"
    [ "$i" -lt "$SAMPLES" ] && sleep "$INTERVAL"
  done

  # Get pod details
  POD_INFO=$(kubectl get pods -n "$namespace" -o json 2>/dev/null || echo "{}")

  python3 << PYEOF
import json, re, sys
from datetime import datetime, timezone

# Parse kubectl top output (format: "pod-name   123m   456Mi")
pods = {}
samples_text = open("$STATS_FILE").read()

for block in samples_text.split("---"):
    for line in block.strip().split('\n'):
        if not line.strip(): continue
        parts = line.split()
        if len(parts) < 3: continue
        name = parts[0]
        cpu_str = parts[1]  # e.g., "123m" (millicores)
        mem_str = parts[2]  # e.g., "456Mi"
        
        if name not in pods:
            pods[name] = {"cpu_samples": [], "mem_samples": []}
        
        # Parse CPU (millicores to percent of 1 core)
        cpu_m = re.match(r'(\d+)m?', cpu_str)
        cpu_millicores = int(cpu_m.group(1)) if cpu_m else 0
        if 'm' in cpu_str:
            cpu_percent = cpu_millicores / 10  # 1000m = 100%
        else:
            cpu_percent = cpu_millicores * 100
        pods[name]["cpu_samples"].append(cpu_percent)
        
        # Parse memory
        mem_m = re.match(r'(\d+)(Mi|Gi|Ki)?', mem_str)
        if mem_m:
            val = int(mem_m.group(1))
            unit = mem_m.group(2) or 'Mi'
            if unit == 'Gi': mem_mb = val * 1024
            elif unit == 'Mi': mem_mb = val
            elif unit == 'Ki': mem_mb = val / 1024
            else: mem_mb = val
        else:
            mem_mb = 0
        pods[name]["mem_samples"].append(mem_mb)

# Get pod metadata
try:
    pod_info = json.loads('''$POD_INFO''')
    pod_images = {}
    pod_requests = {}
    for item in pod_info.get("items", []):
        pname = item["metadata"]["name"]
        containers = item["spec"].get("containers", [])
        if containers:
            pod_images[pname] = containers[0].get("image", "unknown")
            res = containers[0].get("resources", {})
            pod_requests[pname] = {
                "cpu_request": res.get("requests", {}).get("cpu", ""),
                "mem_request": res.get("requests", {}).get("memory", ""),
                "cpu_limit": res.get("limits", {}).get("cpu", ""),
                "mem_limit": res.get("limits", {}).get("memory", "")
            }
except:
    pod_images = {}
    pod_requests = {}

# Calculate energy per pod
duration = $DURATION
services = []
total_energy = 0

for name, data in pods.items():
    avg_cpu = sum(data["cpu_samples"]) / len(data["cpu_samples"]) if data["cpu_samples"] else 0
    avg_mem = sum(data["mem_samples"]) / len(data["mem_samples"]) if data["mem_samples"] else 0
    peak_mem = max(data["mem_samples"]) if data["mem_samples"] else 0
    
    cpu_energy = avg_cpu / 100 * 15 * duration
    mem_energy = avg_mem / 1024 * 0.3725 * duration
    svc_energy = round(cpu_energy + mem_energy, 2)
    total_energy += svc_energy
    
    services.append({
        "name": name,
        "image": pod_images.get(name, "unknown"),
        "avg_cpu_percent": round(avg_cpu, 2),
        "avg_memory_mb": round(avg_mem, 1),
        "peak_memory_mb": round(peak_mem, 1),
        "energy_joules": svc_energy,
        "energy_breakdown": {
            "cpu_joules": round(cpu_energy, 2),
            "memory_joules": round(mem_energy, 2)
        },
        "resource_requests": pod_requests.get(name, {})
    })

services.sort(key=lambda x: -x["energy_joules"])

report = {
    "mode": "kubernetes",
    "namespace": "$namespace",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "measurement_duration_seconds": duration,
    "samples_taken": $SAMPLES,
    "total_pods": len(services),
    "total_energy_joules": round(total_energy, 2),
    "total_memory_mb": round(sum(s["avg_memory_mb"] for s in services), 1),
    "total_cpu_percent": round(sum(s["avg_cpu_percent"] for s in services), 2),
    "energy_per_hour_wh": round(total_energy / duration * 3600 / 3600, 2),
    "pods": services
}

with open("$OUTPUT_FILE", "w") as f:
    json.dump(report, f, indent=2)

print(f"✅ Kubernetes energy analysis complete: $OUTPUT_FILE")
print(f"   Pods: {len(services)} | Namespace: $namespace")
print(f"   Total Energy: {total_energy:.1f}J ({report['energy_per_hour_wh']:.2f} Wh/hour)")
print(f"   Top consumers:")
for s in services[:5]:
    print(f"     {s['name']}: {s['energy_joules']}J (CPU:{s['avg_cpu_percent']}%, Mem:{s['avg_memory_mb']:.0f}MB)")
PYEOF

  rm -f "$STATS_FILE"
}

# ─── RUN ───
case "$MODE" in
  docker|d)  measure_docker ;;
  k8s|kubernetes|k) measure_k8s ;;
  *)
    echo "Usage: $0 <docker|k8s> [target] [duration_seconds] [output_dir]"
    echo ""
    echo "  Docker:     $0 docker [container-name-filter] [duration] [project_dir]"
    echo "  Kubernetes: $0 k8s [namespace] [duration] [project_dir]"
    exit 1
    ;;
esac
