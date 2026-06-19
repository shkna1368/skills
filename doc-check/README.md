# Doc-Check

Validates source code against official framework documentation using the [docpilot](https://github.com/shkna1368/docpilot) MCP server. Detects your framework, identifies key patterns, queries real docs, and reports whether your code follows best practices.

## What It Does

1. Detects framework from project manifests (go.mod, pom.xml, package.json, Cargo.toml, etc.)
2. Scans source code for key patterns (routing, DI, auth, caching, database, config)
3. Queries `searchDocs` MCP tool for official documentation on each pattern
4. Validates code against returned documentation
5. Produces a compliance report with ✅/⚠️/❌ verdicts and fixes
6. Generates a responsive HTML report with light/dark theme

## Trigger Phrases

- "Does my code follow best practices?"
- "Check if my Spring Boot code is correct"
- "Validate this against the docs"
- "Am I using FastAPI correctly?"
- "Doc-check this project"

## Supported Frameworks

Go (Fiber, Gin, Echo) · Java (Spring Boot, Spring Security, Spring Data, Spring Cloud, Quarkus) · Python (FastAPI, Django, Flask) · Rust (Actix-web, Rocket, Axum) · TypeScript (NestJS, Angular, React) · JavaScript (Express) · C# (ASP.NET Core) · and 30+ more technologies via docpilot.

## Requirements

The `framework-docs` MCP server (docpilot) must be configured:

```json
{
  "mcpServers": {
    "framework-docs": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "ghcr.io/shkna1368/docpilot:latest"]
    }
  }
}
```

## Output

Every check produces:

- Text findings during analysis
- A standalone HTML5 report with:
  - Summary dashboard (framework, files checked, pass/warn/fail counts)
  - Light/dark theme toggle (defaults to system preference)
  - Expandable findings with code snippets, doc quotes, verdicts, and fixes
  - Prioritized recommendations

## Installation

```bash
npx skills add shkna1368/skills --skill doc-check
```

Or copy `SKILL.md` to your tool's skill/rules directory.
