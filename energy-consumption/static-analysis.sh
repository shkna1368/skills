#!/bin/bash
# Static Energy Analysis - scans source code for energy-wasting patterns
# Cross-platform: Linux, macOS, Windows (Git Bash / WSL)
set -euo pipefail

PROJECT_ROOT="${1:-.}"
OUTPUT_DIR="$PROJECT_ROOT/energy-report"
OUTPUT_FILE="$OUTPUT_DIR/static-analysis.json"

mkdir -p "$OUTPUT_DIR"

# Initialize findings array
FINDINGS="[]"
find_id=0

add_finding() {
  local severity="$1" category="$2" file="$3" line="$4" pattern="$5" message="$6"
  find_id=$((find_id + 1))
  FINDINGS=$(echo "$FINDINGS" | python3 -c "
import json, sys
findings = json.load(sys.stdin)
findings.append({
    'id': $find_id,
    'severity': '$severity',
    'category': '$category',
    'file': '$file',
    'line': $line,
    'pattern': '$pattern',
    'message': '$message'
})
print(json.dumps(findings))
")
}

echo "🔍 Running static energy analysis on: $PROJECT_ROOT"

# Collect source files (exclude common non-source dirs)
SRC_FILES=$(find "$PROJECT_ROOT" -type f \( \
  -name "*.go" -o -name "*.java" -o -name "*.py" -o -name "*.rs" -o \
  -name "*.ts" -o -name "*.js" -o -name "*.cs" -o -name "*.kt" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/target/*" \
  ! -path "*/vendor/*" ! -path "*/dist/*" ! -path "*/build/*" \
  ! -path "*/energy-report/*" 2>/dev/null || true)

total_files=$(echo "$SRC_FILES" | grep -c '.' || echo 0)
echo "📂 Scanning $total_files source files..."

# Pattern checks
while IFS= read -r file; do
  [ -z "$file" ] && continue
  rel_file="${file#$PROJECT_ROOT/}"

  # 1. Busy loops / polling
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "high" "busy-loop" "$rel_file" "$ln" "while-true" "Busy loop detected — consider event-driven or sleep-based approach"
  done < <(grep -n -E '(while\s*\(\s*true\s*\)|while\s+True|loop\s*\{|for\s*\(\s*;\s*;\s*\))' "$file" 2>/dev/null || true)

  # 2. Sleep in tight loops (low sleep = spin wait)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "medium" "spin-wait" "$rel_file" "$ln" "short-sleep" "Very short sleep in loop — may cause CPU spin"
  done < <(grep -n -E '(sleep\(([0-9]|[1-9][0-9])\)|Sleep\(([0-9]|[1-9][0-9])\)|thread::sleep.*Duration::(from_millis\(([0-9]|[1-9][0-9])\)|from_nanos))' "$file" 2>/dev/null || true)

  # 3. File/DB operations inside loops
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "high" "io-in-loop" "$rel_file" "$ln" "io-inside-loop" "I/O operation likely inside loop — consider batching"
  done < <(grep -n -E '(open\(|fopen|CreateFile|new File|readFile|writeFile|executeQuery|execute\(|\.save\(|\.insert\()' "$file" 2>/dev/null | head -20 || true)

  # 4. N+1 query patterns
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "high" "n-plus-1" "$rel_file" "$ln" "query-in-loop" "Potential N+1 query — use batch/bulk operations"
  done < <(grep -n -E '(for.*\{|for .* in|forEach|\.map\()' "$file" 2>/dev/null | while read -r loop_line; do
    loop_ln=$(echo "$loop_line" | cut -d: -f1)
    # Check next 10 lines for DB calls
    sed -n "$((loop_ln+1)),$((loop_ln+10))p" "$file" 2>/dev/null | grep -q -E '(findBy|query|SELECT|fetch|\.get\(|repository\.)' && echo "$loop_ln:"
  done || true)

  # 5. Missing connection pooling
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "medium" "no-pooling" "$rel_file" "$ln" "new-connection" "New connection created — ensure connection pooling is configured"
  done < <(grep -n -E '(DriverManager\.getConnection|new.*Connection\(|createConnection|sql\.Open\(|connect\()' "$file" 2>/dev/null || true)

  # 6. Unbuffered I/O
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "low" "unbuffered-io" "$rel_file" "$ln" "unbuffered" "Consider buffered I/O for better energy efficiency"
  done < <(grep -n -E '(FileReader\(|FileWriter\(|os\.Open\(|fs\.readFileSync|open\(.*(\"r\"|\"w\"))' "$file" 2>/dev/null | head -5 || true)

  # 7. Thread creation without pooling
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "medium" "thread-waste" "$rel_file" "$ln" "thread-per-request" "Thread/goroutine created per request — consider pooling"
  done < <(grep -n -E '(new Thread\(|threading\.Thread|go func\(|spawn\(|Task\.Run\()' "$file" 2>/dev/null | head -10 || true)

  # 8. Large allocations
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "medium" "memory-waste" "$rel_file" "$ln" "large-alloc" "Large buffer/allocation — consider streaming"
  done < <(grep -n -E '(make\(\[\].*[0-9]{6}|new byte\[.*[0-9]{6}|malloc\(.*[0-9]{6}|Buffer\.alloc\(.*[0-9]{5})' "$file" 2>/dev/null || true)

  # 9. Missing compression
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "low" "no-compression" "$rel_file" "$ln" "uncompressed" "HTTP response without compression — consider gzip/brotli"
  done < <(grep -n -E '(Content-Type.*application/json|ResponseWriter|JsonResponse|json\()' "$file" 2>/dev/null | head -3 || true)

  # 10. Redundant serialization
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "low" "redundant-serde" "$rel_file" "$ln" "double-serde" "Multiple serialize/deserialize — consider passing objects directly"
  done < <(grep -n -E '(JSON\.parse\(JSON\.stringify|json\.loads\(json\.dumps|ObjectMapper.*write.*read|serde_json::from.*serde_json::to)' "$file" 2>/dev/null || true)

  # 11. Chatty HTTP calls (multiple sequential HTTP calls that could be batched)
  chatty_count=$(grep -c -E '(http\.Get|http\.Post|fetch\(|requests\.(get|post)|HttpClient\.(Get|Post|Send)|\.GetAsync|\.PostAsync)' "$file" 2>/dev/null || true)
  chatty_count=${chatty_count:-0}
  chatty_count=$(echo "$chatty_count" | tr -d '[:space:]')
  if [ "$chatty_count" -gt 3 ] 2>/dev/null; then
    ln=$(grep -n -E '(http\.Get|http\.Post|fetch\(|requests\.(get|post)|HttpClient\.(Get|Post|Send)|\.GetAsync|\.PostAsync)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$ln" ] && add_finding "medium" "network-waste" "$rel_file" "$ln" "chatty-http" "Multiple sequential HTTP calls — consider batching or using GraphQL/BFF pattern"
  fi

  # 12. Missing connection reuse
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && add_finding "medium" "network-waste" "$rel_file" "$ln" "no-conn-reuse" "HTTP client created per request — reuse connections with keep-alive"
  done < <(grep -n -E '(new HttpClient\(|&http\.Client\{|http\.Client\{|requests\.Session\(\)|HttpClient\.newHttpClient|axios\.create\()' "$file" 2>/dev/null | head -5 || true)

done <<< "$SRC_FILES"

# Count findings by severity
critical=$(echo "$FINDINGS" | python3 -c "import json,sys; f=json.load(sys.stdin); print(sum(1 for x in f if x['severity']=='critical'))")
high=$(echo "$FINDINGS" | python3 -c "import json,sys; f=json.load(sys.stdin); print(sum(1 for x in f if x['severity']=='high'))")
medium=$(echo "$FINDINGS" | python3 -c "import json,sys; f=json.load(sys.stdin); print(sum(1 for x in f if x['severity']=='medium'))")
low=$(echo "$FINDINGS" | python3 -c "import json,sys; f=json.load(sys.stdin); print(sum(1 for x in f if x['severity']=='low'))")

# Calculate score — normalized per 1000 lines of code to be fair to large projects
score=$(python3 -c "
files = $total_files
# Penalty per finding, but scaled: larger projects tolerate more findings
total_penalty = ($critical*15 + $high*8 + $medium*4 + $low*1)
# Normalize: allow ~1 finding per 2 files before heavy penalty
expected_baseline = max(files * 0.5, 10)
normalized_penalty = total_penalty * (10 / max(expected_baseline, 1))
score = max(0, min(100, int(100 - normalized_penalty)))
print(score)
")

# Generate output JSON
python3 -c "
import json, sys
findings = json.loads('''$FINDINGS''')
report = {
    'project': '$PROJECT_ROOT',
    'timestamp': '$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")',
    'total_files_scanned': $total_files,
    'summary': {
        'total_findings': len(findings),
        'critical': $critical,
        'high': $high,
        'medium': $medium,
        'low': $low,
        'score': $score
    },
    'findings': findings
}
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(report, f, indent=2)
"

echo "✅ Static analysis complete: $OUTPUT_FILE"
echo "   Score: $score/100 | Critical: $critical | High: $high | Medium: $medium | Low: $low"
