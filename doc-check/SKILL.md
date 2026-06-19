---
name: doc-check
description: Analyzes a project's source code to detect its framework, fetches relevant documentation via the docpilot MCP server (searchDocs), and validates whether the code follows best practices from the official docs.
---

# Doc-Check Skill

## Description

Detects the framework/technology used in a project, identifies the most important patterns in the source code (routing, DI, middleware, auth, database, config), queries the `searchDocs` MCP tool for official documentation, and validates whether the code matches documented best practices. Produces a compliance report.

## When to Use

- User asks "does my code follow best practices?"
- User asks to validate code against documentation
- User wants to check if their framework usage is correct
- User asks "am I using X correctly?"
- After writing new code that uses a framework API

## Inputs

- `projectDir`: Root directory of the project (defaults to current working directory)
- `files`: Optional specific files to check (defaults to scanning key source files)
- `framework`: Optional explicit framework override (skips detection)

## Step 0 — Ensure docpilot MCP Server is Available

Before any doc validation, verify the `searchDocs` tool is accessible. If it is not, set it up automatically.

### Reference Links

For troubleshooting, supported frameworks list, and full API documentation:
- **GitHub**: https://github.com/shkna1368/docpilot/
- **Documentation**: https://shkna1368.github.io/docpilot/

### Check

1. Try calling `listFrameworks`. If it succeeds → MCP is ready, proceed to Step 1.
2. If `listFrameworks` fails or `searchDocs` tool is not found → the MCP server is not configured.

### Auto-Setup

If the MCP server is not available, perform these steps:

#### 1. Check Docker is installed

```bash
docker --version
```

If Docker is not installed, tell the user: "Docker is required for docpilot. Install from https://docker.com" and stop.

#### 2. Pull the docpilot image

```bash
docker pull ghcr.io/shkna1368/docpilot:latest
```

#### 3. Detect the user's AI coding tool and configure

Check which tool is being used and add the MCP server config:

**Kiro** — Write to `~/.kiro/settings/mcp.json`:
```bash
# Read existing config or create new
MCP_FILE="$HOME/.kiro/settings/mcp.json"
mkdir -p "$(dirname "$MCP_FILE")"
```
Add to the JSON:
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

**Claude Code** — Run:
```bash
claude mcp add framework-docs -- docker run -i --rm ghcr.io/shkna1368/docpilot:latest
```

**Cursor** — Write to `.cursor/mcp.json` in the project root:
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

**Windsurf** — Write to `.windsurf/mcp.json` in the project root:
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

**VS Code / Copilot** — Write to `.vscode/mcp.json` in the project root:
```json
{
  "servers": {
    "framework-docs": {
      "type": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "ghcr.io/shkna1368/docpilot:latest"]
    }
  }
}
```

#### 4. Notify the user

After configuring, tell the user:
> "I've configured the docpilot MCP server. Please restart your AI tool (or reload MCP servers) for the changes to take effect, then re-run doc-check."

If the tool supports hot-reload of MCP servers, proceed directly. Otherwise, stop and wait for the user to restart.

#### 5. Verify after restart

Call `listFrameworks` again to confirm the server is running. If it still fails, check:
- Is Docker daemon running? (`docker info`)
- Can the image be pulled? (network/auth issues)
- Report the error to the user with the specific failure message.

---

## Step 1 — Detect Framework

Read project manifest files to determine the framework:

| File | Check for | Framework ID |
|------|-----------|--------------|
| `go.mod` | `github.com/gofiber/fiber` | `go-fiber` |
| `go.mod` | `github.com/gin-gonic/gin` | `go-gin` |
| `go.mod` | `github.com/labstack/echo` | `go-echo` |
| `pom.xml` | `spring-boot` | `spring-boot` |
| `pom.xml` | `spring-security` | `spring-security` |
| `pom.xml` | `spring-data` | `spring-data` |
| `pom.xml` | `spring-cloud` | `spring-cloud` |
| `pom.xml` | `quarkus` | `quarkus` |
| `build.gradle` / `build.gradle.kts` | same as pom.xml | same |
| `*.csproj` | `Microsoft.AspNetCore` | `aspnet-core` |
| `requirements.txt` / `pyproject.toml` | `fastapi` | `fastapi` |
| `requirements.txt` / `pyproject.toml` | `django` | `django` |
| `requirements.txt` / `pyproject.toml` | `flask` | `flask` |
| `Cargo.toml` | `actix-web` | `actix-web` |
| `Cargo.toml` | `rocket` | `rocket` |
| `Cargo.toml` | `axum` | `axum` |
| `package.json` | `@nestjs/core` | `nestjs` |
| `package.json` | `@angular/core` | `angular` |
| `package.json` | `"react"` | `react` |
| `package.json` | `"express"` | `express` |

If detection fails, call `listFrameworks` and ask the user which framework to check against.

## Step 2 — Identify Key Patterns in Code

Scan the source files and identify which of these pattern categories are present:

| Category | What to look for |
|----------|-----------------|
| Routing / Endpoints | Route definitions, controllers, handlers |
| Middleware | Request/response pipeline, filters, interceptors |
| Dependency Injection | DI containers, providers, beans, services |
| Authentication / Authorization | Auth guards, security config, JWT, OAuth |
| Database / ORM | Queries, repositories, migrations, models |
| Configuration | Config files, environment loading, profiles |
| Error Handling | Exception handlers, error middleware, fallbacks |
| Caching | Cache annotations, Redis usage, cache strategies |
| Testing | Test setup, mocking patterns, test utilities |
| API Design | Request/response DTOs, validation, serialization |

For each category found, extract one or two representative code snippets (the most complex or critical ones).

## Step 3 — Query Documentation

For each identified pattern, call `searchDocs` with:

```
searchDocs(
  query: "<pattern description> <framework-specific terms>",
  framework: "<detected-framework-id>",
  maxResults: 4,
  projectDir: "<projectDir>"
)
```

Query construction rules:
- Use the pattern category + specific API names found in code
- Example: if code has `@Cacheable` in Spring Boot → query: `"spring cache @Cacheable configuration best practices"`
- Example: if code has `app.Use()` in Fiber → query: `"fiber middleware registration order"`
- Example: if code has `Depends()` in FastAPI → query: `"fastapi dependency injection Depends"`

Make one `searchDocs` call per pattern category (max 5 calls to avoid overload). Prioritize patterns that are:
1. Security-related (auth, validation, CORS)
2. Error-prone (database, caching, middleware order)
3. Configuration-heavy (DI, startup, profiles)

## Step 4 — Validate Code Against Docs

For each pattern, compare the code against the documentation returned and check:

| Check | What it means |
|-------|---------------|
| ✅ Correct | Code matches documented usage |
| ⚠️ Improvement | Code works but misses recommended practice |
| ❌ Incorrect | Code contradicts documentation or uses deprecated API |

Common validation checks per category:

**Routing**: Correct HTTP methods, parameter binding, response types
**Middleware**: Registration order matters (e.g., CORS before auth), correct handler signatures
**DI**: Proper scope (singleton vs request-scoped), circular dependency risks
**Auth**: Required companion annotations (e.g., `@EnableWebSecurity`), correct filter chain order
**Database**: Transaction boundaries, N+1 query prevention, connection pool config
**Caching**: Required enablement annotations, TTL configuration, eviction strategy
**Config**: Profile-specific overrides, secret handling, type-safe config binding
**Error Handling**: Global vs local handlers, proper status codes, error response format

## Step 5 — Produce Report

Output a concise report in this format:

```
## Doc-Check Report: <project-name> (<framework>)

### Summary
- Framework: <name> <version>
- Files checked: <count>
- Patterns analyzed: <count>
- ✅ Correct: N | ⚠️ Improvements: N | ❌ Issues: N

### Findings

#### <Category> — <✅|⚠️|❌>

**Code:**
<relevant snippet>

**Documentation says:**
<key point from searchDocs result>

**Verdict:** <explanation of match or mismatch>

**Fix (if needed):**
<corrected code>

---
(repeat for each finding)

### Recommendations
1. <Most critical fix>
2. <Second priority>
3. ...
```

## Rules

- Never hallucinate documentation. Only use content returned by `searchDocs`.
- If `searchDocs` returns no results for a pattern, state "No documentation found" and skip validation for that pattern.
- Always show the relevant doc excerpt that supports your verdict.
- Prioritize findings by severity: ❌ first, then ⚠️, then ✅.
- Limit report to the 5-8 most impactful findings, not every line of code.
- If the framework is not in docpilot's index, tell the user and offer to check patterns generically.

## Example Usage

User: "Check if my Spring Boot code follows best practices"

Agent actions:
1. Read `pom.xml` → detect `spring-boot`
2. Scan `src/main/java/` → find `@RestController`, `@Cacheable`, `@Transactional`, `SecurityConfig`
3. Call `searchDocs(query: "spring boot caching @Cacheable @EnableCaching", framework: "spring-boot")`
4. Call `searchDocs(query: "spring security filter chain configuration", framework: "spring-boot")`
5. Call `searchDocs(query: "spring boot transaction management best practices", framework: "spring-boot")`
6. Compare code vs docs → produce findings report

## Step 6 — Generate HTML Report

After producing the text report, generate a responsive HTML file (`doc-check-report.html`) with:

- **Dark/light theme** toggle (respects `prefers-color-scheme`, manual toggle button)
- **Summary dashboard**: framework, version, files checked, pattern count, ✅/⚠️/❌ counts
- **Expandable findings**: each with code snippet, doc quote with source link, verdict, and fix
- **Recommendations section**: prioritized next steps
- **Responsive layout**: works on mobile and desktop

After generating the report, open it:

```bash
open doc-check-report.html          # macOS
xdg-open doc-check-report.html     # Linux
```
