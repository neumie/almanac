---
name: agents-md-fix
description: Use when iteratively improving a CLAUDE.md or AGENTS.md file until it meets a target audit score. Spawns a blind reviewer subagent (target hidden, preventing score gaming) and a separate fixer subagent each iteration. Use this whenever the user says fix CLAUDE.md, improve agents-md, raise audit score, loop audit and fix, or wants automated iteration on an instruction file.
metadata:
  dependencies:
    - agents-md-audit
---

# Audit-and-Fix Loop for Agent Instruction Files

Iterates until a CLAUDE.md or AGENTS.md file passes a target audit score. The reviewer subagent never sees the target — prevents score gaming. The fixer subagent never sees the target — addresses every reported issue, not "enough to pass."

The agent running this skill is the **orchestrator**. Spawns subagents, parses scores, decides when to stop. Never delegates the stop decision.

## Inputs

Parse from skill args. Defaults if unspecified:

- `file` — path to file under audit. Default `./CLAUDE.md`.
- `target` — score (0-100) the file must reach. Default `99`.
- `max` — iteration cap. Default `5`.

If multiple CLAUDE.md / AGENTS.md exist and the user did not name one, ask which.

## Anti-Gaming Rules (Non-Negotiable)

1. Reviewer prompt MUST NOT mention the target score, iteration index, the word "loop", or anything implying a goal beyond honest scoring.
2. Fixer prompt MUST NOT mention the target score. Fixer addresses every Suggestion line.
3. Each reviewer call runs fresh — never paste a prior report into a new reviewer prompt.
4. Reviewer never edits the file. Fixer never scores or runs the audit.

Violating any of these defeats the design. If tempted to "just hint at the target so it stops earlier" — don't.

## Loop

Run up to `max` iterations:

### 1. Spawn reviewer (blind)

Use the Agent tool with `subagent_type: general-purpose`. Prompt — copy this template verbatim, substitute only `{FILE}`:

```
Audit the agent instruction file at `{FILE}`. Invoke the `almanac:agents-md-audit` skill via the Skill tool, run its full Phase 1 context scan, score the file against all six rubrics, and return the report verbatim. Do not edit the file. Return only the audit report.
```

Parse the returned report. Extract the total score from the line beginning `**Total: `. Capture the full report body (`Suggestions` section onward) for the fixer.

### 2. Stop check

- Score ≥ `target` → stop. Report final score, iterations used, and file path to the user.
- Iteration count = `max` and score < `target` → stop. Report last score and unresolved issues. Ask the user how to proceed.

### 3. Spawn fixer (target-blind)

Use the Agent tool with `subagent_type: general-purpose`. Prompt template — substitute `{FILE}` and `{REPORT}`:

```
Fix every issue in the audit report below for the file `{FILE}`. Use the Read and Edit tools. Address every Suggestion line — do not pick a subset, do not skip ones that look minor. Verify ground truth (file paths, function names, line references) before editing. After edits, if `tests/test-skills.sh` exists at the repo root, run `bash tests/test-skills.sh`; if it fails, fix the regression before returning. Return a short summary of what changed and any issue you could not address with reasoning.

---
{REPORT}
```

### 4. Re-loop

Increment iteration counter and return to step 1.

## Termination Output

Always report to the user:

- Final score and target.
- Iterations used (`N` of `max`).
- File path.
- If target unmet: bullet list of remaining issues from the last reviewer report.

## Why This Design

Reviewer-and-fixer separation enforces an information firewall. If a single agent both scores and edits, it can rationalize "good enough" once aware of the target. Splitting roles + hiding the target makes each subagent solve only its narrow job. The orchestrator (this agent) holds the target and decides termination.
