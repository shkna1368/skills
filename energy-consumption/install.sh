#!/bin/bash
# Prerequisites installer for Energy Consumption Analysis
# Cross-platform: Linux, macOS, Windows (Git Bash / WSL)
set -euo pipefail

echo "🔧 Energy Consumption Analysis — Prerequisites Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Detect OS
case "$(uname -s 2>/dev/null || echo Windows)" in
  Darwin*)  OS="macos" ;;
  Linux*)   OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) OS="windows" ;;
  *)        OS="linux" ;;
esac
echo "   Platform: $OS"

MISSING=()
INSTALLED=()

# --- Check required tools ---

# Python 3
if command -v python3 &>/dev/null; then
  INSTALLED+=("python3 $(python3 --version 2>&1 | awk '{print $2}')")
else
  MISSING+=("python3")
fi

# Docker
if command -v docker &>/dev/null; then
  INSTALLED+=("docker $(docker --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')")
else
  MISSING+=("docker")
fi

# Docker Compose
if command -v docker-compose &>/dev/null || docker compose version &>/dev/null; then
  INSTALLED+=("docker-compose")
else
  MISSING+=("docker-compose")
fi

# curl
if command -v curl &>/dev/null; then
  INSTALLED+=("curl")
else
  MISSING+=("curl")
fi

# Load testing tool (optional but recommended)
LOAD_TOOL=""
if command -v hey &>/dev/null; then
  LOAD_TOOL="hey"
  INSTALLED+=("hey (load testing)")
elif command -v ab &>/dev/null; then
  LOAD_TOOL="ab"
  INSTALLED+=("ab (load testing)")
elif command -v wrk &>/dev/null; then
  LOAD_TOOL="wrk"
  INSTALLED+=("wrk (load testing)")
fi

# --- Print status ---
echo ""
echo "✅ Installed:"
for tool in "${INSTALLED[@]}"; do
  echo "   • $tool"
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "❌ Missing (required):"
  for tool in "${MISSING[@]}"; do
    echo "   • $tool"
  done
fi

if [ -z "$LOAD_TOOL" ]; then
  echo ""
  echo "⚠️  No load testing tool found (optional but recommended)"
  echo "   Install one for accurate runtime measurement."
fi

# --- Install missing tools ---
if [ ${#MISSING[@]} -gt 0 ] || [ -z "$LOAD_TOOL" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Installing missing dependencies..."
  echo ""

  case "$OS" in
    macos)
      # Ensure Homebrew
      if ! command -v brew &>/dev/null; then
        echo "   Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      for tool in "${MISSING[@]}"; do
        case "$tool" in
          python3)  echo "   brew install python3..."; brew install python3 ;;
          docker)   echo "   ⚠️  Install Docker Desktop from https://docker.com/products/docker-desktop"; ;;
          docker-compose) echo "   Included with Docker Desktop" ;;
          curl)     echo "   brew install curl..."; brew install curl ;;
        esac
      done
      if [ -z "$LOAD_TOOL" ]; then
        echo "   Installing hey (load testing tool)..."
        brew install hey 2>/dev/null || go install github.com/rakyll/hey@latest 2>/dev/null || true
      fi
      ;;

    linux)
      # Detect package manager
      if command -v apt-get &>/dev/null; then
        PKG="apt-get install -y"
        SUDO="sudo"
      elif command -v dnf &>/dev/null; then
        PKG="dnf install -y"
        SUDO="sudo"
      elif command -v pacman &>/dev/null; then
        PKG="pacman -S --noconfirm"
        SUDO="sudo"
      elif command -v apk &>/dev/null; then
        PKG="apk add"
        SUDO=""
      else
        PKG=""
        SUDO=""
      fi

      if [ -n "$PKG" ]; then
        for tool in "${MISSING[@]}"; do
          case "$tool" in
            python3)  echo "   Installing python3..."; $SUDO $PKG python3 ;;
            docker)   echo "   Installing docker..."; curl -fsSL https://get.docker.com | sh ;;
            docker-compose) echo "   Installing docker-compose..."; $SUDO $PKG docker-compose 2>/dev/null || true ;;
            curl)     echo "   Installing curl..."; $SUDO $PKG curl ;;
          esac
        done
        if [ -z "$LOAD_TOOL" ]; then
          echo "   Installing hey (load testing tool)..."
          if command -v go &>/dev/null; then
            go install github.com/rakyll/hey@latest 2>/dev/null || true
          else
            $SUDO $PKG apache2-utils 2>/dev/null || true  # installs 'ab'
          fi
        fi
      else
        echo "   ⚠️  No supported package manager found. Install manually."
      fi
      ;;

    windows)
      echo "   Windows detected. Install via:"
      for tool in "${MISSING[@]}"; do
        case "$tool" in
          python3)  echo "   • python3: winget install Python.Python.3" ;;
          docker)   echo "   • docker: winget install Docker.DockerDesktop" ;;
          docker-compose) echo "   • docker-compose: Included with Docker Desktop" ;;
          curl)     echo "   • curl: winget install cURL.cURL" ;;
        esac
      done
      if [ -z "$LOAD_TOOL" ]; then
        echo "   • hey: go install github.com/rakyll/hey@latest"
        echo "     OR download from https://github.com/rakyll/hey/releases"
      fi
      ;;
  esac
fi

# --- Final verification ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ALL_OK=true
for tool in python3 docker curl; do
  if ! command -v "$tool" &>/dev/null; then
    ALL_OK=false
  fi
done

if [ "$ALL_OK" = true ]; then
  echo "✅ All prerequisites satisfied. Ready to run energy analysis!"
  echo ""
  echo "   Usage:"
  echo "   bash ~/.kiro/skills/energy-consumption/static-analysis.sh <project>"
  echo "   bash ~/.kiro/skills/energy-consumption/runtime-analysis.sh <project> <endpoint> <duration> <concurrency>"
  echo "   bash ~/.kiro/skills/energy-consumption/generate-report.sh <project>"
else
  echo "❌ Some prerequisites still missing. Please install them manually."
  exit 1
fi
