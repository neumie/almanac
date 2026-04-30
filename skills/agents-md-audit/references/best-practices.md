# CLAUDE.md Best Practices

## Core Principle

CLAUDE.md files exist for things an agent **cannot derive from the code**. If it can be found via `grep`, `find`, or reading the file — don't document it. Every line should earn its place by preventing a mistake or saving significant exploration time.

## What belongs in CLAUDE.md

### High value (always include)

- **"Use X, not Y" rules** — when the obvious approach is wrong. Example: "Use column registry, don't create inline DataGridColumn components."
- **Non-obvious gotchas** — things that compile fine but break at runtime or produce wrong behavior. Example: "`$entity.id` in a DataGrid column refers to the row entity, not a nested relation."
- **Commands that aren't in package.json** — hatch commands, multi-step workflows, CI workarounds.
- **Architecture decisions that aren't obvious from structure** — why lib-core has no React dependency, why gates are split across two packages, why the scan app aliases `@app` to admin's lib.
- **Integration patterns** — how to wire up a new feature gate (3 parts across 3 packages), how to add a path-based route, how static render field registration works.
- **Deep module enforcement** — when a shared abstraction exists (registry, context, factory), mandate its use with "always/never" language. Agents will create shallow inline alternatives if not explicitly told to use the deep module.

### Medium value (include if genuinely non-obvious)

- **Build/dev commands** — but only at the root level, and only if they're not standard (`npm run dev`).
- **Environment quirks** — dynamic ports, two-phase migrations, worktree-specific behavior.
- **Framework-specific patterns** — Contember's static/dynamic render split, Binding scope rules.

### Low value (usually omit)

- **File/directory listings** — agents can `ls` and `find`.
- **Hook/component catalogs** — agents can `grep` for exports.
- **Type definitions** — agents can read the source.
- **Things documented in the code itself** — JSDoc, inline comments, README files.
- **Generic best practices** — "use TypeScript", "write tests", "follow SOLID".

## Structure

### Root CLAUDE.md

The primary file. Contains:

- Project overview (1-2 sentences)
- Key commands (build, test, dev, deploy)
- Architecture decisions and patterns that apply project-wide
- Critical rules ("never do X")
- Non-obvious workflows (schema changes, migrations, data fixes)
- Deep module mandates — which shared abstractions agents must use

Target: under 400 lines. If longer, move domain-specific content to subdirectory files.

### Subdirectory CLAUDE.md

Narrow scope — one concern per file. Place next to the code it describes.

**Good examples:**

- `admin/app/pages/CLAUDE.md` — documents path-based route registration (one non-obvious pattern, 20 lines)
- `lib-core/src/domain/gates/CLAUDE.md` — documents the gate pattern (naming, placement rules, consumer pattern)

**Bad examples:**

- `admin/app/CLAUDE.md` that lists every hook and component directory — this is a catalog, not guidance
- `src/CLAUDE.md` that restates the root file

### When to create a subdirectory CLAUDE.md

Create one when ALL of these are true:

1. There's a non-obvious pattern specific to this directory
2. The pattern would be out of place in the root file
3. Someone working in this directory would likely make a mistake without it

## Writing rules

### Be prescriptive, not descriptive

Bad: "The column registry provides reusable DataGrid column definitions per entity."
Good: "Always check the column registry before creating inline DataGridColumn components."

Bad: "lib-core contains domain logic shared across environments."
Good: "lib-core must have zero React/DOM/Node dependencies — pure TypeScript only."

### Enforce deep modules

Bad: "We have a global variable context for sharing state."
Good: "Always use `GlobalVarContext` for cross-component state. Never create local state stores — check the context first. If no variable exists for your use case, add one to the context rather than creating a standalone store."

Bad: "Prefer using the column registry."
Good: "Always use the column registry. Never create inline DataGridColumn components. If you need a new column type, add it to the registry — don't create a one-off."

"Prefer" is too weak — agents rationalize around it. "Always/never" is the bar. And always tell agents to **extend** the deep module when their use case isn't covered yet — otherwise they'll build around it.

### Include a decision framework for new code

Bad: (nothing — agent creates whatever seems fastest)
Good: "Before creating a new utility: (1) check if an existing module covers the use case, (2) if creating new, will it have multiple callers? If yes, design the interface first. If no, a simple inline solution is fine."

### Lead with the rule, follow with the why

```
Never insert `??` fallbacks for values the schema guarantees.
Defaulting a "shouldn't be null" value silently converts a data bug into wrong UI state.
```

### Use concrete examples for gotchas

```
**Wrong:** `<Link to="projectDetail(id: $entity.id)">` inside an Activity DataGrid column — `$entity.id` is the Activity ID, not the Project ID.
**Right:** Use `useField('activityGroup.project.id')` to get the actual project ID.
```

### Keep commands copy-paste ready

```bash
hatch down && hatch setup    # Full reset when migrations are corrupted
```

Not: "Run hatch down followed by hatch setup to reset the database."

### Don't explain what the code does — explain what to watch out for

Bad:
```
## Shared Hooks
- `useCurrentUserId()` — returns the current user's content ID
- `useIsAdmin()` — checks if user has admin role
- `useDealTotals()` — calculates deal revenue
```

Good:
```
## Hooks
Use `useCurrentUserId()` (not `useIdentity()`) when you need the content User entity ID — `useIdentity()` returns the tenant person UUID which is different.
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

"Components use PascalCase." "Files are in kebab-case." If it's enforced by the linter or visible from any file in the directory, don't document it.

### The weak mandate

"Prefer using X." "Consider using Y." "You might want to check Z." Agents treat soft language as optional. Use "always/never" for things that must be followed.

## Maintenance

- Update CLAUDE.md when you discover a new gotcha during a session
- Remove entries when the underlying issue is fixed
- Review for staleness when major refactors land
- If a CLAUDE.md entry causes an agent to do the wrong thing, delete it immediately

## Quality test

For each line in a CLAUDE.md, ask: "If this line were missing, would an agent make a mistake or waste significant time?" If no, delete it.
