---
name: ralph-loop
description: Use when autonomously implementing a PRD or plan task-by-task. Runs Claude in a loop where each iteration picks one task, implements it with TDD, commits, and exits. Progress persists in git, not context. Use this whenever the user says ralph, ralph loop, AFK mode, autonomous loop, or wants hands-off implementation of a plan.
metadata:
  upstream: mattpocock/ralph-workshop-repo-001
  adapted-date: "2026-04-28"
---

# Ralph Loop

Autonomous implementation loop. Each iteration gets fresh context, picks one task from the PRD, implements it, runs feedback loops, commits, and exits. Progress lives in git history, not conversation memory.

## Setup

### 1. Check for a PRD

The loop needs a PRD to work from. Check for one:

```bash
ls plans/prd.md 2>/dev/null
```

If no PRD exists:
- If there's a GitHub issue to work from, fetch it and write it to `plans/prd.md`
- Otherwise, tell the user to run `/prd-create` first

### 2. Detect feedback loops

Look for available feedback commands in the project:

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

Write `plans/prompt.md` using the template below, filling in the detected feedback loops:

```markdown
# INPUTS

Pull @plans/prd.md into your context.

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

1. Start with `RALPH:` prefix
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
Ralph loop ready.

  Single iteration (HITL):
    bash {{SKILL_SCRIPTS}}/once.sh

  Autonomous (AFK):
    bash {{SKILL_SCRIPTS}}/afk.sh <iterations>

  Example — run 10 iterations:
    bash {{SKILL_SCRIPTS}}/afk.sh 10
```

Where `{{SKILL_SCRIPTS}}` is the path to this skill's scripts directory: `${CLAUDE_SKILL_DIR}/scripts`.

## Modes

### AFK Mode (`afk.sh`)

Fully autonomous. Runs N iterations, each in a fresh Claude context. Stops when:
- All tasks complete (`<promise>COMPLETE</promise>`)
- A task is blocked (`<promise>ABORT</promise>`)
- Iteration limit reached

### HITL Mode (`once.sh`)

Single iteration with human in the loop. Runs one pass — you review the result before continuing. Good for:
- First iteration (sanity check)
- After an ABORT (diagnose and unblock)
- When you want to steer

## Monitoring

While AFK mode runs, you can watch progress:

```bash
git log --grep="RALPH" --oneline
```

Each `RALPH:` commit message contains what was done and notes for the next iteration.

## When to stop

- All tasks done → loop exits with "Ralph complete"
- Something's wrong → loop exits with "Ralph aborted"
- You see bad commits → Ctrl+C and review
- Context is confused → kill it, fix the issue, restart (fresh context = fresh start)
