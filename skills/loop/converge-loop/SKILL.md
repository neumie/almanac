---
name: converge-loop
description: "Use when running converge-loop: repeat one custom command toward a mutable goal with overseer verdicts, steering, and stop/watch controls."
disable-model-invocation: true
metadata:
  source: new almanac pattern (no upstream SKILL.md or SHA to sync)
  adapted-date: "2026-05-26"
---

# Converge Loop

A generic convergence loop for "run this command until this goal is met".
Each round starts a fresh write-capable worker agent, gives it the current
`goal.md`, runs one exact exec command, asks it to commit useful changes, and
records a structured self-report. Between rounds, a read-only overseer judges
progress against the current goal and can stop, steer the next worker, or update
the goal directly.

Use it when the iteration action is not a spec slice queue and not harden's
review/fix pipeline. Examples: repeat `/almanac:codebase-improve` until no major
architecture issue remains, run a custom migration check until clean, or keep a
refactor command moving while an overseer narrows the target.

## CLI

Run from the repo being changed. New runs use `--goal` and `--exec`; existing
runs are addressed by their generated slug.

```bash
almanac converge --goal "<goal>" --exec "<shell command>" [--rounds N]
almanac converge --goal "<goal>" --exec "<shell command>" --no-oversee
almanac converge --goal "<goal>" --exec "<shell command>" --oversee-every N

almanac converge <slug>          # status summary
almanac converge <slug> --watch  # live redraw dashboard
almanac converge <slug> --stop   # graceful stop signal
```

Round budget defaults to `${CONVERGE_ROUND_BUDGET:-10}`. Overseer cadence
defaults to `${CONVERGE_OVERSEE_EVERY:-1}`. Set `CONVERGE_FAIL_ON_EXEC_ERROR=1`
to stop on a non-zero exec exit; otherwise the loop logs the failure and
continues.

Canonical demo:

```bash
almanac converge \
  --goal "Improve the codebase until no major architecture friction remains" \
  --exec "claude -p '/almanac:codebase-improve'" \
  --rounds 5
```

Other examples:

```bash
almanac converge \
  --goal "Harden lib/role.sh docs until tests and reviewers agree" \
  --exec "bash tests/test-role.sh && claude -p 'review lib/role.sh for stale docs'" \
  --oversee-every 2

almanac converge \
  --goal "Finish current local refactor without changing public behavior" \
  --exec "codex exec 'run tests, inspect failures, make one focused fix, commit it'" \
  --no-oversee \
  --rounds 3
```

## State

State lives in `docs/plans/converge/<slug>/`. Runtime registry state lives under
`.almanac/`.

```text
docs/plans/converge/<slug>/
  goal.md             current goal; overseer-mutable and human-editable
  goal.history.log    append-only audit trail for goal rewrites
  prompt.md           editable worker prompt template created on first round
  agent-reports.log   worker self-reports, one block per round
  overseer.log        overseer decisions and parsed verdict fields
  convergence.md      final verdict, tick count, elapsed time, final goal
```

The worker prompt re-reads `goal.md` and `prompt.md` each round. Human edits to
either file take effect on the next worker.

## Worker Contract

The worker receives:

- `CONVERGE_TICK`
- `CONVERGE_SLUG`
- `CONVERGE_PLAN_DIR`
- `CONVERGE_REPORT_LOG`
- current `goal.md`
- exact exec command
- optional one-shot steer directive from `.converge-steer`

The worker should run the exact exec command, commit user-visible worktree
changes with `CONVERGE(<slug>): <summary>`, and append one self-report block:

```text
===== tick=<N> ts=<ISO> =====
summary:
concerns:
next:
```

The loop driver does not commit for the worker. If the worker leaves user-visible
changes uncommitted, the driver warns and continues.

## Overseer Contract

The overseer runs read-only after configured rounds. It sees the current goal,
recent worker reports, and recent `CONVERGE(<slug>):` commits. It must emit four
fields in this order:

```text
VERDICT: <CONVERGED|CONTINUE|STEER|STOP>
REASON: <one paragraph>
STEER: <one paragraph, or 'none'>
GOAL_UPDATE: <new goal.md content, or 'unchanged'>
```

Malformed output is conservative: `CONTINUE`, no steering, no goal update.
`GOAL_UPDATE` may span multiple lines because it is the final field.

Continue example:

```text
VERDICT: CONTINUE
REASON: Tests pass, but the report still names two duplicated parsing paths.
STEER: Focus only on the parser duplication; do not touch command help text.
GOAL_UPDATE: unchanged
```

Converged example:

```text
VERDICT: CONVERGED
REASON: Recent reports show no remaining major architecture friction and tests pass.
STEER: none
GOAL_UPDATE: unchanged
```

Goal update example:

```text
VERDICT: STEER
REASON: The broad goal is mostly complete; remaining risk is role-config docs.
STEER: Update docs only, then run structure and skill validation.
GOAL_UPDATE: Finish role-config documentation for converge. Do not change runtime code.
```

Verdict handling:

| Verdict | Effect |
|---------|--------|
| `CONVERGED` | Writes `.converge-stop`, exits done, writes `convergence.md`. |
| `STOP` | Writes `.converge-stop`, exits aborted, writes `convergence.md`. |
| `STEER` | Writes `.converge-steer` when `STEER` is not `none`; next worker consumes it once. |
| `CONTINUE` | Runs next round until budget or stop signal. |

When `GOAL_UPDATE` is not `unchanged`, `goal.md` is rewritten and
`goal.history.log` records provider, reason, before/after diff, and tick.

## Role Config

Converge uses the shared role resolver. Defaults use the current provider
default; override per role with env vars:

| Role | Env prefix | Sandbox | Purpose |
|------|------------|---------|---------|
| worker agent | `CONVERGE_AGENT_*` | `workspace-write` | Runs the exec command and commits changes. |
| overseer | `CONVERGE_OVERSEER_*` | `read-only` | Judges convergence, steers, and mutates `goal.md`. |

Fields are `PROVIDER`, `MODEL`, and `EFFORT`.

```bash
CONVERGE_AGENT_PROVIDER=codex \
CONVERGE_AGENT_MODEL=gpt-5 \
CONVERGE_OVERSEER_PROVIDER=claude \
CONVERGE_OVERSEER_MODEL=opus \
  almanac converge --goal "..." --exec "..." --rounds 4
```

Resolution order is role-specific first, then consumer-wide, then default:

```text
CONVERGE_<ROLE>_{PROVIDER,MODEL,EFFORT}
CONVERGE_{PROVIDER,MODEL,EFFORT}
default provider/model/effort
```

## Use vs Loop vs Harden

| Loop | Use when | Convergence signal |
|------|----------|--------------------|
| `loop` | You have a spec and slice queue under `docs/plans/<name>/issues/`. | Queue empty or slice work complete. |
| `almanac harden` | You need parallel reviewers, ratify-by-execution, and a single fixer against a target. | Acceptance met and zero open blocking findings. |
| `converge-loop` | You already know the per-round command and want an overseer to judge a mutable goal. | Overseer verdict against current `goal.md`. |

## Supervision

Use `almanac converge <slug>` for a one-shot status frame. Use
`almanac converge <slug> --watch` for a live dashboard showing round, last
verdict, recent report header, goal summary, mutation count, and worker health.
Use `almanac converge <slug> --stop` to request graceful shutdown at the next
round boundary.

## gum is optional

The dashboard uses [`gum`](https://github.com/charmbracelet/gum), a single
optional Go binary. When `gum` is absent (or output is piped, or
`ALMANAC_NO_GUM=1`), the CLI degrades gracefully to plain output - almanac keeps
its near-zero-dependency promise. Run `almanac doctor` to check whether `gum` is
installed.

## Notes

- `--no-oversee` disables goal mutation and steering entirely; the loop runs only
  the worker rounds until the budget is exhausted.
- Converge can be launched directly with `almanac converge --goal ... --prompt ...`
  or `--exec ...`, and through `almanac hub --new converge ...`.
- The exec command is trusted user input. Converge judges progress; it is not a
  dangerous-command sandbox or approval gate.
