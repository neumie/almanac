---
name: implement
description: Use when implementing one ready ticket or spec slice end to end. Verifies blockers, applies TDD where useful, reviews, updates queue state, and commits.
disable-model-invocation: true
metadata:
  dependencies:
    - tdd
    - code-review
    - commit
  upstream: mattpocock/skills/skills/engineering/implement
  upstream-sha: 7a0b11f5f4fe9505ea5c7983c3083ba1bf754f69
  adapted-date: "2026-07-13"
---

# Implement

Implement exactly one supplied ticket or spec slice. The ticket is authoritative; its parent spec provides context.

## Process

### 1. Resolve the work item

Accept one of:

- Local ticket path under `docs/plans/<spec>/issues/`
- GitHub issue number or URL
- A clearly bounded spec slice supplied by the user or an orchestrator

If no single work item is identifiable, ask which ticket to implement. Do not silently take an unrelated `ready-for-agent` item.

Read the full ticket, comments, parent spec, relevant `CONTEXT.md`, and ADRs. Verify:

- Readiness is `ready-for-agent`. Accept legacy local `status: open` plus `type: AFK`, or legacy GitHub queue issues without any readiness label.
- Every declared blocker is done or closed.
- Acceptance criteria define a bounded, testable outcome.

Stop on `ready-for-human`, an incomplete blocker, or a material ambiguity that changes scope.

### 2. Explore

Inspect existing behavior, tests, and repo instructions. Find facts in the environment. Keep scope to the selected ticket.

### 3. Implement

Follow the `tdd` skill for behavior changes at pre-agreed seams. For mechanical refactors, change the full bounded blast radius, then verify with existing tests.

Run targeted typechecks and tests while working. Run all relevant feedback loops once at the end.

### 4. Review

Follow the `code-review` skill against the work item and current diff. Fix blocking findings. Do not add unrelated improvements.

### 5. Update queue state

Use the strict checkbox protocol: check only criteria demonstrably fulfilled by this change.

For a local ticket:

1. Flip fulfilled acceptance criteria from `[ ]` to `[x]`.
2. Append `- <ISO-date>: <summary> — fulfills criteria N[, M…]` under `## Progress`.
3. When every criterion is checked, set `status: done`.
4. Include the ticket update in the code commit.

For a GitHub issue:

1. Prepare the updated issue body before committing.
2. Commit the code.
3. Update fulfilled checkboxes and comment with `<sha>: <summary> — fulfills criteria N[, M…]`.
4. When every criterion is checked, close the issue and remove `ready-for-agent`.

### 6. Commit

Follow the `commit` skill. If an orchestrator supplies a stricter commit format, such as `RALPH(<spec>):`, follow the orchestrator contract instead.

Report the commit, verification run, queue update, and any remaining criteria.
