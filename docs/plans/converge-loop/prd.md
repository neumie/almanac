## Problem Statement

I regularly want to point an agent at a custom workflow — "run /almanac:codebase-improve over and over until there's nothing major to improve", "keep refactoring this module until tests stop changing", "harden these contracts until reviewers add no new findings" — and have it iterate to a steerable goal without me babysitting each pass.

`ralph-loop` is close but PRD-bound: each iteration's action is hardcoded to "pick the next slice from `docs/plans/<prd>/issues/`". `harden-loop` is close but its action is a fixed lens-fanout + ratify-by-execution + fixer pipeline. Neither lets me say "the action is *this command*; converge when *this goal* is met."

The recurring failures I want this to solve:
1. **Hardcoded iteration action.** I can't supply the per-round command. Today that means writing a new loop skill for every recurring workflow.
2. **Immutable goal.** Harden's rubric is immutable to agents during a run by design (the contract). Ralph has no separate goal at all — the PRD is the goal. I want a goal that *evolves* during the run, judged by an overseer agent that has read recent reports and commits — without me stopping the loop to edit it.
3. **No generic convergence verdict.** Harden's gate is lens-specific ("zero open blocking findings + acceptance met"). Ralph's exit is queue-empty. I want an overseer agent to judge convergence against the *current* goal text and stop the loop when the answer is yes.

## Solution

`converge-loop` is a **generic convergence loop primitive** that runs a single user-supplied command per iteration toward a steerable goal:

```bash
almanac converge --goal "<initial goal>" \
                 --exec "<shell command>" \
                 [--rounds N] [--provider claude|codex] \
                 [--no-oversee] [--oversee-every N]
```

State lives under `docs/plans/converge/<slug>/`:

```
goal.md             current goal (overseer-mutable, human-editable)
goal.history.log    append-only audit of goal changes
prompt.md           worker iteration prompt template
agent-reports.log   worker self-reports
overseer.log        overseer tick decisions
convergence.md      final verdict on exit
```

Each round, a fresh agent reads `goal.md`, runs `<exec>`, writes a structured self-report, and commits its diff with prefix `CONVERGE(<slug>): <summary>`. Between rounds, an overseer agent reads recent reports + commits + the current goal and emits a 4-field verdict:

```
VERDICT: CONVERGED | CONTINUE | STEER | STOP
REASON: <one paragraph>
STEER: <directive for next iteration, or 'none'>
GOAL_UPDATE: <new goal.md content, or 'unchanged'>
```

- `CONVERGED` / `STOP` → writes `.converge-stop`, loop exits, `convergence.md` written
- `STEER:<directive>` → writes `.converge-steer` (one-shot for next iteration)
- `GOAL_UPDATE:<text>` → rewrites `goal.md`, appends before/after diff to `goal.history.log` with tick # and reason

The overseer updates the goal **directly** (logged for audit, no HITL gate). This is the deliberate choice — the operator's interaction is the goal authored at launch + the runtime knob `almanac converge <slug> --stop`. Mid-run goal evolution is the overseer's job.

This is a **sibling** of ralph (PRD-driven) and harden (lens-fanout). All three sit on the same shared engine: `lib/agent.sh` (the agent-run seam), `lib/run.sh` (the run registry), `lib/role.sh` (role → provider/model/effort resolution), and the EXIT-trap-safe pattern from the harden trap-scope fix.

## User Stories

1. As a developer, I want to launch a convergence loop with a goal string and an arbitrary exec command, so that I can iterate any workflow toward any goal without writing a new loop skill.
2. As a developer, I want the goal to live in `goal.md` so that it has a canonical, version-controlled location I can edit directly between runs.
3. As a developer, I want a starting round budget (`--rounds`) so that a misconfigured loop cannot run forever.
4. As a developer, I want each iteration to be a fresh agent context with the iteration prompt loading the current `goal.md`, so that goal changes propagate immediately to the next round.
5. As a developer, I want each iteration to commit its diff with a `CONVERGE(<slug>):` prefix, so that progress is auditable in git history.
6. As a developer, I want a structured self-report per iteration (concerns/errors/uncertainties), so that the overseer has signal beyond the diff alone.
7. As a developer, I want an overseer agent to judge convergence between rounds, so that the loop terminates without me supervising every round.
8. As a developer, I want the overseer to emit one-shot steering directives (`.converge-steer`) when it has concrete advice, so that mid-run drift gets corrected without my intervention.
9. As a developer, I want the overseer to rewrite `goal.md` when convergence requires narrowing or amending the goal, with the change logged to `goal.history.log`, so that the goal evolves visibly.
10. As a developer, I want a final `convergence.md` written on exit (converged or stopped), so that the run leaves a single durable record of what was achieved.
11. As a developer, I want the run registered in the shared registry as `type=converge`, so that `almanac hub` lists it alongside ralph and harden runs.
12. As a developer, I want `almanac converge <slug> --watch` to stream a live dashboard, so that I can supervise without tailing files.
13. As a developer, I want `almanac converge <slug> --stop` to halt the loop gracefully, so that I can intervene at any time.
14. As a developer, I want every role (worker, overseer) to resolve `(provider, model, effort)` via the shared role config, so that I can pick a different model for the overseer than the worker.
15. As a developer, I want `--no-oversee` to disable the overseer entirely (no goal mutation, no steering, just rounds + budget), so that the simplest mode is one trustworthy flag away.
16. As a developer, I want the loop to register its EXIT trap safely (no dynamic-scope dependency on `$root`/`$run_id`), so that a mid-loop `_die` marks the run aborted cleanly instead of crashing under `set -u`.
17. As a maintainer, I want converge-loop to follow almanac's authoring, validation, and doc-sync rules, so that it lands consistently with the rest of the repo.

## Implementation Decisions

**A new command, not an extension.** `almanac converge` sits alongside `almanac ralph` and `almanac harden`, not inside either. Harden's lens-fanout is its identity; ralph's PRD-queue is its identity. Converge's identity is `--goal` + `--exec` + overseer-judged convergence. Three commands, one shared engine.

**Overseer updates `goal.md` directly, no HITL gate.** This is the trade-off the user explicitly picked. The audit lives in `goal.history.log` (append-only). The HITL gate is "I authored the initial goal at launch, and I can `--stop` at any time."

**Reuse the shared engine, don't fork.** Worker invocations route through `lib/agent.sh::agent_run` (the seam ralph and harden already share). Role config via `lib/role.sh` (resolving `CONVERGE_AGENT_*` / `CONVERGE_OVERSEER_*` env). Run registry via `lib/run.sh` (entries with `type=converge`).

**EXIT-trap safety from day one.** Slice 01 lands the `printf -v ... %q` baking pattern (from the harden trap-scope fix shipped at `1467073`) so the loop's mid-`_die` abort cannot fall into the dynamic-scope trap pit again.

**One worker per round, sequential.** No fanout. The exec command is whatever the user supplies — `claude -p '/almanac:codebase-improve'`, a shell pipeline, a make target — and one of those per round is enough. Parallelism would require contracts (lenses, slices) the converge primitive deliberately avoids.

**Worker commit policy.** After the exec runs, if the working tree has uncommitted changes, the worker commits with `CONVERGE(<slug>): <summary>` (best-effort, skip if nothing to commit). Matches ralph's pattern; gives the overseer git history to read.

**Self-report format.** Worker appends a structured block to `agent-reports.log` with a header `===== tick=N ts=ISO =====` and three sections: `summary:`, `concerns:`, `next:`. Bounded — the overseer tails the last ~8KB, matching ralph's overseer.

## Testing Decisions

- **What makes a good test:** assert external behavior of the deep modules. Given synthetic inputs (goal text, exec command, worker reports, overseer prompt response), assert the output (registry state, signal files written, `goal.md` after mutation, `convergence.md` after exit). Do not assert on prompt strings or provider internals beyond format contracts.
- **Provider seams are stubbed.** `lib/agent.sh::agent_run` is the only place a real provider gets invoked; tests stub it to return canned responses (a fake overseer verdict, a worker exit code). This is the same pattern `tests/test-harden-cli.sh` and `tests/test-ralph-*.sh` use.
- **No real git remote needed.** Worker commits happen in a `mktemp` repo; tests `git init` per fixture. No push, no remote.
- **EXIT-trap regression test** ships in slice 01 alongside the trap pattern — same shape as `test_run_aborts_cleanly_when_target_missing` in `tests/test-harden-cli.sh`.

## Out of Scope (v1)

- HITL prompts between rounds. The design picks overseer-direct goal mutation; HITL is a deliberate non-feature.
- Parallel workers per round. The exec command is sequential; fanout is harden's territory.
- Goal proposals from the worker (vs the overseer). The worker self-reports facts; the overseer is the sole goal mutator.
- A separate "ratify" or "feedback" phase. Convergence is judged from reports + commits — no separate gate runner.
- GitHub PR integration. Local-only; ralph already covers PR workflows.
- `--watch-worker` style per-iteration event tailing. The dashboard at `--watch` is enough for v1.
