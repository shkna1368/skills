# Changelog

## 1.0.0 (2026-06-22)

### Features
- Static code analysis (10+ energy waste patterns across all languages)
- Dockerfile analysis (9 anti-patterns with estimated waste in MB)
- Runtime analysis with load testing (hey/ab/wrk/curl)
- Auto-discovery of endpoints from docker-compose, source code, and README
- Auto-detection of HTTP method and body from README curl examples
- Idle vs load comparison with efficiency ratio
- Container analysis for Docker and Kubernetes (multi-sample)
- Per-service energy breakdown in Joules
- Energy per request (mJ/request)
- CO₂ emissions estimate with region-aware carbon intensity
- Cloud cost profiles (AWS, Azure, GCP, custom)
- Carbon region comparison with deployment recommendation
- Historical trend tracking across runs
- Network waste detection (chatty HTTP, missing connection reuse)
- JVM/runtime-specific optimization tips
- Achievement badges based on actual metrics
- Wall of Shame — roasts worst offending services
- Fun facts section (hamsters, SpaceX rockets, burritos, etc.)
- Responsive HTML report with dark/light mode toggle
- Cross-platform support (macOS, Linux, Windows)
- Prerequisites installer (auto-installs via brew/apt/dnf/pacman/winget)
