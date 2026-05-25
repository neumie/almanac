# INPUTS

Pull @docs/plans/loop-engine-split/prd.md into your context.

You've been passed the last 10 RALPH commits (SHA, date, full message). Review these to understand what work has been done.

# CONSTRAINTS

- **Preserve the snapshot-exec guard.** `afk.sh` and `once.sh` begin with a `RALPH_SNAPSHOT` re-exec block — it is what lets this refactor run safely against its own runner. NEVER remove, reorder, or break it: it must stay the first executable block, and `SCRIPT_DIR` must keep resolving via `RALPH_REAL_DIR`. If your slice edits these files, keep the guard intact.
- **Behavior-preserving refactor.** Do not change the surface behavior of `almanac ralph`, `almanac harden`, or the hub. The full test suite is the proof; if you can't keep every suite green, the slice is not done.
- Read `CONTEXT.md` for the canonical vocabulary (provider/loop adapters, deep invocation, the module map) before touching the engine.

# TASK QUEUE

Before decomposing the PRD, check whether an explicit queue exists. Detect in this order:

1. **Local slice files.** If `docs/plans/loop-engine-split/issues/` contains `*.md` files, that directory is your queue. Each file has frontmatter (`status`, `blocked-by`, `type`) and an `## Acceptance criteria` checklist of `- [ ]` items.
2. **GitHub issues.** Else if `gh issue list --search 'label:"ralph(loop-engine-split)" state:open'` returns at least one issue, that's your queue. (Use `--search`, not `--label` — the parenthesised label name breaks the `--label` filter.) Each issue body contains an `## Acceptance criteria` section with `- [ ]` items.
3. **No queue.** Skip to TASK BREAKDOWN below and decompose the PRD yourself.

If a queue is present:

- Pick the **lowest-numbered** open slice file (or **oldest** open issue) whose `blocked-by` references are all `status: done` (or closed). That slice/issue is your task.
- Its `## What to build` and `## Acceptance criteria` define your scope. The PRD is reference; the slice/issue is the spec.
- Do NOT decompose the PRD again — TASK BREAKDOWN below is for the no-queue case only.
- If every queued task is blocked by something incomplete, output `<promise>ABORT</promise>`.

# TASK BREAKDOWN

(Run this section ONLY if TASK QUEUE found no queue. Otherwise the slice/issue you picked IS your task; skip ahead to EXPLORATION.)

Break down the PRD into tasks.

Pick the smallest unit of work that pins one meaningful behavior. Don't outrun your headlights — but don't underrun them either.

- **Behavior changes** (new features, schema, business logic): one task = one behavior, written test-first.
- **Mechanical refactors** (renames, threading a parameter through callers, search-and-replace across many files): the whole refactor is ONE task. Batch all related edits across all affected files into a single commit. The existing test suite is the verification — don't split a rename into one commit per call site.

If you can't articulate a behavior the task pins, you're mid-refactor — bundle it.

# TASK SELECTION

If TASK QUEUE found a task, that's your task. Otherwise pick the next task from your TASK BREAKDOWN that hasn't been completed (check RALPH commits for completed work).

If all tasks are complete, output <promise>COMPLETE</promise>.

# EXPLORATION

Explore the repo and fill your context window with relevant information that will allow you to complete the task.

# EXECUTION

Complete the task.

For behavior changes, use TDD:
1. Write one failing test for the behavior
2. Write minimal code to pass
3. Refactor if needed
4. Repeat for the next behavior within this task

For mechanical refactors, skip TDD: make the change across all affected files in one pass, then run the feedback loops. Existing tests verify correctness; don't write new ones to pin the refactor itself.

# FEEDBACK LOOPS

Before committing, run ALL feedback loops. Fix any failures before proceeding.

- `for t in tests/test-*.sh; do echo "== $(basename "$t") =="; bash "$t" || exit 1; done` — run the **FULL** test suite; **every** suite must pass. This is a behavior-preserving refactor, so the existing suites (especially `test-ralph-smoke`, `test-loop-core`, `test-hub`, `test-harden-cli`) are the safety net for every slice. A slice that can't keep them all green is not done.
- After any change to a script's behavior, also confirm `bash -n` parses every edited `.sh` file.

# COMMIT

If you used a queued task, update the queue using the **strict checkbox protocol** before committing.

**Strict means:** flip a `- [ ]` to `- [x]` ONLY for an acceptance criterion that THIS commit's actual code changes demonstrably fulfill. Do not flip a checkbox for something "almost", "implicitly", or "previously" done. The overseer audits these flips against the diff and rolls back overclaims.

**Local slice file:**

1. Edit the slice file: flip `- [ ]` -> `- [x]` for each criterion this commit fulfills.
2. Append a line under `## Progress` (create the section if it doesn't exist): `- <ISO-date>: <one-line summary> - fulfills criteria N[, M...]`.
3. If every `- [ ]` in `## Acceptance criteria` is now `- [x]`, also flip frontmatter `status: open` -> `status: done`.
4. Stage the slice-file edits as part of this commit.

**GitHub issue:**

1. Fetch current body: `gh issue view <num> --json body -q .body > /tmp/issue-body.md`.
2. Edit `/tmp/issue-body.md` to flip the relevant `- [ ]` -> `- [x]`.
3. After committing the code, push the body update: `gh issue edit <num> --body-file /tmp/issue-body.md`.
4. Post a comment with the commit SHA: `gh issue comment <num> --body "<sha>: <summary> - fulfills criteria N[, M...]"`.
5. If every checkbox is now `- [x]`, also `gh issue close <num>`.

Then make the git commit. The commit message must:

1. Start with `RALPH(loop-engine-split):` prefix
2. Include task completed + PRD reference
3. Key decisions made
4. Files changed
5. Blockers or notes for next iteration

Keep it concise but informative for the next iteration.

# REPORT

After committing, append a self-report to `docs/plans/loop-engine-split/agent-reports.log`. The overseer reads recent reports each tick and may emit steering directives based on what you flag. Be honest — concerns and uncertainties are more useful than reassurance.

Append exactly this block (replace `<HEAD-sha>` with the SHA of the commit you just made, e.g. `git rev-parse HEAD`):

```
===== sha=<HEAD-sha> ts=<ISO-8601-timestamp> =====
## concerns
- <anything about the code, tests, or approach that feels off; or "(none)">
## errors
- <runtime errors, test failures, lint issues, or retries you hit; or "(none)">
## uncertainties
- <PRD ambiguities, missing context, or assumptions you made and want validated; or "(none)">
```

If the iteration was a CI fix or a steered iteration, mention that in concerns so the overseer has context.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
