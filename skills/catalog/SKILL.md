---
name: catalog
description: Use when the user asks what skills are available, needs help choosing a workflow, or wants to understand the toolkit. Lists all skills organized by workflow phase with guidance on combining them.
---

# Skill Catalog

## By Workflow Phase

### Plan
- **planning** — Architecture decisions, task breakdown, trade-off analysis. Use before jumping into any multi-step coding task.
- **catalog** — This skill. Lists available skills and when to use them.

### Build
- **tdd** — Red-green-refactor cycle with vertical slice methodology. Use when building features or fixing bugs test-first.
- **frontend-design** — Distinctive production-grade web interfaces. Use when creating or improving any web UI.
- **mcp-builder** — Build MCP servers in TypeScript or Python. Use when integrating external APIs as tools for LLMs.
- **skill-creator** — Create and validate skills against the Agent Skills Open Standard. Use when building new skills.

### Test
- **debugging** — Hypothesis-driven root cause analysis. Use when encountering errors, test failures, or unexpected behavior.
- **webapp-testing** — Test web apps with agent-browser. Use for visual inspection, interaction testing, and e2e validation.

### Assess
- **frontend-perf** — Page loads, Core Web Vitals, bundle size, runtime performance. Use when assessing or optimizing web page performance.
- **backend-perf** — Database queries, API response times, caching, resource usage. Use when assessing or optimizing server-side performance.

### Review
- **code-review** — Branch-scoped technical review: correctness, security, performance, readability, testing. Diffs against base branch and produces a structured report.
- **branch-summary** — Business-focused narrative of branch changes. Groups by feature, explains impact, includes manual testing steps.
- **refactoring** — Safe code restructuring without changing external behavior. Use when cleaning up or simplifying code.

### Ship
- **commit** — Analyze changes, write conventional commit messages, stage and commit safely. Use when committing code.
- **push** — Push to remote with safety checks. Handles upstream tracking, diverged branches, force-push protection.
- **rebase** — Rebase onto base branch with conflict handling and optional squash. Use before PRs to sync with main.
- **create-pr** — Generate PR title and description from branch commits, push if needed, create the PR. Use when ready to merge.
- **git-workflow** — Conventions reference: commit format, branch naming, safety rules. Referenced by other ship skills.

### Fix
- **branch-fix** — Fix problems using a saved branch summary as a map. Use after branch-summary to make targeted corrections.

## Combining Skills

Common combinations:
- **New feature**: planning -> tdd -> code-review -> commit -> push -> create-pr
- **Bug fix**: debugging -> tdd (regression test) -> commit -> push -> create-pr
- **UI work**: planning -> frontend-design -> webapp-testing -> code-review -> commit -> create-pr
- **New integration**: planning -> mcp-builder -> tdd -> code-review -> commit -> create-pr
- **Performance audit**: frontend-perf + backend-perf -> planning -> tdd
- **Before PR**: rebase -> code-review -> push -> create-pr
- **Branch catch-up**: branch-summary -> branch-fix -> commit

Start with **planning** for multi-step work. Use **tdd** during implementation. Run **code-review** before shipping. Use **commit** -> **push** -> **create-pr** to ship.

## Reference Material

Most skills include `references/` directories with supporting docs loaded on demand:
- `skills/planning/references/` — task templates, architect role, vertical slice pattern
- `skills/git-workflow/references/` — commit format, safety guardrails
- `skills/debugging/references/` — debugging session template
- `skills/mcp-builder/references/` — TypeScript/Python guides, best practices
- `skills/skill-creator/references/` — spec summary, progressive disclosure pattern
- `skills/frontend-perf/references/` — Lighthouse guide, bundle analysis
- `skills/backend-perf/references/` — database analysis, caching patterns
