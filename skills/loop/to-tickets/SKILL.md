---
name: to-tickets
description: Use when breaking a plan, spec, or conversation into tracer-bullet tickets for GitHub or docs/plans, with blocking edges and agent/human readiness.
disable-model-invocation: true
metadata:
  upstream: mattpocock/skills/skills/engineering/to-tickets
  upstream-sha: 23140c577f71c98993523f0dbec74f250561b708
  adapted-date: "2026-07-13"
---

# To Tickets

Break a plan, spec, or conversation into independently grabbable tracer-bullet tickets. Each ticket declares its blocking edges and whether an agent or human should take it.

## Process

### 1. Gather context

Use existing conversation context. If the user passes a spec path, issue number, or URL, read its full body and comments.

Determine `<spec>` from `docs/plans/<spec>/spec.md`, falling back to legacy `prd.md`. If multiple specs could apply, ask which one.

Determine the tracker:

- Honor an explicit `local` or `github` argument.
- Otherwise use a destination already chosen in the conversation.
- Otherwise ask one question: GitHub tickets or local files?

Both modes keep the spec and supporting artifacts under `docs/plans/<spec>/`. Local mode also stores tickets there.

### 2. Explore the codebase

Explore enough code to ground ticket boundaries in real behavior and modules. Reuse `CONTEXT.md` vocabulary and respect relevant ADRs. Find facts in the environment instead of asking the user.

Look for prefactoring that makes the requested change easier. Make the change easy, then make the easy change.

### 3. Draft vertical slices

Draft thin, complete tracer bullets:

- Cut through every required layer instead of splitting by layer.
- Make each ticket independently demoable or verifiable.
- Size each ticket for one fresh context window.
- Declare every genuine blocking edge.
- Prefer many thin tickets over few thick tickets.

Use readiness vocabulary instead of HITL/AFK:

- `ready-for-agent` — implementable without another human decision. `/implement` or `ralph-loop` may take it.
- `ready-for-human` — requires a decision, design review, access, or another human-only action.

Wide mechanical refactors are the exception. Sequence them as expand, bounded migration batches, then contract. Keep each intermediate state green; declare the real blocking edges.

### 4. Confirm the breakdown

Present a numbered list. For each ticket show:

- **Title**
- **Ready for**: agent or human
- **Blocked by**
- **What it delivers**

Ask whether granularity, readiness, and blocking edges are correct. Iterate until approved. Do not publish before approval.

### 5. Publish

Publish blockers first so later tickets can reference stable identifiers.

#### Local files

Write one file per ticket to `docs/plans/<spec>/issues/NN-<slug>.md`:

```markdown
---
title: <Short title>
status: ready-for-agent # or ready-for-human
blocked-by: []         # or [01-first-ticket]
user-stories: []       # story numbers from the spec when applicable
---

## What to build

The end-to-end behavior this ticket delivers.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Notes

Context, references, or constraints needed by the implementer.
```

Reference blockers by filename basename. Existing legacy files using `status: open` plus `type: AFK|HITL` remain valid; do not rewrite them unless already editing that ticket.

#### GitHub issues

Ensure these labels exist:

```bash
gh label create "ralph(<spec>)" --color FBCA04 --description "Ralph loop task queue" 2>/dev/null || true
gh label create "ready-for-agent" --color 0E8A16 --description "Ready for autonomous implementation" 2>/dev/null || true
gh label create "ready-for-human" --color D93F0B --description "Needs human decision or action" 2>/dev/null || true
```

Create one issue per ticket with both:

- `ralph(<spec>)` — queue identity
- `ready-for-agent` or `ready-for-human` — executor eligibility

Use `gh issue create --label "ralph(<spec>)" --label "<readiness>"`, passing the approved title and body.

Use this body:

```markdown
## Spec

`docs/plans/<spec>/spec.md`

## Parent

#<parent-number> (omit when no parent issue exists)

## What to build

The end-to-end behavior this ticket delivers.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- Blocked by #<issue-number>

Or: None — can start immediately.
```

Do not close or modify a parent issue. Avoid file-level implementation instructions unless a prototype snippet encodes a decision more precisely than prose.

### 6. Report

List created files or issue URLs, readiness, and blockers. Point to `/implement <ticket>` for one agent-ready ticket or `/ralph-loop <spec>` for the autonomous queue.
