---
name: grill-me
description: Use when stress-testing a plan, design, or architecture through relentless questioning. Walks each branch of the decision tree, writes crystallized decisions to docs/plans/<name>/brief.md.
disable-model-invocation: true
metadata:
  upstream: mattpocock/skills/skills/productivity/grill-me
  upstream-sha: bd04394c675ee54173a093c50eb74da01a2940fa
  adapted-date: "2026-05-25"
---

# Grill Me

Interview the user relentlessly about every aspect of their plan until reaching shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

## Setup

Pre-run on skill load — output replaces the line below:

- Current branch: !`git branch --show-current 2>/dev/null || true`

### Context detection (do this first, before anything else)

Determine the feature `<name>` for this session:

1. **If the skill was invoked with an argument** (e.g. `/grill-me auth-system`), use that as `<name>`.
2. **Otherwise**, take the branch name from the pre-run above and strip a leading type prefix if present — `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, `ci/`, `perf/`. Whatever remains is `<name>`. Example: `feat/auth-system` → `auth-system`, `dashboard-redesign` → `dashboard-redesign`.
3. **If the branch is `main`, `master`, or `develop`** (or empty after stripping), there is no usable name. Tell the user:

   ```
   No feature name available. Either pass an explicit name (e.g. /grill-me auth-system) or check out a feature branch first.
   ```

   Then stop. Do not proceed.

Once `<name>` is known, run this command to load any existing brief:

```bash
cat docs/plans/<name>/brief.md 2>/dev/null || true
```

If content is present, you're continuing a previous grilling session — acknowledge what's already decided and pick up from open questions. If empty (file missing or empty), this is a fresh session.

Create the directory before the first write:

```bash
mkdir -p docs/plans/<name>
```

## Rules

- For each question, provide your recommended answer
- If a question can be answered by exploring the codebase, explore the codebase instead of asking
- Don't accept vague answers — push for specifics
- Track which branches of the decision tree are resolved vs. open
- Ask one question at a time, wait for the answer before continuing

## Writing the Brief

After each decision is resolved, update `docs/plans/<name>/brief.md` immediately. Don't batch — capture as you go.

Use the format in `~/.claude/skills/almanac/grill-me/references/brief-format.md`.

## Finishing

When all branches are resolved (no open questions remain), update `docs/plans/<name>/brief.md` one final time and tell the user:

```
Grilling complete. Brief saved to docs/plans/<name>/brief.md.
Next step: /prd-create
```
