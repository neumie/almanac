---
name: task-start
description: Use when beginning work on a task. Assesses complexity, then routes to the right execution depth — trivial tasks get solved immediately, moderate ones are broken into steps, complex ones get a plan first. Use this whenever the user says start this, work on this, do this, or describes a task they want done.
metadata:
  dependencies:
    - complexity-assess
    - branch-name
---

# Task Start

Take a task from vague description to execution. Assess complexity autonomously and pick the right approach — no confirmation needed.

## Prerequisites

Verify the working context before starting:

- Check the current branch with `git branch --show-current`
- If on `main` or `master`, warn: "You're on main — consider creating a worktree or feature branch first." Continue anyway (don't block).
- If the branch doesn't have a descriptive name yet (e.g. still on a default worktree name, a generic branch, or doesn't match `<type>/<description>` pattern), name it using the `branch-name` skill. Do this after exploration (Step 2) so the name reflects the actual work.

## Step 1 — Understand the task

Read the user's task description. If the task references specific files, errors, or issues, note them.

## Step 2 — Explore

Before assessing complexity, explore the codebase to understand what's involved:

- Grep for terms from the task description
- Read files that are likely relevant
- Understand the current state of the code in this area

This exploration is required — you cannot score complexity accurately without it.

## Step 3 — Assess complexity

Follow the `complexity-assess` skill to score the task across 4 dimensions (scope, clarity, risk, novelty) and determine the tier (trivial, moderate, or complex).

Output the assessment table as specified by the skill. Do not ask for confirmation. Announce the tier and move to execution.

## Step 4 — Execute

Load and follow the reference file for the assessed tier:

- **Trivial (4-5):** `${CLAUDE_SKILL_DIR}/references/trivial-execution.md`
- **Moderate (6-8):** `${CLAUDE_SKILL_DIR}/references/moderate-execution.md`
- **Complex (9-12):** `${CLAUDE_SKILL_DIR}/references/complex-execution.md`

## Tier Upgrade

If at any point during execution you discover the task is more complex than initially assessed, stop and re-assess. Upgrade to the appropriate tier and switch to its execution reference. Announce the upgrade:

```
Upgrading from TRIVIAL to MODERATE — discovered shared validation logic that needs updating across 6 files.
```

## Rules

- Always explore before scoring — never guess from the description alone
- No confirmation gates — assess and go
- The complexity table is mandatory output — it shows your reasoning
- Prefer reading the codebase over asking the user (per interview-me pattern)
- If the task should be decomposed into separate tasks, say so and propose the split rather than tackling everything at once
