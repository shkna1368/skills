# Skills

A collection of AI assistant skills for solving real-world problems.

## Available Skills

| Skill | Description |
|-------|-------------|
| [constraint-solver](constraint-solver/) | Solve constraint satisfaction & optimization problems with 4 solvers in parallel (OR-Tools, Timefold, Choco, Z3) |
| [microbench](microbench/) | Benchmark Java methods using JMH in Spring Boot and Quarkus projects. Detects anti-patterns (N+1, Thread.sleep, race conditions) and generates HTML report with fix recommendations. |
| [performance-engineer](performance-engineer/) | Profile and diagnose microservices for performance bottlenecks across Java, Go, Rust, Python, Node.js, and .NET. Load test, profile (async-profiler, JFR, pprof, py-spy), find root cause, and fix. |
| [redteam](redteam/) | Adversarial security analysis — finds vulnerabilities, exploit chains, business logic flaws. Generates HTML report with CVSS scores, CWE mappings, PoC, and remediation. |

## Installation

```bash
npx skills add shkna1368/skills --skill constraint-solver
npx skills add shkna1368/skills --skill microbench
npx skills add shkna1368/skills --skill performance-engineer
npx skills add shkna1368/skills --skill redteam
```

### Install in Agentic Coding Tools

<details>
<summary>Claude Code</summary>

```bash
# Install individual skills
claude mcp add skills-constraint-solver -- npx -y skills run shkna1368/skills --skill constraint-solver
claude mcp add skills-microbench -- npx -y skills run shkna1368/skills --skill microbench
claude mcp add skills-performance-engineer -- npx -y skills run shkna1368/skills --skill performance-engineer
claude mcp add skills-redteam -- npx -y skills run shkna1368/skills --skill redteam
```
</details>

<details>
<summary>Kiro</summary>

```bash
npx skills install shkna1368/skills --skill constraint-solver --client kiro
npx skills install shkna1368/skills --skill microbench --client kiro
npx skills install shkna1368/skills --skill performance-engineer --client kiro
npx skills install shkna1368/skills --skill redteam --client kiro
```

Or copy each skill's `SKILL.md` to `.kiro/skills/<skill-name>/SKILL.md` in your project.
</details>

<details>
<summary>Codex</summary>

```bash
npx skills install shkna1368/skills --skill constraint-solver --client codex
npx skills install shkna1368/skills --skill microbench --client codex
npx skills install shkna1368/skills --skill performance-engineer --client codex
npx skills install shkna1368/skills --skill redteam --client codex
```

Or copy `SKILL.md` content into your Codex instructions file (`AGENTS.md` or `codex.md`).
</details>

<details>
<summary>Cursor</summary>

```bash
npx skills install shkna1368/skills --skill constraint-solver --client cursor
npx skills install shkna1368/skills --skill microbench --client cursor
npx skills install shkna1368/skills --skill performance-engineer --client cursor
npx skills install shkna1368/skills --skill redteam --client cursor
```

Or copy each skill's `SKILL.md` to `.cursor/rules/<skill-name>.md` in your project.
</details>

<details>
<summary>Windsurf</summary>

```bash
npx skills install shkna1368/skills --skill constraint-solver --client windsurf
npx skills install shkna1368/skills --skill microbench --client windsurf
npx skills install shkna1368/skills --skill performance-engineer --client windsurf
npx skills install shkna1368/skills --skill redteam --client windsurf
```

Or copy each skill's `SKILL.md` to `.windsurf/rules/<skill-name>.md` in your project.
</details>

<details>
<summary>Amazon Q Developer CLI</summary>

Copy each skill's `SKILL.md` to `.amazonq/rules/<skill-name>.md` in your project:

```bash
# Manual setup
mkdir -p .amazonq/rules
cp constraint-solver/SKILL.md .amazonq/rules/constraint-solver.md
cp microbench/SKILL.md .amazonq/rules/microbench.md
cp performance-engineer/SKILL.md .amazonq/rules/performance-engineer.md
cp redteam/SKILL.md .amazonq/rules/redteam.md
```
</details>

## Author

**Shabab Koohi** — [GitHub](https://github.com/shkna1368)

## License

MIT — see [LICENSE](LICENSE) for details.
