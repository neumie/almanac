#!/bin/bash
set -euo pipefail

# ALMANAC_HOME bootstrap — prefer an exported value, else self-resolve
# symlink-safe (pwd -P) at this file's known depth. Mirrors almanac_resolve_home
# in lib/core.sh; keep the two in sync.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)}"

# prompt.sh's only engine dependency is feedback detection
# (almanac_loop_feedback_markdown), so source lib/feedback.sh directly rather
# than the whole loop engine.
if [ ! -f "$ALMANAC_HOME/lib/feedback.sh" ]; then
  echo "Error: lib/feedback.sh not found at $ALMANAC_HOME/lib/feedback.sh" >&2
  exit 1
fi

source "$ALMANAC_HOME/lib/feedback.sh"

usage() {
  cat <<'EOF'
Usage: prompt.sh <spec-name>
Example: prompt.sh auth-system
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

SPEC_NAME="${1:-}"
[ -n "$SPEC_NAME" ] || {
  usage >&2
  exit 1
}

case "$SPEC_NAME" in
  *[!A-Za-z0-9._-]*)
    echo "Error: spec name may only contain letters, numbers, dot, underscore, and hyphen." >&2
    exit 1
    ;;
esac

PROJECT_ROOT="${LOOP_PROJECT_ROOT:-$PWD}"
# Prefer spec.md; fall back to legacy prd.md so old plan dirs keep working.
SPEC_FILE="docs/plans/${SPEC_NAME}/spec.md"
[ -f "$PROJECT_ROOT/$SPEC_FILE" ] || SPEC_FILE="docs/plans/${SPEC_NAME}/prd.md"
PROMPT_FILE="$PROJECT_ROOT/docs/plans/${SPEC_NAME}/prompt.md"

if [ ! -f "$PROJECT_ROOT/$SPEC_FILE" ]; then
  echo "Error: docs/plans/${SPEC_NAME}/spec.md not found (no legacy prd.md either). Run /spec-create first." >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/docs/plans/${SPEC_NAME}"

render_intro() {
  cat <<'EOF' | sed -e "s|{{SPEC_FILE}}|$SPEC_FILE|g" -e "s|{{SPEC_NAME}}|$SPEC_NAME|g"
# INPUTS

Pull @{{SPEC_FILE}} into your context.

You've been passed the last 10 LOOP commits (SHA, date, full message). Review these to understand what work has been done.

# TASK QUEUE

Before decomposing the spec, check whether an explicit queue exists. Detect in this order:

1. **Local ticket files.** If `docs/plans/{{SPEC_NAME}}/issues/` contains `*.md` files, that directory is your queue. New tickets use `status: ready-for-agent|ready-for-human`; legacy tickets use `status: open` plus `type: AFK|HITL`.
2. **GitHub issues.** Else if `gh issue list --search 'label:"loop({{SPEC_NAME}})" state:open'` returns at least one issue, that's your queue. (Use `--search`, not `--label` — the parenthesised label name breaks the `--label` filter.) New agent tickets also carry `ready-for-agent`; legacy tickets may have no readiness label.
3. **No queue.** Skip to TASK BREAKDOWN below and decompose the spec yourself.

If a queue is present:

- Pick the **lowest-numbered** agent-ready local ticket (or **oldest** agent-ready GitHub issue) whose blockers are all done or closed. Treat legacy `status: open` + `type: AFK` files and legacy GitHub queue issues without any readiness label as agent-ready. Never pick `ready-for-human` or legacy `type: HITL`.
- Its `## What to build` and `## Acceptance criteria` define your scope. The spec is reference; the slice/issue is authoritative.
- Do NOT decompose the spec again — TASK BREAKDOWN below is for the no-queue case only.
- If every queued task is blocked by something incomplete, output `<promise>ABORT</promise>`.

# TASK BREAKDOWN

(Run this section ONLY if TASK QUEUE found no queue. Otherwise the slice/issue you picked IS your task; skip ahead to EXPLORATION.)

Break down the spec into tasks.

Pick the smallest unit of work that pins one meaningful behavior. Don't outrun your headlights — but don't underrun them either.

- **Behavior changes** (new features, schema, business logic): one task = one behavior, written test-first.
- **Mechanical refactors** (renames, threading a parameter through callers, search-and-replace across many files): the whole refactor is ONE task. Batch all related edits across all affected files into a single commit. The existing test suite is the verification — don't split a rename into one commit per call site.

If you can't articulate a behavior the task pins, you're mid-refactor — bundle it.

# TASK SELECTION

If TASK QUEUE found a task, that's your task. Otherwise pick the next task from your TASK BREAKDOWN that hasn't been completed (check LOOP commits for completed work).

If all tasks are complete, output <promise>COMPLETE</promise>.

# EXPLORATION

Explore the repo and fill your context window with relevant information that will allow you to complete the task.

# EXECUTION

Follow the `implement` skill for this one selected task: verify readiness and blockers, implement at the agreed seam, run feedback loops, review the diff, and update queue state. The selected task is already resolved — do not choose another ticket.

# FEEDBACK LOOPS

Before committing, run ALL feedback loops. Fix any failures before proceeding.

EOF
}

render_tail() {
  cat <<'EOF' | sed -e "s|{{SPEC_NAME}}|$SPEC_NAME|g"

# COMMIT

Follow the `implement` skill's strict checkbox and queue-update protocol. Then make the git commit. The commit message must:

1. Start with `LOOP({{SPEC_NAME}}):` prefix
2. Include task completed + spec reference
3. Key decisions made
4. Files changed
5. Blockers or notes for next iteration

Keep it concise but informative for the next iteration.

# REPORT

After committing, append a self-report to `docs/plans/{{SPEC_NAME}}/agent-reports.log`. The overseer reads recent reports each tick and may emit steering directives based on what you flag. Be honest — concerns and uncertainties are more useful than reassurance.

Append exactly this block (replace `<HEAD-sha>` with the SHA of the commit you just made, e.g. `git rev-parse HEAD`):

```
===== sha=<HEAD-sha> ts=<ISO-8601-timestamp> =====
## concerns
- <anything about the code, tests, or approach that feels off; or "(none)">
## errors
- <runtime errors, test failures, lint issues, or retries you hit; or "(none)">
## uncertainties
- <spec ambiguities, missing context, or assumptions you made and want validated; or "(none)">
```

If the iteration was a CI fix or a steered iteration, mention that in concerns so the overseer has context.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
EOF
}

{
  render_intro
  almanac_loop_feedback_markdown "$PROJECT_ROOT"
  render_tail
} > "$PROMPT_FILE"

echo "Generated $PROMPT_FILE"
