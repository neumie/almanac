# CLAUDE.md Best Practices

## Core Principle

CLAUDE.md files exist for things an agent **cannot derive from the code**. If it can be found via `grep`, `find`, or reading the file — don't document it. Every line should earn its place by preventing a mistake or saving significant exploration time.

## What belongs in CLAUDE.md

### High value (always include)

- **"Use X, not Y" rules** — when the obvious approach is wrong. Example: "Always use the config registry. Never hardcode config values."
- **Non-obvious gotchas** — things that compile fine but break at runtime. Example: "`getId()` returns the DB surrogate key, not the business entity ID — use `getEntityId()` instead."
- **Commands that aren't discoverable** — multi-step workflows, CI workarounds, non-standard build steps.
- **Architecture decisions that aren't obvious from structure** — why a package has no external dependencies, why two modules are split, why an abstraction exists.
- **Integration patterns** — how to wire up a new feature across multiple packages or layers.
- **Deep module enforcement** — when a shared abstraction exists (registry, repository, logger), mandate its use with "always/never" language. Agents will create shallow inline alternatives if not explicitly told to use the deep module.

### Medium value (include if genuinely non-obvious)

- **Build/dev commands** — only if non-standard.
- **Environment quirks** — dynamic ports, two-phase migrations, platform-specific behavior.
- **Framework-specific patterns** — patterns unique to the framework that differ from the obvious approach.

### Low value (usually omit)

- **File/directory listings** — agents can `ls` and `find`.
- **Export catalogs** — agents can `grep` for exports.
- **Type definitions** — agents can read the source.
- **Things documented in the code itself** — docstrings, inline comments, README files.
- **Generic best practices** — "write tests", "follow SOLID", "use meaningful names".

## Structure

### Root CLAUDE.md

The primary file. Contains:

- Project overview (1-2 sentences)
- Key commands (build, test, dev, deploy)
- Architecture decisions and patterns that apply project-wide
- Critical rules ("never do X")
- Non-obvious workflows (schema changes, migrations, data fixes)
- Deep module mandates — which shared abstractions agents must use and extend

Target: under 400 lines. If longer, move domain-specific content to subdirectory files.

### Subdirectory CLAUDE.md

Narrow scope — one concern per file. Place next to the code it describes.

**Good examples:**

- `src/auth/CLAUDE.md` — documents the token refresh flow (one non-obvious pattern, 20 lines)
- `lib/db/CLAUDE.md` — documents the repository pattern (naming, query conventions, caching rules)

**Bad examples:**

- `src/CLAUDE.md` that lists every module and export — this is a catalog, not guidance
- `lib/CLAUDE.md` that restates the root file

### When to create a subdirectory CLAUDE.md

Create one when ALL of these are true:

1. There's a non-obvious pattern specific to this directory
2. The pattern would be out of place in the root file
3. Someone working in this directory would likely make a mistake without it

## Writing rules

### Be prescriptive, not descriptive

Bad: "The config registry provides centralized configuration management."
Good: "Always use `getConfig(key)` for configuration values. Never hardcode config or read env vars directly."

Bad: "The logging module handles structured logging."
Good: "Always use the logger. Never `console.log` or `print` directly — the logger handles formatting, levels, and transport."

### Enforce deep modules

Bad: "We have a repository layer for DB access."
Good: "Always use the repository. Never write raw queries outside `lib/db/`. If you need a new query, add a method to the repository — don't create a one-off."

Bad: "Prefer using the config registry."
Good: "Always use `getConfig()`. Never read env vars directly. If a new config value is needed, add it to the registry with validation — don't create a separate config reader."

"Prefer" is too weak — agents rationalize around it. "Always/never" is the bar. And always tell agents to **extend** the deep module when their use case isn't covered yet — otherwise they'll build around it.

### Include a decision framework for new code

Bad: (nothing — agent creates whatever seems fastest)
Good: "Before creating a new utility: (1) check if an existing module covers the use case, (2) if creating new, will it have multiple callers? If yes, design the interface first. If no, a simple inline solution is fine."

### Lead with the rule, follow with the why

```
Never insert fallback defaults for values the schema guarantees.
Defaulting a "shouldn't be null" value silently converts a data bug into wrong behavior.
```

### Use concrete examples for gotchas

```
**Wrong:** `user.getId()` — returns the internal DB surrogate key (auto-increment).
**Right:** `user.getEntityId()` — returns the business entity UUID used across services.
```

### Keep commands copy-paste ready

```bash
docker compose down -v && docker compose up -d && npm run db:migrate    # Full reset
```

Not: "Bring down the containers, then bring them back up and run migrations."

### Don't explain what the code does — explain what to watch out for

Bad:
```
## Utilities
- `formatDate()` — formats a date to ISO string
- `parseConfig()` — parses YAML config files
- `hashPassword()` — hashes passwords with bcrypt
```

Good:
```
## Utilities
Use `formatDate()` (not `toISOString()`) — it applies the project's timezone normalization. Raw `toISOString()` produces UTC which breaks date comparisons in reports.
```

## Anti-patterns

### The catalog

Listing every file, export, or directory. Agents can discover these. They rot as the codebase changes.

### The tutorial

Step-by-step explanations of how things work. CLAUDE.md is a reference, not a guide. If an agent needs to understand a pattern, it can read the code.

### The duplicate

Restating information from the root CLAUDE.md in a subdirectory file. Subdirectory files should only add NEW information specific to their scope.

### The aspirational

Documenting how things SHOULD work rather than how they DO work. CLAUDE.md must reflect the current codebase.

### The obvious

"Use PascalCase for classes." "Files are in kebab-case." If it's enforced by the linter or visible from any file in the directory, don't document it.

### The weak mandate

"Prefer using X." "Consider using Y." "You might want to check Z." Agents treat soft language as optional. Use "always/never" for things that must be followed.

## Maintenance

- Update CLAUDE.md when you discover a new gotcha during a session
- Remove entries when the underlying issue is fixed
- Review for staleness when major refactors land
- If a CLAUDE.md entry causes an agent to do the wrong thing, delete it immediately

## Quality test

For each line in a CLAUDE.md, ask: "If this line were missing, would an agent make a mistake or waste significant time?" If no, delete it.
