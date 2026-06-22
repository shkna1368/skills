#!/bin/bash
# Generate HTML Energy Report - combines static + runtime analysis into a responsive HTML report
# Cross-platform: Linux, macOS, Windows (Git Bash / WSL)
set -euo pipefail

PROJECT_ROOT="${1:-.}"
OUTPUT_DIR="$PROJECT_ROOT/energy-report"
STATIC_FILE="$OUTPUT_DIR/static-analysis.json"
RUNTIME_FILE="$OUTPUT_DIR/runtime-analysis.json"
HTML_FILE="$OUTPUT_DIR/energy-report.html"

if [ ! -f "$STATIC_FILE" ] && [ ! -f "$RUNTIME_FILE" ]; then
  echo "❌ No analysis data found. Run static-analysis.sh and/or runtime-analysis.sh first."
  exit 1
fi

echo "📊 Generating HTML energy report..."

python3 << 'PYTHON_SCRIPT'
import json, os, sys
from datetime import datetime, timezone

project_root = sys.argv[1] if len(sys.argv) > 1 else "."
output_dir = os.path.join(project_root, "energy-report")
static_file = os.path.join(output_dir, "static-analysis.json")
runtime_file = os.path.join(output_dir, "runtime-analysis.json")
html_file = os.path.join(output_dir, "energy-report.html")

static_data = json.load(open(static_file)) if os.path.exists(static_file) else None
runtime_data = json.load(open(runtime_file)) if os.path.exists(runtime_file) else None
container_file = os.path.join(output_dir, "container-analysis.json")
container_data = json.load(open(container_file)) if os.path.exists(container_file) else None

# Calculate combined grade (static + runtime)
score = static_data["summary"]["score"] if static_data else 100
static_score = score

runtime_score = 100
if runtime_data:
    rm = runtime_data["runtime_metrics"]
    ee = runtime_data["energy_estimate"]
    lt = runtime_data.get("load_test", {})
    containers = runtime_data.get("project_metrics", {}).get("containers_running", 1)

    # Runtime scoring factors:
    # 1. Memory efficiency: penalize if avg memory per service > 300MB
    avg_mem_per_service = rm.get("total_memory_mb", 0) / max(containers, 1)
    if avg_mem_per_service > 500: runtime_score -= 25
    elif avg_mem_per_service > 300: runtime_score -= 15
    elif avg_mem_per_service > 150: runtime_score -= 5

    # 2. CPU efficiency: penalize high idle CPU (>2% per container avg)
    avg_cpu = rm.get("total_cpu_percent", 0) / max(containers, 1)
    if avg_cpu > 5: runtime_score -= 20
    elif avg_cpu > 2: runtime_score -= 10
    elif avg_cpu > 1: runtime_score -= 5

    # 3. Energy per request (if load test data available)
    total_reqs = lt.get("total_requests", 0)
    total_energy = ee.get("total_estimated_joules", 0)
    if total_reqs > 0:
        energy_per_req = total_energy / total_reqs
        if energy_per_req > 1.0: runtime_score -= 20
        elif energy_per_req > 0.1: runtime_score -= 10
        elif energy_per_req > 0.01: runtime_score -= 5

    # 4. I/O efficiency: penalize heavy block I/O
    total_io_mb = rm.get("total_block_io_in_mb", 0) + rm.get("total_block_io_out_mb", 0)
    if total_io_mb > 2000: runtime_score -= 15
    elif total_io_mb > 500: runtime_score -= 8
    elif total_io_mb > 100: runtime_score -= 3

    runtime_score = max(0, min(100, runtime_score))

# Combined: 40% static, 60% runtime (runtime matters more for real energy)
if runtime_data and static_data:
    score = int(static_score * 0.4 + runtime_score * 0.6)
elif runtime_data:
    score = runtime_score
else:
    score = static_score

if score >= 90: grade, grade_color = "A", "#22c55e"
elif score >= 75: grade, grade_color = "B", "#84cc16"
elif score >= 60: grade, grade_color = "C", "#eab308"
elif score >= 40: grade, grade_color = "D", "#f97316"
else: grade, grade_color = "F", "#ef4444"

# CO2 emissions and cost estimate — Cloud Profile Aware
total_energy_joules = 0
energy_per_hour_wh = 0
if runtime_data:
    total_energy_joules = runtime_data["energy_estimate"]["total_estimated_joules"]
elif container_data:
    total_energy_joules = container_data.get("total_energy_joules", 0)
    energy_per_hour_wh = container_data.get("energy_per_hour_wh", 0)

if runtime_data and not energy_per_hour_wh:
    duration = runtime_data.get("load_test", {}).get("duration_seconds", runtime_data["runtime_metrics"].get("wall_clock_seconds", 30))
    energy_per_hour_wh = (total_energy_joules / max(duration, 1)) * 3600 / 3600

# Load cloud profiles
profiles_file = os.path.join(os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.path.expanduser("~/.kiro/skills/energy-consumption"), "cloud-profiles.json")
if not os.path.exists(profiles_file):
    profiles_file = os.path.expanduser("~/.kiro/skills/energy-consumption/cloud-profiles.json")
try:
    cloud_profiles = json.load(open(profiles_file))
except:
    cloud_profiles = {"defaults": {"carbon_g_per_kwh": 400, "price_per_kwh": 0.05}, "cloud_profiles": {}, "country_carbon_intensity": {}}

defaults = cloud_profiles.get("defaults", {})
carbon_intensity = defaults.get("carbon_g_per_kwh", 400)
price_per_kwh = defaults.get("price_per_kwh", 0.05)

energy_kwh = energy_per_hour_wh / 1000
co2_grams = energy_kwh * carbon_intensity
monthly_kwh = energy_kwh * 24 * 30
monthly_cost = monthly_kwh * price_per_kwh
yearly_cost = monthly_cost * 12
co2_monthly_kg = monthly_kwh * carbon_intensity / 1000

# Per-service cost (if per_service_metrics available)
per_service_costs = []
if runtime_data and runtime_data.get("per_service_metrics"):
    for svc in runtime_data["per_service_metrics"]:
        svc_cpu_energy = svc["cpu_percent"] / 100 * 15 * duration
        svc_mem_energy = svc["memory_mb"] / 1024 * 0.3725 * duration
        svc_energy_j = svc_cpu_energy + svc_mem_energy
        svc_wh = svc_energy_j / 3600
        svc_monthly_cost = svc_wh * 24 * 30 * price_per_kwh
        per_service_costs.append({"name": svc["name"], "monthly_cost": round(svc_monthly_cost, 4), "energy_j": round(svc_energy_j, 2)})
    per_service_costs.sort(key=lambda x: -x["monthly_cost"])

# Region comparison — show CO₂ and cost across all cloud regions
region_comparison = []
for provider, pdata in cloud_profiles.get("cloud_profiles", {}).items():
    for region_id, rdata in pdata.get("regions", {}).items():
        r_carbon = rdata["carbon_g_per_kwh"]
        r_price = rdata["price_per_kwh"]
        r_co2_monthly = monthly_kwh * r_carbon / 1000
        r_cost_monthly = monthly_kwh * r_price
        region_comparison.append({
            "provider": provider.upper(),
            "region": region_id,
            "name": rdata["name"],
            "carbon_g_per_kwh": r_carbon,
            "co2_monthly_kg": round(r_co2_monthly, 4),
            "cost_monthly": round(r_cost_monthly, 4)
        })
region_comparison.sort(key=lambda x: x["co2_monthly_kg"])

# Build region comparison HTML
region_html = ""
if region_comparison and energy_per_hour_wh > 0:
    best = region_comparison[0]
    worst = region_comparison[-1]
    region_html = f'''<div class="section"><h2>🌍 Carbon Region Comparison</h2>
    <p class="note">Same workload deployed to different regions — showing CO₂ and cost impact.</p>
    <div class="metrics-grid">
        <div class="metric-card" style="border-color:#22c55e">
            <div class="metric-value" style="color:#22c55e">🏆 {best["name"]}</div>
            <div class="metric-label">{best["provider"]} {best["region"]} — {best["carbon_g_per_kwh"]}g CO₂/kWh — ${best["cost_monthly"]:.4f}/mo</div>
        </div>
        <div class="metric-card" style="border-color:#ef4444">
            <div class="metric-value" style="color:#ef4444">⚠️ {worst["name"]}</div>
            <div class="metric-label">{worst["provider"]} {worst["region"]} — {worst["carbon_g_per_kwh"]}g CO₂/kWh — ${worst["cost_monthly"]:.4f}/mo</div>
        </div>
    </div>
    <table><thead><tr><th>Provider</th><th>Region</th><th>Carbon (g/kWh)</th><th>CO₂/month (kg)</th><th>Cost/month</th></tr></thead><tbody>'''
    for r in region_comparison:
        highlight = ' style="background:var(--energy-bg)"' if r["carbon_g_per_kwh"] <= 100 else ""
        region_html += f'<tr{highlight}><td>{r["provider"]}</td><td>{r["name"]} ({r["region"]})</td><td>{r["carbon_g_per_kwh"]}</td><td>{r["co2_monthly_kg"]:.4f}</td><td>${r["cost_monthly"]:.4f}</td></tr>'
    region_html += '</tbody></table>'
    region_html += f'<p class="note"><strong>Recommendation:</strong> Deploy to <strong>{best["name"]} ({best["provider"]} {best["region"]})</strong> for {round((1 - best["co2_monthly_kg"]/max(worst["co2_monthly_kg"],0.001))*100)}% less CO₂ emissions.</p></div>'

# Historical comparison
history_file = os.path.join(output_dir, "history.json")
history = []
if os.path.exists(history_file):
    try:
        history = json.load(open(history_file))
    except:
        history = []

trend_arrow = ""
if history:
    last_score = history[-1].get("score", score)
    if score > last_score: trend_arrow = "↑"
    elif score < last_score: trend_arrow = "↓"
    else: trend_arrow = "→"

# Build trend HTML (last 10 runs)
trend_html = ""
recent = (history + [{"timestamp": datetime.now(timezone.utc).isoformat(), "score": score}])[-10:]
if len(recent) > 1:
    bars = ""
    for entry in recent:
        s = entry.get("score", 0)
        color = "#22c55e" if s >= 90 else "#84cc16" if s >= 75 else "#eab308" if s >= 60 else "#f97316" if s >= 40 else "#ef4444"
        ts_label = entry.get("timestamp", "")[:10]
        bars += f'<div style="display:flex;flex-direction:column;align-items:center;flex:1;gap:4px"><div style="height:{s}px;width:24px;background:{color};border-radius:4px"></div><div style="font-size:0.7rem;color:var(--fg2)">{s}</div><div style="font-size:0.6rem;color:var(--fg2)">{ts_label}</div></div>'
    trend_html = f'''<div class="section"><h2>📈 Trend Over Time {f'<span style="font-size:1.5rem">{trend_arrow}</span>' if trend_arrow else ''}</h2>
    <div style="display:flex;align-items:flex-end;height:120px;gap:4px;padding:1rem 0">{bars}</div>
    <p class="note">Last {len(recent)} runs shown. {'Score improved! ' + trend_arrow if trend_arrow == "↑" else 'Score worsened ' + trend_arrow if trend_arrow == "↓" else 'Score unchanged →'}</p></div>'''

# Build findings HTML
findings_html = ""
if static_data and static_data.get("findings"):
    for f in static_data["findings"]:
        sev = f["severity"]
        sev_class = {"critical": "sev-critical", "high": "sev-high", "medium": "sev-medium", "low": "sev-low"}.get(sev, "sev-low")
        findings_html += f'''<tr>
            <td><span class="badge {sev_class}">{sev.upper()}</span></td>
            <td>{f["category"]}</td>
            <td class="file-path">{f["file"]}:{f["line"]}</td>
            <td>{f["message"]}</td>
        </tr>\n'''

# Build runtime metrics HTML
runtime_html = ""
if runtime_data:
    rm = runtime_data["runtime_metrics"]
    ee = runtime_data["energy_estimate"]
    pm = runtime_data["project_metrics"]
    lt = runtime_data.get("load_test", {})
    containers = pm.get("containers_running", 1)

    # Main metrics
    runtime_html = f'''
    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value">{rm.get("startup_wall_clock_seconds", rm.get("wall_clock_seconds", 0))}s</div>
            <div class="metric-label">Startup Time</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_cpu_percent", 0):.1f}%</div>
            <div class="metric-label">Total CPU Usage</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_memory_mb", round(rm.get("max_rss_bytes",0)/1048576,1)):.0f}MB</div>
            <div class="metric-label">Total Memory</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{pm.get("containers_running", 0)}</div>
            <div class="metric-label">Containers Running</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_network_in_mb", 0):.1f}MB</div>
            <div class="metric-label">Network In</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_network_out_mb", 0):.1f}MB</div>
            <div class="metric-label">Network Out</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_block_io_in_mb", rm.get("io_blocks_read",0)):.0f}MB</div>
            <div class="metric-label">Block I/O Read</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{rm.get("total_block_io_out_mb", rm.get("io_blocks_written",0)):.0f}MB</div>
            <div class="metric-label">Block I/O Write</div>
        </div>
    </div>
    <h3>Energy Estimate</h3>
    <div class="metrics-grid">
        <div class="metric-card energy">
            <div class="metric-value">{ee["total_estimated_joules"]}J</div>
            <div class="metric-label">Total Estimated Energy</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{ee["cpu_energy_joules"]}J</div>
            <div class="metric-label">CPU Energy</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{ee["memory_energy_joules"]}J</div>
            <div class="metric-label">Memory Energy</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{ee["io_energy_joules"]}J</div>
            <div class="metric-label">I/O Energy</div>
        </div>
    </div>
    <p class="note">{ee["note"]}</p>'''

    # Per-service breakdown (if available)
    per_service = runtime_data.get("per_service_metrics", [])
    if per_service:
        max_mem = max(s["memory_mb"] for s in per_service) if per_service else 1
        duration = lt.get("duration_seconds", rm.get("wall_clock_seconds", 30))
        total_reqs = lt.get("total_requests", 0)

        # Calculate per-service energy
        runtime_html += '<h3>Per-Service Energy &amp; Resources</h3><div class="service-table"><table><thead><tr><th>Service</th><th>CPU %</th><th>Memory</th><th>Energy (J)</th><th>Memory Bar</th></tr></thead><tbody>'
        for s in per_service:
            pct = s["memory_mb"] / max_mem * 100
            # Energy per service: CPU component + memory component
            svc_cpu_energy = s["cpu_percent"] / 100 * 15 * duration
            svc_mem_energy = s["memory_mb"] / 1024 * 0.3725 * duration
            svc_energy = round(svc_cpu_energy + svc_mem_energy, 2)
            runtime_html += f'<tr><td>{s["name"]}</td><td>{s["cpu_percent"]:.2f}%</td><td>{s["memory_mb"]:.0f}MB</td><td>{svc_energy}J</td><td><div class="bar-track" style="width:100%"><div class="bar-fill" style="width:{pct:.0f}%"></div></div></td></tr>'
        runtime_html += '</tbody></table></div>'

        # Energy per request
        if total_reqs > 0:
            energy_per_req = ee["total_estimated_joules"] / total_reqs
            runtime_html += f'''<h3>Energy Per Request</h3>
            <div class="metrics-grid">
                <div class="metric-card energy">
                    <div class="metric-value">{energy_per_req*1000:.2f} mJ</div>
                    <div class="metric-label">Energy per Request</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{total_reqs:,}</div>
                    <div class="metric-label">Total Requests</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{ee["total_estimated_joules"]:.1f} J</div>
                    <div class="metric-label">Total Energy (during test)</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{rm.get("total_memory_mb",0)/max(containers,1):.0f} MB</div>
                    <div class="metric-label">Avg Memory / Service</div>
                </div>
            </div>'''

    runtime_html += f'''
    <h3>Project Metrics</h3>
    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value">{pm.get("source_files", 0)}</div>
            <div class="metric-label">Source Files</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{pm.get("total_lines", 0):,}</div>
            <div class="metric-label">Total Lines</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{pm.get("disk_usage_mb", 0)}MB</div>
            <div class="metric-label">Disk Usage</div>
        </div>
    </div>'''

# Load test section
load_test_html = ""
if runtime_data and "load_test" in runtime_data:
    lt = runtime_data["load_test"]
    load_test_html = f'''<div class="section"><h2>🔥 RUNTIME — Load Test Results</h2>
    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value">{lt.get("tool","N/A")}</div>
            <div class="metric-label">Tool</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{lt.get("requests_per_second",0):.1f}</div>
            <div class="metric-label">Requests/sec</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{lt.get("total_requests",0):,}</div>
            <div class="metric-label">Total Requests</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{lt.get("avg_latency","0")}</div>
            <div class="metric-label">Avg Latency</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{lt.get("duration_seconds",0):.0f}s</div>
            <div class="metric-label">Duration</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{lt.get("concurrency",0)}</div>
            <div class="metric-label">Concurrency</div>
        </div>
    </div>
    <p class="note">Endpoint: {lt.get("endpoint","")}</p>
    </div>'''

# Container analysis section (Docker / K8s)
container_html = ""
if container_data:
    mode_label = "Kubernetes Pods" if container_data.get("mode") == "kubernetes" else "Docker Containers"
    items = container_data.get("pods", container_data.get("containers", []))
    container_html = f'''<div class="section"><h2>🐳 CONTAINER ANALYSIS — {mode_label}</h2>
    <div class="metrics-grid">
        <div class="metric-card energy">
            <div class="metric-value">{container_data.get("total_energy_joules",0)}J</div>
            <div class="metric-label">Total Energy ({container_data.get("measurement_duration_seconds",0)}s)</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{container_data.get("energy_per_hour_wh",0)} Wh</div>
            <div class="metric-label">Energy per Hour</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{container_data.get("total_containers", container_data.get("total_pods",0))}</div>
            <div class="metric-label">Total {mode_label.split()[0]}s</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{container_data.get("total_memory_mb",0):.0f}MB</div>
            <div class="metric-label">Total Memory</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{container_data.get("total_cpu_percent",0):.1f}%</div>
            <div class="metric-label">Total CPU</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{container_data.get("samples_taken",0)}</div>
            <div class="metric-label">Samples Taken</div>
        </div>
    </div>
    <h3>Per-Container Energy Breakdown</h3>
    <table><thead><tr><th>Name</th><th>CPU %</th><th>Memory</th><th>Energy (J)</th><th>CPU (J)</th><th>Mem (J)</th></tr></thead><tbody>'''
    for item in items:
        eb = item.get("energy_breakdown", {})
        container_html += f'<tr><td>{item["name"]}</td><td>{item["avg_cpu_percent"]:.2f}%</td><td>{item["avg_memory_mb"]:.0f}MB</td><td><strong>{item["energy_joules"]}</strong></td><td>{eb.get("cpu_joules",0)}</td><td>{eb.get("memory_joules",0)}</td></tr>'
    container_html += '</tbody></table></div>'

# Category summary
category_counts = {}
if static_data:
    for f in static_data.get("findings", []):
        cat = f["category"]
        category_counts[cat] = category_counts.get(cat, 0) + 1

category_chart_html = ""
if category_counts:
    max_count = max(category_counts.values())
    for cat, count in sorted(category_counts.items(), key=lambda x: -x[1]):
        pct = count / max_count * 100
        category_chart_html += f'''<div class="bar-row">
            <span class="bar-label">{cat}</span>
            <div class="bar-track"><div class="bar-fill" style="width:{pct}%"></div></div>
            <span class="bar-value">{count}</span>
        </div>\n'''

timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
project_name = os.path.basename(os.path.abspath(project_root))

# Fun section — what could this energy do in real life?
fun_html = ""
if energy_per_hour_wh > 0:
    monthly_wh = energy_per_hour_wh * 24 * 30
    monthly_j = monthly_wh * 3600
    # Fun equivalents
    fun_items = []
    # Phone charges: ~10 Wh per full charge
    phones = monthly_wh / 10
    fun_items.append(f"📱 Charge <strong>{phones:.0f} smartphones</strong>")
    # Cups of tea: ~100 Wh to boil a cup
    teas = monthly_wh / 100
    fun_items.append(f"☕ Boil <strong>{teas:.0f} cups of tea</strong>")
    # Netflix hours: ~50 Wh per hour of streaming
    netflix = monthly_wh / 50
    fun_items.append(f"🎬 Stream <strong>{netflix:.0f} hours of Netflix</strong>")
    # km in electric car: ~150 Wh per km
    km = monthly_wh / 150
    fun_items.append(f"🚗 Drive an EV <strong>{km:.1f} km</strong>")
    # Hamsters: 1 hamster ≈ 0.5W
    hamsters = energy_per_hour_wh / 0.5
    fun_items.append(f"🐹 Requires <strong>{hamsters:.0f} hamsters</strong> running on wheels 24/7")
    # Human marathons: running burns ~100W, marathon = ~3.5h = 350 Wh
    marathons = monthly_wh / 350
    fun_items.append(f"🏃 Equivalent to running <strong>{marathons:.0f} marathons</strong>")
    # SpaceX rocket: Merlin engine = 845,000 kW
    rocket_ms = monthly_wh / 1000 / 845000 * 3600 * 1000
    fun_items.append(f"🚀 <strong>{rocket_ms:.2f} milliseconds</strong> of SpaceX Falcon 9 thrust")
    # Pizza ovens: ~2000W
    pizzas = energy_per_hour_wh / 2000
    fun_items.append(f"🍕 Run <strong>{pizzas:.2f} pizza ovens</strong> simultaneously")
    # PlayStation gaming: ~200 Wh per hour
    gaming = monthly_wh / 200
    fun_items.append(f"🎮 <strong>{gaming:.0f} hours</strong> of PlayStation gaming")
    # Microwave burritos: ~2 min at 1000W = 33 Wh each
    burritos = monthly_wh / 33
    fun_items.append(f"🌮 Microwave <strong>{burritos:.0f} burritos</strong>")
    # LED bulb hours: 10W LED
    led_hours = monthly_wh / 10
    fun_items.append(f"💡 Power an LED bulb for <strong>{led_hours/24:.0f} days</strong>")
    # Trees needed to offset: 1 tree absorbs ~22kg CO₂/year
    trees = co2_monthly_kg * 12 / 22
    fun_items.append(f"🌳 Need <strong>{trees:.1f} trees</strong> to offset yearly CO₂")

    fun_html = '<div class="section"><h2>🎉 Fun Facts — What This Energy Could Power</h2>'
    fun_html += f'<p class="note">Your monthly energy: <strong>{monthly_wh:.1f} Wh</strong> ({monthly_wh/1000:.3f} kWh) — continuous power draw: <strong>{energy_per_hour_wh:.1f} W</strong></p>'
    fun_html += '<div class="metrics-grid">'
    for item in fun_items:
        fun_html += f'<div class="metric-card"><div class="metric-label" style="font-size:0.95rem">{item}</div></div>'
    fun_html += '</div></div>'

# Shame section — roast the worst offenders
shame_html = ""
if runtime_data and runtime_data.get("per_service_metrics"):
    services_sorted = sorted(runtime_data["per_service_metrics"], key=lambda x: -x["memory_mb"])
    roasts = []
    for svc in services_sorted[:5]:
        name = svc["name"]
        mem = svc["memory_mb"]
        cpu = svc["cpu_percent"]
        if "oracle" in name.lower() and mem > 1000:
            roasts.append(f"🏛️ <strong>{name}</strong> is using {mem:.0f}MB RAM — that's more than the entire Apollo 11 guidance computer had for going to the Moon")
        elif "kafka" in name.lower() and cpu > 5:
            roasts.append(f"☕ <strong>{name}</strong> ({cpu:.1f}% CPU) is consuming more energy than the actual kafka in your coffee machine")
        elif ("spring" in name.lower() or "user-service" in name.lower() or "product" in name.lower()) and mem > 200:
            roasts.append(f"🦕 <strong>{name}</strong> needs {mem:.0f}MB RAM — a 2005 gaming PC had 512MB total and ran Doom 3")
        elif "mysql" in name.lower() and mem > 400:
            roasts.append(f"🐘 <strong>{name}</strong> is hoarding {mem:.0f}MB — it's storing more in RAM than most people have photos")
        elif mem > 100:
            roasts.append(f"🤔 <strong>{name}</strong> uses {mem:.0f}MB just to exist — my first computer had 4MB and ran an OS")

    if roasts:
        shame_html = '<div class="section"><h2>🔥 Wall of Shame — Roasting Your Services</h2>'
        shame_html += '<ul style="padding-left:1.5rem; font-size:0.95rem; line-height:2;">'
        for roast in roasts:
            shame_html += f'<li>{roast}</li>'
        shame_html += '</ul></div>'

# Achievement badges
badges_html = ""
badge_list = []
if score >= 90:
    badge_list.append(("🏆", "Green Machine", "Score 90+ — pristine energy efficiency"))
elif score >= 75:
    badge_list.append(("🌱", "Eco Warrior", "Score 75+ — good efficiency with room to grow"))
if co2_monthly_kg < 1:
    badge_list.append(("🍃", "Carbon Featherweight", "Less than 1kg CO₂/month"))
if runtime_data:
    rm = runtime_data["runtime_metrics"]
    lt = runtime_data.get("load_test", {})
    if rm.get("total_cpu_percent", 0) > 80:
        badge_list.append(("🔥", "Burnout Risk", f"CPU at {rm['total_cpu_percent']:.0f}% — your servers are sweating"))
    if runtime_data.get("per_service_metrics"):
        avg_mem_svc = rm.get("total_memory_mb", 0) / max(len(runtime_data["per_service_metrics"]), 1)
        if avg_mem_svc > 500:
            badge_list.append(("🐌", "Memory Hoarder", f"{avg_mem_svc:.0f}MB avg/service — Chrome would be jealous"))
        elif avg_mem_svc < 50:
            badge_list.append(("🪶", "Featherweight", f"Only {avg_mem_svc:.0f}MB avg/service — lean and mean"))
    if lt.get("requests_per_second", 0) > 1000:
        badge_list.append(("⚡", "Speed Demon", f"{lt['requests_per_second']:.0f} req/s — blazing fast"))
    elif lt.get("requests_per_second", 0) > 100:
        badge_list.append(("🚀", "Solid Performer", f"{lt['requests_per_second']:.0f} req/s — respectable throughput"))
if monthly_cost > 10:
    badge_list.append(("💸", "Budget Buster", f"${monthly_cost:.2f}/mo — your wallet is crying"))
elif monthly_cost < 1:
    badge_list.append(("🪙", "Penny Pincher", f"Only ${monthly_cost:.4f}/mo — incredibly cheap"))
if container_data and container_data.get("total_containers", 0) > 15:
    badge_list.append(("🐳", "Container Collector", f"{container_data['total_containers']} containers — you really like Docker"))

if badge_list:
    badges_html = '<div class="section"><h2>🏅 Achievement Badges</h2><div class="metrics-grid">'
    for emoji, title, desc in badge_list:
        badges_html += f'<div class="metric-card" style="text-align:center"><div class="metric-value" style="font-size:2rem">{emoji}</div><div class="metric-label"><strong>{title}</strong><br><span style="font-size:0.75rem">{desc}</span></div></div>'
    badges_html += '</div></div>'

# Build recommendations from runtime data
runtime_advice = ""
if runtime_data:
    lt = runtime_data.get("load_test", {})
    total_reqs = lt.get("total_requests", 0)
    total_e = runtime_data["energy_estimate"]["total_estimated_joules"]
    total_mem = runtime_data["runtime_metrics"].get("total_memory_mb", 0)
    num_containers = runtime_data.get("project_metrics", {}).get("containers_running", 1) or 1
    avg_mem = total_mem / num_containers

    runtime_advice = "<h3>From Runtime Analysis</h3><ul style='padding-left:1.5rem; color:var(--fg2);'>"
    if total_reqs > 0:
        epr = total_e / total_reqs * 1000
        runtime_advice += f"<li><strong>Energy per request: {epr:.1f} mJ</strong> — consider caching frequent responses, reducing middleware chain, using HTTP/2</li>"
    if avg_mem > 150:
        runtime_advice += f"<li><strong>High memory: {avg_mem:.0f} MB avg/service</strong> — use lighter base images (Alpine), reduce heap sizes, enable GC tuning</li>"
    runtime_advice += "<li><strong>General:</strong> Enable connection keep-alive, use async I/O, set resource limits on containers</li></ul>"

# Build recommendations from container data
container_advice = ""
if container_data:
    items = container_data.get("containers", container_data.get("pods", []))
    container_advice = "<h3>From Container Analysis</h3><ul style='padding-left:1.5rem; color:var(--fg2);'>"
    container_advice += f"<li><strong>Total energy: {container_data.get('total_energy_joules',0)}J ({container_data.get('energy_per_hour_wh',0)} Wh/hour)</strong> — identify top consumers and optimize or right-size them</li>"
    if any(s.get("energy_joules",0) > 10 for s in items if any(x in s.get("name","").lower() for x in ["db","oracle","mysql","postgres"])):
        container_advice += "<li><strong>Heavy databases:</strong> Use connection pooling, query caching, read replicas to reduce DB CPU cycles</li>"
    if any(s.get("energy_joules",0) > 10 for s in items if "kafka" in s.get("name","").lower()):
        container_advice += "<li><strong>Kafka overhead:</strong> Tune partition count, reduce replication factor in dev, increase batch.size and linger.ms</li>"
    container_advice += "<li><strong>Right-size containers:</strong> Set CPU/memory limits, use multi-stage builds for smaller images</li>"
    container_advice += "<li><strong>Scale to zero:</strong> Use serverless or scale-to-zero for rarely used services</li></ul>"

# Runtime-specific tips based on detected project files
runtime_tips = []
if os.path.exists(os.path.join(project_root, "pom.xml")) or os.path.exists(os.path.join(project_root, "build.gradle")):
    runtime_tips.append("Consider GraalVM native image for 10x less memory, enable Spring AOT, tune JVM: -XX:+UseG1GC -Xmx256m")
if os.path.exists(os.path.join(project_root, "Cargo.toml")):
    runtime_tips.append("Rust services are already memory-efficient. Consider opt-level=3 and LTO for further CPU reduction")
if os.path.exists(os.path.join(project_root, "package.json")):
    runtime_tips.append("Use Node.js cluster mode, enable --max-old-space-size limit, consider Bun for 2-3x less memory")
if os.path.exists(os.path.join(project_root, "requirements.txt")):
    runtime_tips.append("Use uvicorn with --workers, enable connection pooling, consider PyPy for CPU-bound tasks")
if os.path.exists(os.path.join(project_root, "go.mod")):
    runtime_tips.append("Go is already efficient. Set GOMAXPROCS to match container CPU limit, use sync.Pool for allocations")
runtime_tips_html = ""
if runtime_tips:
    runtime_tips_html = "<h3>Runtime-Specific Tips</h3><ul style='padding-left:1.5rem; color:var(--fg2);'>" + "".join(f"<li>{t}</li>" for t in runtime_tips) + "</ul>"

html = f'''<!DOCTYPE html>
<html lang="en" data-theme="auto">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Energy Report — {project_name}</title>
<style>
:root {{
    --bg: #ffffff; --bg2: #f8fafc; --fg: #1e293b; --fg2: #475569;
    --border: #e2e8f0; --card: #ffffff; --card-shadow: 0 1px 3px rgba(0,0,0,0.1);
    --accent: #3b82f6; --accent2: #6366f1;
    --sev-critical: #dc2626; --sev-high: #ea580c; --sev-medium: #ca8a04; --sev-low: #65a30d;
    --bar-bg: #e2e8f0; --energy-bg: #eff6ff;
}}
[data-theme="dark"] {{
    --bg: #0f172a; --bg2: #1e293b; --fg: #f1f5f9; --fg2: #94a3b8;
    --border: #334155; --card: #1e293b; --card-shadow: 0 1px 3px rgba(0,0,0,0.4);
    --accent: #60a5fa; --accent2: #818cf8;
    --sev-critical: #f87171; --sev-high: #fb923c; --sev-medium: #fbbf24; --sev-low: #a3e635;
    --bar-bg: #334155; --energy-bg: #1e3a5f;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--fg); line-height: 1.6; }}
.container {{ max-width: 1200px; margin: 0 auto; padding: 2rem 1rem; }}
header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; flex-wrap: wrap; gap: 1rem; }}
h1 {{ font-size: 1.5rem; font-weight: 700; }}
h2 {{ font-size: 1.25rem; margin: 2rem 0 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--border); }}
h3 {{ font-size: 1rem; margin: 1.5rem 0 0.75rem; color: var(--fg2); }}
.theme-toggle {{ background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 0.5rem 1rem; cursor: pointer; color: var(--fg); font-size: 0.875rem; }}
.theme-toggle:hover {{ border-color: var(--accent); }}
.summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
.summary-card {{ background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 1.5rem; text-align: center; box-shadow: var(--card-shadow); }}
.grade-card {{ background: linear-gradient(135deg, var(--accent), var(--accent2)); color: white; }}
.grade {{ font-size: 3rem; font-weight: 800; }}
.score {{ font-size: 1.25rem; opacity: 0.9; }}
.stat-value {{ font-size: 2rem; font-weight: 700; color: var(--accent); }}
.stat-label {{ font-size: 0.875rem; color: var(--fg2); margin-top: 0.25rem; }}
.metrics-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; margin: 1rem 0; }}
.metric-card {{ background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; text-align: center; }}
.metric-card.energy {{ background: var(--energy-bg); border-color: var(--accent); }}
.metric-value {{ font-size: 1.25rem; font-weight: 700; color: var(--fg); }}
.metric-label {{ font-size: 0.75rem; color: var(--fg2); margin-top: 0.25rem; }}
table {{ width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.875rem; }}
th, td {{ padding: 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }}
th {{ background: var(--bg2); font-weight: 600; position: sticky; top: 0; }}
tr:hover {{ background: var(--bg2); }}
.badge {{ padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.7rem; font-weight: 700; color: white; }}
.sev-critical {{ background: var(--sev-critical); }}
.sev-high {{ background: var(--sev-high); }}
.sev-medium {{ background: var(--sev-medium); }}
.sev-low {{ background: var(--sev-low); }}
.file-path {{ font-family: monospace; font-size: 0.8rem; color: var(--fg2); word-break: break-all; }}
.bar-row {{ display: flex; align-items: center; gap: 0.75rem; margin: 0.4rem 0; }}
.bar-label {{ width: 140px; font-size: 0.8rem; text-align: right; color: var(--fg2); }}
.bar-track {{ flex: 1; height: 20px; background: var(--bar-bg); border-radius: 4px; overflow: hidden; }}
.bar-fill {{ height: 100%; background: linear-gradient(90deg, var(--accent), var(--accent2)); border-radius: 4px; transition: width 0.5s; }}
.bar-value {{ width: 30px; font-size: 0.8rem; font-weight: 600; }}
.note {{ font-size: 0.8rem; color: var(--fg2); font-style: italic; margin: 0.5rem 0; }}
.section {{ background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 1.5rem; margin: 1.5rem 0; box-shadow: var(--card-shadow); }}
.timestamp {{ font-size: 0.75rem; color: var(--fg2); }}
.empty {{ text-align: center; padding: 2rem; color: var(--fg2); }}
@media (max-width: 768px) {{
    .container {{ padding: 1rem 0.5rem; }}
    .summary {{ grid-template-columns: 1fr 1fr; }}
    .metrics-grid {{ grid-template-columns: 1fr 1fr; }}
    table {{ font-size: 0.75rem; }}
    th, td {{ padding: 0.5rem; }}
    .bar-label {{ width: 100px; }}
}}
@media (max-width: 480px) {{
    .summary {{ grid-template-columns: 1fr; }}
    .metrics-grid {{ grid-template-columns: 1fr; }}
    header {{ flex-direction: column; align-items: flex-start; }}
}}
</style>
</head>
<body>
<div class="container">
<header>
    <div>
        <h1>⚡ Energy Consumption Report</h1>
        <p class="timestamp">{project_name} — Generated {timestamp}</p>
    </div>
    <button class="theme-toggle" onclick="toggleTheme()">🌓 Toggle Theme</button>
</header>

<div class="summary">
    <div class="summary-card grade-card">
        <div class="grade">{grade}</div>
        <div class="score">{score}/100 {trend_arrow}</div>
        <div class="stat-label" style="color:rgba(255,255,255,0.8)">Combined Score</div>
    </div>
    <div class="summary-card">
        <div class="stat-value">🌱 {co2_monthly_kg:.4f}kg</div>
        <div class="stat-label">CO₂/month ({carbon_intensity}g/kWh)</div>
    </div>
    <div class="summary-card">
        <div class="stat-value">💰 ${monthly_cost:.4f}</div>
        <div class="stat-label">Monthly (${yearly_cost:.2f}/yr)</div>
    </div>
    <div class="summary-card">
        <div class="stat-value">{static_score}</div>
        <div class="stat-label">Static Score (40%)</div>
    </div>
    <div class="summary-card">
        <div class="stat-value">{runtime_score}</div>
        <div class="stat-label">Runtime Score (60%)</div>
    </div>
    <div class="summary-card">
        <div class="stat-value" style="color:var(--sev-critical)">{static_data["summary"]["critical"] if static_data else 0}</div>
        <div class="stat-label">Critical</div>
    </div>
    <div class="summary-card">
        <div class="stat-value" style="color:var(--sev-high)">{static_data["summary"]["high"] if static_data else 0}</div>
        <div class="stat-label">High</div>
    </div>
</div>

{load_test_html}

{region_html}

{"<div class='section'><h2>🏃 RUNTIME ANALYSIS — Measured Under Load</h2>" + runtime_html + "</div>" if runtime_html else ""}

{container_html}

<div class="section">
<h2>🔍 STATIC ANALYSIS — Code Pattern Scan</h2>
{"<h3>Category Breakdown</h3>" + category_chart_html if category_chart_html else ""}
{"<h3>Findings</h3><div class='table-wrap'><table><thead><tr><th>Severity</th><th>Category</th><th>Location</th><th>Message</th></tr></thead><tbody>" + findings_html + "</tbody></table></div>" if findings_html else "<p class='empty'>No findings — excellent energy efficiency! 🎉</p>"}
</div>

{fun_html}

{shame_html}

{badges_html}

<div class="section">
<h2>💡 Recommendations to Reduce Energy Consumption</h2>

<h3>From Static Analysis</h3>
<ul style="padding-left:1.5rem; color:var(--fg2);">
{"<li><strong>Busy loops:</strong> Replace polling with event-driven patterns, message queues, or webhooks</li>" if category_counts.get("busy-loop") else ""}
{"<li><strong>I/O in loops:</strong> Batch database/file operations, use bulk APIs</li>" if category_counts.get("io-in-loop") else ""}
{"<li><strong>N+1 queries:</strong> Use JOINs, eager loading, or batch fetching</li>" if category_counts.get("n-plus-1") else ""}
{"<li><strong>Connection pooling:</strong> Configure connection pools for all external resources</li>" if category_counts.get("no-pooling") else ""}
{"<li><strong>Thread management:</strong> Use thread pools with bounded sizes</li>" if category_counts.get("thread-waste") else ""}
{"<li><strong>Memory:</strong> Stream large data instead of loading entirely into memory</li>" if category_counts.get("memory-waste") else ""}
{"<li><strong>Compression:</strong> Enable gzip/brotli for HTTP responses to reduce network energy</li>" if category_counts.get("no-compression") else ""}
{"<li><strong>Serialization:</strong> Avoid redundant JSON parse/stringify — pass objects directly between layers</li>" if category_counts.get("redundant-serde") else ""}
</ul>

{runtime_advice}

{container_advice}

{runtime_tips_html}
<h3>General Best Practices</h3>
<ul style="padding-left:1.5rem; color:var(--fg2);">
<li><strong>Choose efficient runtimes:</strong> Go, Rust → 5-20MB RAM vs Java/C# → 200-400MB RAM per service</li>
<li><strong>Use Alpine/distroless images:</strong> Smaller images = less disk I/O, faster startup, less memory</li>
<li><strong>Enable HTTP compression:</strong> gzip/brotli reduces network bytes by 60-90%</li>
<li><strong>Implement caching:</strong> Redis/in-memory caches prevent repeated computation and DB queries</li>
<li><strong>Async over sync:</strong> Use non-blocking I/O and message queues instead of synchronous chains</li>
<li><strong>Auto-scaling:</strong> Scale down when demand drops — idle containers waste energy continuously</li>
<li><strong>Measure continuously:</strong> Run this analysis in CI/CD to catch energy regressions early</li>
</ul>
</div>
</div>

{trend_html}
</div>

<script>
function getPreferred() {{ return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; }}
function setTheme(t) {{ document.documentElement.setAttribute('data-theme', t); localStorage.setItem('energy-theme', t); }}
function toggleTheme() {{
    const current = document.documentElement.getAttribute('data-theme');
    const effective = current === 'auto' ? getPreferred() : current;
    setTheme(effective === 'dark' ? 'light' : 'dark');
}}
(function() {{
    const saved = localStorage.getItem('energy-theme');
    if (saved) setTheme(saved);
    else setTheme(getPreferred());
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {{
        if (!localStorage.getItem('energy-theme') || localStorage.getItem('energy-theme') === 'auto')
            setTheme(e.matches ? 'dark' : 'light');
    }});
}})();
</script>
</body>
</html>'''

with open(html_file, 'w') as f:
    f.write(html)

# Save history entry
history.append({
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "score": score,
    "energy_joules": total_energy_joules,
    "co2_grams": round(co2_grams, 4),
    "cost_monthly": round(monthly_cost, 6)
})
with open(history_file, 'w') as f:
    json.dump(history, f, indent=2)

print(f"✅ HTML report generated: {html_file}")
PYTHON_SCRIPT

echo "   Open with: open $HTML_FILE"
