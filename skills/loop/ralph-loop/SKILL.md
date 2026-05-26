---
name: ralph-loop
description: "Use when autonomously implementing a PRD task-by-task. Each loop iteration picks one task, TDDs it, commits, exits. Progress persists in git. Triggers: ralph, AFK mode, autonomous loop."
disable-model-invocation: true
metadata:
  source: mattpocock/ralph-workshop-repo-001 (technique only — no canonical SKILL.md to SHA-sync)
  adapted-date: "2026-04-28"
---

# Ralph Loop

Autonomous implementation loop. Each iteration gets fresh context, picks one task from the PRD, implements it, runs feedback loops, commits, and exits. Progress lives in git history, not conversation memory.

## Setup

These commands run automatically when the skill loads — output replaces each line below:

- Available PRDs: !`for d in docs/plans/*/; do [ -f "$d/prd.md" ] && basename "$d"; done 2>/dev/null || true`
- Project files: !`ls package.json Makefile Cargo.toml go.mod pyproject.toml setup.py 2>/dev/null || true`
- Tests directory: !`ls tests/ 2>/dev/null || true`

### 1. Select a PRD

From the PRD list:

- If the user passed a name (e.g. `/ralph-loop auth-system`), use `docs/plans/auth-system/prd.md`
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
mkdir -p docs/plans/<name>
```

### 4. Generate the prompt

Prefer the prompt generator script because it uses the shared loop engine's
feedback detector:

```bash
bash skills/loop/ralph-loop/scripts/prompt.sh <name>
```

If running from an installed skill path, resolve `{{SKILL_SCRIPTS}}` as in
step 5 and run `bash {{SKILL_SCRIPTS}}/prompt.sh <name>`.

The script writes `docs/plans/<name>/prompt.md`, sources `lib/feedback.sh`,
and renders feedback commands from `almanac_loop_feedback_markdown()`.
Use the template below only as a fallback when the script is unavailable.

Write `docs/plans/<name>/prompt.md` (e.g. `docs/plans/auth-system/prompt.md`) using the template below, filling in the detected feedback loops and the PRD path:

```markdown
# INPUTS

Pull @{{PRD_FILE}} into your context.

You've been passed the last 10 RALPH commits (SHA, date, full message). Review these to understand what work has been done.

# TASK QUEUE

Before decomposing the PRD, check whether an explicit queue exists. Detect in this order:

1. **Local slice files.** If `docs/plans/<name>/issues/` contains `*.md` files, that directory is your queue. Each file has frontmatter (`status`, `blocked-by`, `type`) and an `## Acceptance criteria` checklist of `- [ ]` items.
2. **GitHub issues.** Else if `gh issue list --search 'label:"ralph(<name>)" state:open'` returns at least one issue, that's your queue. (Use `--search`, not `--label` — the parenthesised label name breaks the `--label` filter.) Each issue body contains an `## Acceptance criteria` section with `- [ ]` items.
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

{{FEEDBACK_COMMANDS}}

# COMMIT

If you used a queued task, update the queue using the **strict checkbox protocol** before committing.

**Strict means:** flip a `- [ ]` to `- [x]` ONLY for an acceptance criterion that THIS commit's actual code changes demonstrably fulfill. Do not flip a checkbox for something "almost", "implicitly", or "previously" done. The overseer audits these flips against the diff and rolls back overclaims.

**Local slice file:**

1. Edit the slice file: flip `- [ ]` → `- [x]` for each criterion this commit fulfills.
2. Append a line under `## Progress` (create the section if it doesn't exist): `- <ISO-date>: <one-line summary> — fulfills criteria N[, M…]`.
3. If every `- [ ]` in `## Acceptance criteria` is now `- [x]`, also flip frontmatter `status: open` → `status: done`.
4. Stage the slice-file edits as part of this commit.

**GitHub issue:**

1. Fetch current body: `gh issue view <num> --json body -q .body > /tmp/issue-body.md`.
2. Edit `/tmp/issue-body.md` to flip the relevant `- [ ]` → `- [x]`.
3. After committing the code, push the body update: `gh issue edit <num> --body-file /tmp/issue-body.md`.
4. Post a comment with the commit SHA: `gh issue comment <num> --body "<sha>: <summary> — fulfills criteria N[, M…]"`.
5. If every checkbox is now `- [x]`, also `gh issue close <num>`.

Then make the git commit. The commit message must:

1. Start with `RALPH(<name>):` prefix (e.g. `RALPH(auth-system):`)
2. Include task completed + PRD reference
3. Key decisions made
4. Files changed
5. Blockers or notes for next iteration

Keep it concise but informative for the next iteration.

# REPORT

After committing, append a self-report to `docs/plans/<name>/agent-reports.log`. The overseer reads recent reports each tick and may emit steering directives based on what you flag. Be honest — concerns and uncertainties are more useful than reassurance.

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
```

Replace `{{FEEDBACK_COMMANDS}}` with the detected commands as a markdown list
matching `almanac_loop_feedback_markdown()`, e.g.:
```markdown
- `npm run test` to run the tests
- `npm run typecheck` to run the type checker
```

### 5. Tell the user how to run it

Print:

```
Ralph loop ready for <name>.

  Interactive CLI:
    almanac ralph
    # or: bash {{SKILL_SCRIPTS}}/ralph.sh

  Single iteration (HITL):
    bash {{SKILL_SCRIPTS}}/once.sh <name>

  Autonomous (AFK):
    bash {{SKILL_SCRIPTS}}/afk.sh <name> <iterations>

  Example — run 10 iterations:
    bash {{SKILL_SCRIPTS}}/afk.sh auth-system 10
```

Where `{{SKILL_SCRIPTS}}` is the absolute path to this skill's scripts. Resolve in this order:

1. `~/.agents/skills/almanac/ralph-loop/scripts` — set by `almanac install codex`; use this when running in Codex.
2. `~/.claude/skills/almanac/ralph-loop/scripts` — set by `almanac install claude-code`; use this when running in Claude Code.
3. `${CLAUDE_SKILL_DIR}/scripts` — fallback if the host agent populates `CLAUDE_SKILL_DIR` from the resolved skill directory.
4. `$ALMANAC_HOME/skills/loop/ralph-loop/scripts` — fallback when invoked outside an installed provider.

Print the literal provider install path in user-facing instructions (`~/.agents/...` for Codex, `~/.claude/...` for Claude Code) so users can run the scripts directly.

## Modes

### AFK Mode (`afk.sh`)

Fully autonomous. Runs N iterations, each in a fresh agent context. Stops when:
- All tasks complete (`<promise>COMPLETE</promise>`)
- A task is blocked (`<promise>ABORT</promise>`)
- Iteration limit reached
- `.ralph-stop` file exists in the working directory (graceful stop — see below)
- Overseer detects HIGH drift (writes `.ralph-stop` automatically — see Overseer below)

**Provider selection:** set `RALPH_PROVIDER=codex` or `RALPH_PROVIDER=claude` to force an agent. If unset, the scripts use Codex when running inside Codex, otherwise Claude Code when available, otherwise Codex.

**Model override:** set `RALPH_MODEL` (e.g. `RALPH_PROVIDER=codex RALPH_MODEL=gpt-5.5 bash afk.sh <name> 10` or `RALPH_MODEL=claude-opus-4-7 bash afk.sh <name> 10`); unset uses the selected provider's default.

**Thinking override:** set `RALPH_EFFORT` to control model thinking level. Codex receives this as `model_reasoning_effort`; Claude Code receives it as `--effort`. Supported common values: `low`, `medium`, `high`, `xhigh`; Claude Code also supports `max`.

**Codex output:** Codex raw session output is quiet by default and written to `docs/plans/<name>/ralph-codex-*.log`; the terminal shows concise agent progress messages, the final assistant message, and the log path. Set `RALPH_CODEX_VERBOSE=1` to stream Codex's full session output.

**Interactive launcher:** run `almanac ralph` (or `ralph.sh` directly) to select PRD, mode, provider, model, thinking level, iteration count, and overseer behavior from prompts. It delegates to `once.sh` or `afk.sh` with the corresponding `RALPH_PROVIDER`, `RALPH_MODEL`, `RALPH_EFFORT`, and `RALPH_NO_OVERSEE` environment values.

**Auto-push:** the overseer pushes any unpushed RALPH commits to `origin` at the start of each tick (default 15 min, configurable via `RALPH_OVERSEE_INTERVAL`). This batches commits so CI runs at overseer cadence rather than per-iteration — avoids clogging CI when iterations are minutes apart. End-of-loop also pushes as a safety net. Sets upstream automatically on first push and repairs mismatched upstreams such as `origin/main`.

**Overseer:** a parallel process wakes every `RALPH_OVERSEE_INTERVAL` seconds (default 900 = 15 min) and runs a sequential tick:

1. **Push** (shell). Pushes any local commits ahead of upstream. Logs to `docs/plans/<name>/overseer.log`.

2. **Wait for CI** (shell, only if step 1 actually pushed). Polls `gh run list` every `RALPH_CI_POLL_INTERVAL` seconds (default 30) for the run matching the pushed `headSha`, blocking until status leaves `in_progress|queued|waiting|requested|pending`. Times out after `RALPH_CI_WAIT_TIMEOUT` seconds (default 1800 = 30 min). Exits early on `.ralph-stop`. While the overseer waits, main-loop iterations keep running — only the overseer thread is blocked.

3. **CI verdict** (shell, no Claude call). Reads `gh run list --limit 1`. On `conclusion=failure|cancelled|timed_out|action_required|startup_failure`, writes `.ralph-ci-failed` (run URL, ID, workflow name, branch, timestamp). On `conclusion=success`, clears the marker. Also runs once at script start to pick up pre-existing failures from prior sessions or manual pushes.

4. **Drift review** (selected agent call). Reviews recent `RALPH(<name>)` commits, **the tail of `docs/plans/<name>/agent-reports.log`** (last ~8KB of agent self-reports — concerns, errors, uncertainties), **and any task queue** (slice files in `docs/plans/<name>/issues/` or open GitHub issues with the `ralph(<name>)` label) against the PRD. Detects:

   - Repeated tasks, off-PRD work, ABORT loops, vague commits, scope creep, test rot, recurring concerns the agents aren't solving on their own.
   - **Queue overclaim** — checkboxes flipped to `[x]` (or `status: done` set, or issues closed) without the corresponding code in those commits. For each recently-flipped checkbox, the overseer reads the slice/issue criterion and the commits that flipped it, and judges whether the diff actually fulfills the criterion. If not, the steer directs the next iteration to roll back the checkbox / status / issue closure.
   - **Queue staleness** — criteria clearly fulfilled by recent commits but checkbox still `[ ]`.

   Outputs `DRIFT_LEVEL: low|medium|high`, `REASON: …`, `STEER: …`. On HIGH drift writes `.ralph-stop`. When `STEER` is non-`none`, writes the directive to `.ralph-steer`.

Effective drift-review cadence is `RALPH_OVERSEE_INTERVAL + (CI duration if pushed)`. Steps 2-3 silently no-op if `gh` is missing, the repo has no remote, or no run materialized for the pushed SHA.

Disable the whole overseer with `RALPH_NO_OVERSEE=1` — that also disables overseer-cadence push, CI wait, CI monitoring, and steer; only the end-of-loop push remains.

**Iteration prompt prefixes:** at the start of each iteration, `afk.sh` may prepend up to two directives to the iteration prompt:

- **Fix-CI** — when `.ralph-ci-failed` exists. The spawned agent is told to skip new task work, read the marker, fetch logs via `gh run view`, repair, and commit with `RALPH(<name>): fix CI — …`. Persistent: cleared automatically by the next overseer tick once CI is green again.
- **Overseer steer** — when `.ralph-steer` exists. The spawned agent is told the overseer reviewed recent reports + commits and emitted concrete advice (wrong assumption, scope correction, alternate approach, etc.). One-shot: `afk.sh` removes the file after consumption. The overseer can re-emit it next tick if the underlying issue persists.

Both can stack — a steered fix-CI iteration is valid.

**Agent self-reports:** the iteration prompt template instructs the spawned agent to append a structured block to `docs/plans/<name>/agent-reports.log` after committing — `concerns`, `errors`, `uncertainties` per iteration. This is the primary signal the overseer uses to decide whether to issue a steer beyond what the commits alone reveal. Agents are told to be honest — flagged uncertainties are more useful than reassurance.

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
