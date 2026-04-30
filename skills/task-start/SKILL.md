---
name: task-start
description: Use when beginning work on a NEW task that hasn't been explored yet. Assesses complexity, then routes to the right execution depth — trivial tasks get solved immediately, moderate ones are broken into steps, complex ones get a plan first. Do NOT use when the task has already been discussed, explored, or planned in the current conversation — in that case just execute directly.
metadata:
  dependencies:
    - complexity-assess
    - branch-name
---

# Task Start

Take a task from vague description to execution. Assess complexity autonomously and pick the right approach — no confirmation needed.

## Prerequisites

Pre-run on skill load — output replaces the line below:

- Current branch: !`git branch --show-current`

If on `main` or `master`, warn: "You're on main — consider creating a worktree or feature branch first." Continue anyway (don't block).

## Fast-path — Self-evidently trivial tasks

If the task is unambiguously trivial — exact file, line, and change are specified with no exploration needed (e.g. "fix the typo on line 42 of foo.py") — skip the assessment and go straight to implementation. Note: "Skipping assessment — task is self-evidently trivial." Then implement, verify, and report. This fast-path is only for tasks where complexity assessment would add no information.

## Step 1 — Understand the task

Read the user's task description. If the task references specific files, errors, or issues, note them.

## Step 2 — Explore

Explore the codebase to understand what's involved:

- Grep for terms from the task description
- Read files that are likely relevant
- Understand the current state of the code in this area

This exploration is required — you cannot score complexity accurately without it. This is the single exploration phase for the entire workflow. Later steps (complexity-assess and execution) should build on what was learned here rather than re-exploring from scratch.

## Step 3 — Assess complexity

Follow the `complexity-assess` skill to score the task across 4 dimensions (scope, clarity, risk, novelty) and determine the tier (trivial, moderate, or complex). The exploration from Step 2 has already been done — use those findings directly when scoring.

Output the assessment table as specified by the skill. Do not ask for confirmation. Announce the tier and move to execution.

## Step 4 — Name the branch

If the current branch doesn't already match `<type>/<description>` pattern (e.g. on `main`, a worktree default name, or a generic branch), follow the `branch-name` skill to name it. Since no code has been written yet, `branch-name` will use the task description from this conversation as context instead of diffs.

## Step 5 — Execute

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
