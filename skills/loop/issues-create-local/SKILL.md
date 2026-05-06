---
name: issues-create-local
description: Use when breaking a plan, spec, or PRD into local markdown task files as vertical-slice tracer bullets. No GitHub. Each slice gets its own file with status/blocked-by/type frontmatter.
---

Break a plan into local markdown task files using vertical slices (tracer bullets). Same vertical-slice discipline as `issues-create`, but writes files to `plans/issues/<prd>/` instead of calling `gh issue create`.

## When to use this vs `issues-create`

- This skill — solo work, no GitHub remote, or repos where you don't want issue noise. Slices live in-tree as markdown.
- `issues-create` — collaborative work where slices need to be grabbed from a backlog by humans/bots via GitHub.

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a PRD path or name (e.g. `auth-system`), read `plans/auth-system.md`. If there's exactly one PRD in `plans/`, use it. If none, tell the user to run `/prd-create` first.

Derive `<prd>` — the kebab-case PRD basename without `.md` (e.g. `plans/auth-system.md` → `auth-system`). All issue files for this PRD go under `plans/issues/<prd>/`.

### 2. Explore the codebase (optional)

`CONTEXT.md` runs automatically when the skill loads — output replaces the line below:

- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`

If content is present, reuse its vocabulary in slice titles and descriptions. If you have not already explored the codebase, do so now to ground the slices in real modules.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be **HITL** or **AFK**:
- **HITL** — requires human interaction (architectural decision, design review)
- **AFK** — can be implemented and merged without human interaction

Prefer AFK over HITL where possible.

**Vertical slice rules:**
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked HITL / AFK?

Iterate until the user approves the breakdown.

### 5. Write the markdown files

For each approved slice, write one file to `plans/issues/<prd>/NN-<slug>.md`.

- `NN` — two-digit zero-padded ordinal in dependency order (blockers first): `01`, `02`, …
- `<slug>` — kebab-case version of the title (lowercase, hyphens, no punctuation), e.g. `add-login-form`

```bash
mkdir -p plans/issues/<prd>
```

Use the file template below. Reference blockers by their filename basename (e.g. `01-add-login-form`) — that survives renames inside this directory better than absolute paths.

```markdown
---
title: <Short descriptive title>
status: open
type: AFK            # or HITL
blocked-by: []       # or [01-add-login-form, 02-add-session-store]
user-stories: []     # or [1, 4, 7] — story numbers from the PRD
---

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Notes

Any context, references, or open questions for the implementer.
```

### 6. Report

Print the list of files written, with paths relative to the repo root, e.g.:

```
Wrote 5 slices to plans/issues/auth-system/:
  01-add-login-form.md          (AFK)
  02-add-session-store.md       (AFK, blocked-by: 01)
  03-protect-dashboard-route.md (AFK, blocked-by: 02)
  04-logout-button.md           (AFK, blocked-by: 02)
  05-session-expiry-design.md   (HITL)
```

Then point the user at `/ralph-loop <prd>` to start working through them. Ralph reads the PRD directly today; the local issue files serve as a manual checklist and as a place to mark slices `status: done` as you go.

## Status updates

When a slice is finished, edit its frontmatter `status: open` → `status: done`. To list remaining work:

```bash
grep -L "status: done" plans/issues/<prd>/*.md
```
