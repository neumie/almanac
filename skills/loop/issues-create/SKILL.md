---
name: issues-create
description: Use when breaking a plan, spec, or PRD into independently-grabbable GitHub issues as vertical-slice tracer bullets. Each issue is a thin end-to-end slice verified on its own.
disable-model-invocation: true
metadata:
  upstream: mattpocock/skills/skills/engineering/to-tickets
  upstream-sha: dceaa730875d60a8edc51f90f1c7d885e8535c95
  adapted-date: "2026-07-10"
---

Break a plan, spec, or conversation into independently-grabbable GitHub issues — tracer-bullet vertical slices, each declaring the issues that **block** it. An issue with no blockers can start immediately.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference as an argument, fetch it: `gh issue view <number>` (with comments) for an issue number or URL, read the file for a spec path.

### 2. Explore the codebase (optional)

`CONTEXT.md` runs automatically when the skill loads — output replaces the line below:

- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`

If content is present above, use its vocabulary in issue titles and descriptions. If you have not already explored the codebase, do so to understand the current state of the code.

Respect ADRs in the area you're touching. Look for opportunities to prefactor the code to make implementation easier: make the change easy, then make the easy change.

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

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own issue blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in an issue blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify issue — green is promised only there.

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
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Create the GitHub issues

Pick a queue label of the form `ralph(<short-name>)` (e.g. `ralph(auth-system)`). This label is what `ralph-loop` uses to find issues belonging to this work — without it, the loop can't see the queue. Create the label once if it doesn't exist:

```bash
gh label create "ralph(<short-name>)" --color FBCA04 --description "Ralph loop task queue" 2>/dev/null || true
```

For each approved slice, create a GitHub issue using `gh issue create --label "ralph(<short-name>)"`. Use the issue body template below.

Create issues in dependency order (blockers first) so you can reference real issue numbers in the "Blocked by" field.

```markdown
## Parent

#<parent-issue-number> (if the source was a GitHub issue, otherwise omit)

## What to build

The end-to-end behavior this slice makes work, from the user's perspective — not layer-by-layer implementation.

Avoid specific file paths or code snippets -- they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline only the decision-rich parts and note that it came from a prototype.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- Blocked by #<issue-number> (one line per blocking issue)

Or "None — can start immediately" if no blockers.
```

Do NOT close or modify any parent issue.

The issues form a **frontier**: any issue whose blockers are all done is grabbable. `ralph-loop` works the frontier one issue at a time with a fresh context per issue.
