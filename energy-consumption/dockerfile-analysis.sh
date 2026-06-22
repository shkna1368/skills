#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${1:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/energy-report"
OUTPUT_FILE="$OUTPUT_DIR/dockerfile-analysis.json"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FINDINGS="[]"
TOTAL=0

add_finding() {
  local sev="$1" file="$2" line="$3" pattern="$4" msg="$5" waste="$6"
  FINDINGS=$(printf '%s' "$FINDINGS" | python3 -c "
import sys,json
f=json.loads(sys.stdin.read())
f.append({'severity':'$sev','file':'$file','line':$line,'pattern':'$pattern','message':$(python3 -c "import json;print(json.dumps('$msg'))"),'estimated_waste_mb':$waste})
print(json.dumps(f))")
}

# Find all Dockerfiles
DOCKERFILES=()
while IFS= read -r -d '' df; do
  DOCKERFILES+=("$df")
done < <(find "$PROJECT_ROOT" -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -print0 2>/dev/null)

TOTAL=${#DOCKERFILES[@]}

for DF in "${DOCKERFILES[@]}"; do
  REL_FILE="${DF#$PROJECT_ROOT/}"
  
  # Read file content
  CONTENT=$(cat "$DF")
  
  # Count FROM instructions
  FROM_COUNT=$(grep -ci "^FROM " "$DF" || true)
  
  # CRITICAL: No multi-stage build with build tools
  if [ "$FROM_COUNT" -le 1 ]; then
    if grep -qiE "(gcc|g\+\+|make|maven|gradle|cargo|go build|dotnet build|javac|npm run build)" "$DF"; then
      add_finding "CRITICAL" "$REL_FILE" 1 "no_multistage" "Single FROM with build tools in final image" 500
    fi
  fi

  # HIGH: Large base images
  while IFS= read -r line_info; do
    LNUM=$(echo "$line_info" | cut -d: -f1)
    LINE=$(echo "$line_info" | cut -d: -f2-)
    if echo "$LINE" | grep -qiE "FROM\s+(ubuntu|debian|centos|fedora|amazonlinux)[: ]" && \
       ! echo "$LINE" | grep -qiE "(slim|minimal)"; then
      add_finding "HIGH" "$REL_FILE" "$LNUM" "large_base_image" "Using large base image instead of alpine/slim/distroless" 600
    fi
  done < <(grep -niE "^FROM " "$DF" || true)

  # HIGH: COPY . without .dockerignore
  DIR_OF_DF=$(dirname "$DF")
  HAS_DOCKERIGNORE=false
  [ -f "$DIR_OF_DF/.dockerignore" ] || [ -f "$PROJECT_ROOT/.dockerignore" ] && HAS_DOCKERIGNORE=true
  if [ "$HAS_DOCKERIGNORE" = false ]; then
    while IFS= read -r line_info; do
      LNUM=$(echo "$line_info" | cut -d: -f1)
      if echo "$line_info" | grep -qE "COPY\s+\.[\s/]"; then
        add_finding "HIGH" "$REL_FILE" "$LNUM" "copy_all_no_dockerignore" "COPY of entire directory without .dockerignore" 200
      fi
    done < <(grep -nE "^COPY " "$DF" || true)
  fi

  # MEDIUM: Too many RUN layers
  RUN_COUNT=$(grep -c "^RUN " "$DF" || true)
  if [ "$RUN_COUNT" -gt 10 ]; then
    add_finding "MEDIUM" "$REL_FILE" 1 "too_many_run_layers" "Too many RUN layers ($RUN_COUNT > 10), combine with &&" 50
  fi

  # MEDIUM: Package manager cache not cleaned
  while IFS= read -r line_info; do
    LNUM=$(echo "$line_info" | cut -d: -f1)
    LINE=$(echo "$line_info" | cut -d: -f2-)
    if echo "$LINE" | grep -qE "apt-get install" && \
       ! echo "$LINE" | grep -qE "(--no-install-recommends|rm -rf /var/lib/apt)"; then
      # Check if same RUN block has cleanup (multi-line)
      add_finding "MEDIUM" "$REL_FILE" "$LNUM" "no_cache_clean" "Package manager cache not cleaned after install" 100
    fi
  done < <(grep -nE "apt-get install" "$DF" || true)

  # MEDIUM: Dev dependencies in production
  while IFS= read -r line_info; do
    LNUM=$(echo "$line_info" | cut -d: -f1)
    LINE=$(echo "$line_info" | cut -d: -f2-)
    if echo "$LINE" | grep -qE "npm install" && ! echo "$LINE" | grep -qE "(--production|--omit=dev|NODE_ENV=production|ci --only=production)"; then
      add_finding "MEDIUM" "$REL_FILE" "$LNUM" "dev_deps_in_prod" "npm install without --production flag includes dev dependencies" 80
    fi
    if echo "$LINE" | grep -qE "pip install.*(dev|test)" && ! echo "$LINE" | grep -qE "requirements\.txt"; then
      add_finding "MEDIUM" "$REL_FILE" "$LNUM" "dev_deps_in_prod" "Installing dev/test packages with pip in production image" 50
    fi
  done < <(grep -nE "^RUN " "$DF" || true)

  # LOW: No HEALTHCHECK
  if ! grep -qi "^HEALTHCHECK" "$DF"; then
    add_finding "LOW" "$REL_FILE" 1 "no_healthcheck" "No HEALTHCHECK instruction defined" 0
  fi

  # LOW: Using latest tag
  while IFS= read -r line_info; do
    [ -z "$line_info" ] && continue
    LNUM=$(echo "$line_info" | cut -d: -f1)
    LINE=$(echo "$line_info" | cut -d: -f2-)
    IMG=$(echo "$LINE" | sed -E 's/^[Ff][Rr][Oo][Mm]\s+(\S+).*/\1/')
    if echo "$IMG" | grep -q ":latest" || ! echo "$IMG" | grep -q ":"; then
      add_finding "LOW" "$REL_FILE" "$LNUM" "latest_tag" "Using :latest or unpinned tag instead of specific version" 0
    fi
  done < <(grep -niE "^FROM " "$DF" || true)

  # LOW: COPY before dependency install (breaks caching)
  COPY_ALL_LINE=0
  DEP_INSTALL_LINE=0
  while IFS= read -r line_info; do
    LNUM=$(echo "$line_info" | cut -d: -f1)
    LINE=$(echo "$line_info" | cut -d: -f2-)
    if [ "$COPY_ALL_LINE" -eq 0 ] && echo "$LINE" | grep -qE "^COPY\s+\.\s"; then
      COPY_ALL_LINE=$LNUM
    fi
    if echo "$LINE" | grep -qE "(npm install|pip install|go mod download|mvn dependency|gradle dependencies|dotnet restore|cargo build)"; then
      DEP_INSTALL_LINE=$LNUM
    fi
  done < <(grep -nE "^(COPY|RUN) " "$DF" || true)
  if [ "$COPY_ALL_LINE" -gt 0 ] && [ "$DEP_INSTALL_LINE" -gt 0 ] && [ "$COPY_ALL_LINE" -lt "$DEP_INSTALL_LINE" ]; then
    add_finding "LOW" "$REL_FILE" "$COPY_ALL_LINE" "copy_before_deps" "COPY . before dependency install breaks layer caching" 0
  fi
done

# Generate summary and output
python3 -c "
import json,sys
findings = json.loads('''$FINDINGS''')
summary = {'critical':0,'high':0,'medium':0,'low':0,'estimated_image_waste_mb':0}
for f in findings:
    s = f['severity'].lower()
    if s in summary: summary[s] += 1
    summary['estimated_image_waste_mb'] += f.get('estimated_waste_mb',0)
result = {
    'timestamp': '$TIMESTAMP',
    'total_dockerfiles': $TOTAL,
    'findings': findings,
    'summary': summary
}
with open('$OUTPUT_FILE','w') as out:
    json.dump(result, out, indent=2)
print(json.dumps(summary, indent=2))
"

echo ""
echo "Dockerfile analysis complete: $OUTPUT_FILE"
echo "Analyzed $TOTAL Dockerfile(s)"
