---
name: ralph-loop
description: Use when autonomously implementing a PRD task-by-task. Each loop iteration picks one task, TDDs it, commits, exits. Progress persists in git. Triggers: ralph, AFK mode, autonomous loop.
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

Make each task the smallest possible unit of work. We don't want to outrun our headlights. Aim for one small change per task.

# TASK SELECTION

Pick the next task that hasn't been completed (check RALPH commits for completed work).

If all tasks are complete, output <promise>COMPLETE</promise>.

# EXPLORATION

Explore the repo and fill your context window with relevant information that will allow you to complete the task.

# EXECUTION

Complete the task using test-driven development:
1. Write one failing test for the behavior
2. Write minimal code to pass
3. Refactor if needed
4. Repeat for the next behavior within this task

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

**Auto-push:** when the loop ends (any reason above), accumulated `RALPH(<name>)` commits are pushed to `origin` automatically — no manual `git push` needed after AFK runs.

**Observer:** a parallel Claude process wakes every 15 minutes (configurable via `RALPH_OBSERVE_INTERVAL`, in seconds) and reviews recent `RALPH(<name>)` commits + the PRD for drift — repeated tasks, off-PRD work, ABORT loops, vague commits, scope creep, test rot, etc. Each check is logged to `plans/observer-<name>.log` with `DRIFT_LEVEL: low|medium|high` + reasoning. On HIGH drift the observer writes `.ralph-stop`, which makes the loop exit gracefully at the next iteration boundary. Disable with `RALPH_NO_OBSERVE=1`.

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
