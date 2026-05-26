---
title: Overseer agent — VERDICT/STEER/STOP + convergence.md
status: open
type: AFK
blocked-by: [03-worker-prompt-with-shared-agent-runner]
user-stories: [7, 8, 10, 14, 15]
---

## What to build

A between-rounds **overseer agent** that reads recent worker self-reports + `CONVERGE(<slug>)` commits + the current `goal.md`, then emits a 4-field structured verdict. Three of those fields (VERDICT / REASON / STEER) land in this slice; the fourth (`GOAL_UPDATE`) lands in slice 05.

End user effect: the loop stops on its own when the overseer says `CONVERGED`. The operator never has to know the round budget — it's a safety net, not the termination signal.

Adds two flags: `--no-oversee` (disables the overseer entirely; loop runs until rounds budget) and `--oversee-every N` (cadence in rounds, default 1 = every round).

## Acceptance criteria

- [ ] `lib/converge-core.sh::almanac_converge_overseer_prompt` produces a prompt that:
  - [ ] Reads the current `goal.md` and embeds it verbatim
  - [ ] Tails `agent-reports.log` (last ~8KB — bounded like ralph's overseer at `scripts/afk.sh:329-333`)
  - [ ] Lists the last 10 `CONVERGE(<slug>)` commits via `git log --grep` (mirror ralph's pattern at `scripts/afk.sh:325`)
  - [ ] Instructs the overseer to output **exactly four lines** with no preamble:
    ```
    VERDICT: <CONVERGED|CONTINUE|STEER|STOP>
    REASON: <one paragraph>
    STEER: <one paragraph, or 'none'>
    GOAL_UPDATE: <new goal.md content, or 'unchanged'>
    ```
- [ ] `lib/converge-core.sh::almanac_converge_overseer_parse` parses the overseer's response into the four fields. Robust: missing/garbled lines default to `VERDICT=CONTINUE`, `STEER=none`, `GOAL_UPDATE=unchanged` (conservative — never accidentally stop or mutate goal on a malformed response).
- [ ] Overseer runs through `agent_run` with `sandbox=read-only` (same pattern as ralph's overseer at `scripts/afk.sh:373-380`). Provider/model/effort via `CONVERGE_OVERSEER_*` env, resolved through `lib/role.sh`.
- [ ] Cadence: `--oversee-every N` controls how often the overseer ticks (every N rounds; default 1). `--no-oversee` skips the tick entirely.
- [ ] Verdict handling:
  - [ ] `CONVERGED` or `STOP` → write `.converge-stop` → loop exits cleanly after current round → mark registry `status=done` (CONVERGED) or `status=aborted` (STOP)
  - [ ] `STEER:<directive>` → write `.converge-steer` (overwrites any prior) → slice 03's worker prompt consumes and removes
  - [ ] `CONTINUE` → no signal file, next round runs
  - [ ] `GOAL_UPDATE` field is **logged** to `overseer.log` for this slice but NOT applied to `goal.md` — slice 05 wires the mutation
- [ ] `convergence.md` written on loop exit (any terminal state) — captures: final verdict, tick count, time elapsed, final goal.md, final reason from the overseer.
- [ ] `tests/test-converge.sh` adds:
  - [ ] Overseer prompt embeds goal + tailed reports + commit log
  - [ ] Parser handles all four verdicts correctly
  - [ ] Parser is conservative on malformed input (returns CONTINUE/none/unchanged)
  - [ ] `CONVERGED` → `.converge-stop` written → loop exits next-iteration check → registry `status=done`
  - [ ] `STEER:<text>` → `.converge-steer` file content matches
  - [ ] `--no-oversee` skips the overseer agent entirely (assert `agent_run` is never called for the overseer role)
  - [ ] `--oversee-every 3` calls the overseer on rounds 3, 6, 9 only
  - [ ] `convergence.md` exists post-run with the four required sections
- [ ] `tests/test-structure.sh` and `tests/test-skills.sh` stay green.

## Notes

- The overseer is **read-only**. It never commits, never writes outside `overseer.log`, `.converge-stop`, `.converge-steer`, and `convergence.md`. Slice 05 will add `goal.md` and `goal.history.log` to its write list.
- Mirror ralph's overseer architecture but keep it **synchronous** (between-rounds tick). Ralph's overseer runs in a background subshell with its own interval timer; converge's overseer runs in the main loop, between rounds. Simpler, fewer concurrency bugs, and the cadence is round-based not wall-clock.
- The 4-field contract is the **interface**. Don't add a 5th field for "log this thing" or "annotate that thing" — extending the protocol is a separate slice.
- `--no-oversee` is the **trust knob**. Some users will want the convergence loop without the LLM judge — they'll set rounds=5, eyeball the result. Make sure this path has zero overseer-related work (no prompt, no agent call, no parsing, no `.converge-stop` writes from the overseer).
