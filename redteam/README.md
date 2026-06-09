# Red Team Security Assessment

Performs adversarial security analysis of source code, APIs, architecture, infrastructure, CI/CD pipelines, and cloud deployments. Finds vulnerabilities, exploit chains, business logic flaws, and architectural security risks.

## What It Does

1. Maps the attack surface (endpoints, auth, trust boundaries)
2. Models threats from multiple attacker perspectives (external, insider, supply chain)
3. Reviews code for OWASP Top 10 and CWE Top 25 vulnerabilities
4. Constructs exploit chains across components
5. Provides actionable remediation with PoC for every finding
6. Generates a standalone HTML report with light/dark theme
7. Opens the report in your default browser

## Trigger Phrases

- "Red team this service"
- "Security review of this codebase"
- "Find vulnerabilities in this API"
- "Analyze this code for security issues"
- "Threat model this architecture"

## Output

Every assessment produces:

- Concise text findings during analysis
- A standalone HTML5 report with:
  - Executive dashboard with severity counts
  - Light/dark theme toggle (defaults to system preference)
  - Expandable finding details with PoC and remediation
  - Attack path visualization
  - Prioritized remediation roadmap

## Installation

```bash
npx skills add shkna1368/skills --skill redteam
```

Or copy `SKILL.md` to your tool's skill/rules directory.
