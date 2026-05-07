---
name: ralph-loop
description: "Use when autonomously implementing a PRD task-by-task. Each loop iteration picks one task, TDDs it, commits, exits. Progress persists in git. Triggers: ralph, AFK mode, autonomous loop."
disable-model-invocation: true
metadata:
  upstream: mattpocock/ralph-workshop-repo-001
  adapted-date: "2026-04-28"
---

# Ralph Loop

Autonomous implementation loop. Each iteration gets fresh context, picks one task from the PRD, implements it, runs feedback loops, commits, and exits. Progress lives in git history, not conversation memory.

## Setup

These commands run automatically when the skill loads — output replaces each line below:

- Available PRDs: !`ls plans/*.md 2>/dev/null | grep -v prompt | grep -v brief || true`
- Project files: !`ls package.json Makefile Cargo.toml go.mod pyproject.toml setup.py 2>/dev/null || true`
- Tests directory: !`ls tests/ 2>/dev/null || true`

### 1. Select a PRD

From the PRD list:

- If the user passed a name (e.g. `/ralph-loop auth-system`), use `plans/auth-system.md`
- If there's exactly one PRD, use it
- If there are multiple, ask the user which one to use
- If there are none, tell the user to run `/prd-create` first

Store the selected PRD path as `PRD_FILE` for use in the prompt template.

### 2. Detect feedback loops

Map the detected project files to feedback commands:

- `package.json` → `npm run test`, `npm run typecheck`, `npm run lint`
- `Makefile` → `make test`, `make check`
- `Cargo.toml` → `cargo test`, `cargo check`
- `go.mod` → `go test ./...`, `go vet ./...`
- `pyproject.toml` / `setup.py` → `pytest`, `mypy`
- `tests/` directory in this repo → `bash tests/test-skills.sh`, `bash tests/test-structure.sh`

Build the feedback loop commands list from what's actually available.

### 3. Create the plans directory

```bash
mkdir -p plans
```

### 4. Generate the prompt

Write `plans/prompt-<name>.md` (e.g. `plans/prompt-auth-system.md`) using the template below, filling in the detected feedback loops and the PRD path:

```markdown
# INPUTS

Pull @{{PRD_FILE}} into your context.

You've been passed the last 10 RALPH commits (SHA, date, full message). Review these to understand what work has been done.

# TASK BREAKDOWN

Break down the PRD into tasks.

Pick the smallest unit of work that pins one meaningful behavior. Don't outrun your headlights — but don't underrun them either.

- **Behavior changes** (new features, schema, business logic): one task = one behavior, written test-first.
- **Mechanical refactors** (renames, threading a parameter through callers, search-and-replace across many files): the whole refactor is ONE task. Batch all related edits across all affected files into a single commit. The existing test suite is the verification — don't split a rename into one commit per call site.

If you can't articulate a behavior the task pins, you're mid-refactor — bundle it.

# TASK SELECTION

Pick the next task that hasn't been completed (check RALPH commits for completed work).

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

{{FEEDBACK_COMMANDS}}

# COMMIT

Make a git commit. The commit message must:

1. Start with `RALPH(<name>):` prefix (e.g. `RALPH(auth-system):`)
2. Include task completed + PRD reference
3. Key decisions made
4. Files changed
5. Blockers or notes for next iteration

Keep it concise but informative for the next iteration.

# REPORT

After committing, append a self-report to `plans/agent-reports-<name>.log`. The observer reads recent reports each tick and may emit steering directives based on what you flag. Be honest — concerns and uncertainties are more useful than reassurance.

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

If the iteration was a CI fix or a steered iteration, mention that in concerns so the observer has context.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
```

Replace `{{FEEDBACK_COMMANDS}}` with the detected commands as a markdown list, e.g.:
```markdown
- `npm run test` to run the tests
- `npm run typecheck` to run the type checker
```

### 5. Tell the user how to run it

Print:

```
Ralph loop ready for <name>.

  Single iteration (HITL):
    bash {{SKILL_SCRIPTS}}/once.sh <name>

  Autonomous (AFK):
    bash {{SKILL_SCRIPTS}}/afk.sh <name> <iterations>

  Example — run 10 iterations:
    bash {{SKILL_SCRIPTS}}/afk.sh auth-system 10
```

Where `{{SKILL_SCRIPTS}}` is the absolute path to this skill's scripts. Resolve in this order:

1. `~/.claude/skills/almanac/ralph-loop/scripts` — set by `almanac install claude-code` (recommended; works on any provider that installs via the `~/.claude/skills/` directory symlink).
2. `${CLAUDE_SKILL_DIR}/scripts` — fallback if the host agent populates `CLAUDE_SKILL_DIR` from the resolved skill directory.
3. `$ALMANAC_HOME/skills/ralph-loop/scripts` — fallback when invoked outside an installed Claude Code provider.

Print the literal `~/.claude/skills/almanac/ralph-loop/scripts/...` paths in the user-facing instructions so they work regardless of how the host agent resolves `${CLAUDE_SKILL_DIR}`.

## Modes

### AFK Mode (`afk.sh`)

Fully autonomous. Runs N iterations, each in a fresh Claude context. Stops when:
- All tasks complete (`<promise>COMPLETE</promise>`)
- A task is blocked (`<promise>ABORT</promise>`)
- Iteration limit reached
- `.ralph-stop` file exists in the working directory (graceful stop — see below)
- Observer detects HIGH drift (writes `.ralph-stop` automatically — see Observer below)

**Model override:** set `RALPH_MODEL` (e.g. `RALPH_MODEL=claude-opus-4-7 bash afk.sh <name> 10`); unset uses Claude Code's default.

**Auto-push:** the observer pushes any unpushed RALPH commits to `origin` at the start of each tick (default 15 min, configurable via `RALPH_OBSERVE_INTERVAL`). This batches commits so CI runs at observer cadence rather than per-iteration — avoids clogging CI when iterations are minutes apart. End-of-loop also pushes as a safety net. Sets upstream automatically on first push.

**Observer:** a parallel process wakes every `RALPH_OBSERVE_INTERVAL` seconds (default 900 = 15 min) and runs a sequential tick:

1. **Push** (shell). Pushes any local commits ahead of upstream. Logs to `plans/observer-<name>.log`.

2. **Wait for CI** (shell, only if step 1 actually pushed). Polls `gh run list` every `RALPH_CI_POLL_INTERVAL` seconds (default 30) for the run matching the pushed `headSha`, blocking until status leaves `in_progress|queued|waiting|requested|pending`. Times out after `RALPH_CI_WAIT_TIMEOUT` seconds (default 1800 = 30 min). Exits early on `.ralph-stop`. While the observer waits, main-loop iterations keep running — only the observer thread is blocked.

3. **CI verdict** (shell, no Claude call). Reads `gh run list --limit 1`. On `conclusion=failure|cancelled|timed_out|action_required|startup_failure`, writes `.ralph-ci-failed` (run URL, ID, workflow name, branch, timestamp). On `conclusion=success`, clears the marker. Also runs once at script start to pick up pre-existing failures from prior sessions or manual pushes.

4. **Drift review** (Claude call). Reviews recent `RALPH(<name>)` commits **and the tail of `plans/agent-reports-<name>.log`** (last ~8KB of agent self-reports — concerns, errors, uncertainties) against the PRD. Detects repeated tasks, off-PRD work, ABORT loops, vague commits, scope creep, test rot, recurring concerns the agents aren't solving on their own, etc. Outputs `DRIFT_LEVEL: low|medium|high`, `REASON: …`, `STEER: …`. On HIGH drift writes `.ralph-stop`. When `STEER` is non-`none`, writes the directive to `.ralph-steer`.

Effective drift-review cadence is `RALPH_OBSERVE_INTERVAL + (CI duration if pushed)`. Steps 2-3 silently no-op if `gh` is missing, the repo has no remote, or no run materialized for the pushed SHA.

Disable the whole observer with `RALPH_NO_OBSERVE=1` — that also disables observer-cadence push, CI wait, CI monitoring, and steer; only the end-of-loop push remains.

**Iteration prompt prefixes:** at the start of each iteration, `afk.sh` may prepend up to two directives to the iteration prompt:

- **Fix-CI** — when `.ralph-ci-failed` exists. The spawned agent is told to skip new task work, read the marker, fetch logs via `gh run view`, repair, and commit with `RALPH(<name>): fix CI — …`. Persistent: cleared automatically by the next observer tick once CI is green again.
- **Observer steer** — when `.ralph-steer` exists. The spawned agent is told the observer reviewed recent reports + commits and emitted concrete advice (wrong assumption, scope correction, alternate approach, etc.). One-shot: `afk.sh` removes the file after consumption. The observer can re-emit it next tick if the underlying issue persists.

Both can stack — a steered fix-CI iteration is valid.

**Agent self-reports:** the iteration prompt template instructs the spawned agent to append a structured block to `plans/agent-reports-<name>.log` after committing — `concerns`, `errors`, `uncertainties` per iteration. This is the primary signal the observer uses to decide whether to issue a steer beyond what the commits alone reveal. Agents are told to be honest — flagged uncertainties are more useful than reassurance.

### HITL Mode (`once.sh`)

Single iteration with human in the loop. Runs one pass — you review the result before continuing. Good for:
- First iteration (sanity check)
- After an ABORT (diagnose and unblock)
- When you want to steer

## Monitoring

While AFK mode runs, you can watch progress:

```bash
git log --grep="RALPH(auth-system)" --oneline
```

Each `RALPH(<name>):` commit message contains what was done and notes for the next iteration. The name prefix means multiple PRDs can run against the same repo without confusing each other's progress.

## When to stop

- All tasks done → loop exits with "Ralph complete" + auto-push.
- Something's wrong → loop exits with "Ralph aborted" + auto-push.
- Graceful stop mid-run → `touch .ralph-stop` in the working directory. The loop exits at the start of the next iteration, pushes commits, removes the file. Use this instead of Ctrl+C — Ctrl+C skips the auto-push and may leave RALPH commits stranded locally.
- You see bad commits → Ctrl+C, review, and `git push` manually if you want to keep them.
- Context is confused → kill it, fix the issue, restart (fresh context = fresh start).
