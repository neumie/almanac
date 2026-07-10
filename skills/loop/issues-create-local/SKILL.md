---
name: issues-create-local
description: Use when breaking a plan, spec, or PRD into local markdown task files as vertical-slice tracer bullets. No GitHub. Each slice gets its own file with status/blocked-by/type frontmatter.
---

Break a plan into local markdown task files using vertical slices (tracer bullets). Same vertical-slice discipline as `issues-create`, but writes files to `docs/plans/<prd>/issues/` instead of calling `gh issue create`.

## When to use this vs `issues-create`

- This skill — solo work, no GitHub remote, or repos where you don't want issue noise. Slices live in-tree as markdown.
- `issues-create` — collaborative work where slices need to be grabbed from a backlog by humans/bots via GitHub.

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a PRD name (e.g. `auth-system`), read `docs/plans/auth-system/prd.md`. Otherwise scan `docs/plans/` for feature directories that contain `prd.md`:

```bash
for d in docs/plans/*/; do [ -f "$d/prd.md" ] && echo "$d"; done
```

If exactly one directory has a `prd.md`, use it. If none, tell the user to run `/prd-create` first. If multiple, ask which.

Derive `<prd>` from the directory name (e.g. `docs/plans/auth-system/prd.md` → `auth-system`). All issue files for this PRD go under `docs/plans/<prd>/issues/`.

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
- Each slice is sized to fit in a single fresh context window
- Prefer many thin slices over few thick ones

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own slice blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a slice blocked by every migrate batch.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **What it delivers**: the end-to-end behavior this slice makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each slice only depend on slices that genuinely gate it?
- Should any slices be merged or split further?
- Are the correct slices marked HITL / AFK?

Iterate until the user approves the breakdown.

### 5. Write the markdown files

For each approved slice, write one file to `docs/plans/<prd>/issues/NN-<slug>.md`.

- `NN` — two-digit zero-padded ordinal in dependency order (blockers first): `01`, `02`, …
- `<slug>` — kebab-case version of the title (lowercase, hyphens, no punctuation), e.g. `add-login-form`

```bash
mkdir -p docs/plans/<prd>/issues
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

The end-to-end behavior this slice makes work, from the user's perspective — not layer-by-layer implementation.

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
Wrote 5 slices to docs/plans/auth-system/issues/:
  01-add-login-form.md          (AFK)
  02-add-session-store.md       (AFK, blocked-by: 01)
  03-protect-dashboard-route.md (AFK, blocked-by: 02)
  04-logout-button.md           (AFK, blocked-by: 02)
  05-session-expiry-design.md   (HITL)
```

Then point the user at `/ralph-loop <prd>` to start working through them. ralph-loop reads these files as its task queue: it picks the lowest-numbered open slice whose blockers are all `status: done`, uses the slice's acceptance criteria as the task spec, flips checkboxes commit-by-commit (strict — only criteria fulfilled by that commit), and flips `status: open → done` automatically when the last `- [ ]` becomes `- [x]`. The overseer audits each flip against the diff and rolls back overclaims.

## Status updates

ralph-loop iterations maintain `status` and acceptance-criteria checkboxes automatically under the strict checkbox protocol — no manual flips needed during AFK runs. The overseer reconciles overclaims and stale checkboxes on its tick. To list remaining work at a glance:

```bash
grep -L "status: done" docs/plans/<prd>/issues/*.md
```
