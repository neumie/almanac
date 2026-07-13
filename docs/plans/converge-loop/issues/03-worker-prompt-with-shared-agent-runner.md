---
title: Worker prompt via shared agent_run seam + structured self-reports
status: done
type: AFK
blocked-by: [02-multi-round-budget-with-commits]
user-stories: [4, 6, 14]
---

## What to build

Replace the direct `bash -c "$exec"` from slices 01–02 with a **worker agent** spawned through the shared `lib/agent.sh::agent_run` seam (the same one loop and harden use). The agent reads `goal.md`, runs the `--exec` command itself, then writes a structured self-report to `agent-reports.log`. Provider / model / effort resolve via `lib/role.sh` (`CONVERGE_AGENT_PROVIDER`, `CONVERGE_AGENT_MODEL`, `CONVERGE_AGENT_EFFORT`).

The worker prompt template lives at `docs/plans/converge/<slug>/prompt.md` — generated at first run, editable between runs.

## Acceptance criteria

- [x] `lib/converge-core.sh::almanac_converge_worker_prompt` produces a prompt that:
  - [x] Embeds the current `goal.md` contents (read fresh each round, so goal mutations from slice 05 take effect on the next round)
  - [x] Instructs the worker to run the `--exec` command in its sandbox
  - [x] Instructs the worker to commit any diff with the message `CONVERGE(<slug>): <one-line summary>` (worker commits, not the loop driver — frees the worker to author meaningful messages)
  - [x] Instructs the worker to append a structured self-report to `agent-reports.log` with the exact header `===== tick=<N> ts=<ISO> =====` and three sections: `summary:`, `concerns:`, `next:`
  - [x] Picks up `.converge-steer` if present (one-shot directive); the loop driver removes the file after the worker reads it (the consumption pattern from `scripts/afk.sh:298-308`)
- [x] `docs/plans/converge/<slug>/prompt.md` is created on first round if absent; subsequent rounds re-read it (so the user can edit between rounds).
- [x] Each round spawns the worker via `agent_run` with `sandbox=workspace-write` (so it can commit). Provider resolved via `lib/role.sh::almanac_role_field "agent" "" provider` against `CONVERGE_AGENT_*` env (extend `lib/role.sh` if it currently hardcodes the consumer name; converge needs to be a recognized consumer alongside loop and harden — keep the lookup table-driven, not branched).
- [x] The worker's commit replaces the loop-driver commit from slice 02. The driver no longer commits; if the worker fails to commit but produced a diff, the driver logs a `_warn` but does not retry the commit (the worker is authoritative).
- [x] Slice 02's commit-prefix tests are migrated to assert the worker commits (stub `agent_run` to write a fake commit; the test verifies the prefix + presence, not the real model behavior).
- [x] `tests/test-converge.sh` adds:
  - [x] Worker prompt embeds `goal.md` contents verbatim
  - [x] `.converge-steer` content embedded in prompt and the file is removed after consumption
  - [x] `agent_run` is invoked with `sandbox=workspace-write` and the resolved provider/model/effort
  - [x] Structured self-report block with the expected three-section header is parseable by the slice 04 overseer (write a simple parser/checker now to lock the format)
  - [x] `CONVERGE_AGENT_PROVIDER=codex` env override threads through (use the same fixture pattern as `test_role_config_overrides_each_role_via_env` in `tests/test-harden-cli.sh`)
- [x] `tests/test-structure.sh` and `tests/test-skills.sh` stay green.

## Notes

- This is where the loop becomes **agentic**. Up to here it was a shell-script loop with bookkeeping. From here on, every iteration is a real provider call (or a stubbed one in tests).
- The role-config lookup needs to accept `converge` as a consumer prefix. Audit `lib/role.sh` — if it has a hardcoded `loop|harden` switch, replace with a generic consumer arg.
- Keep the prompt template **bounded**. Don't embed full agent-reports history; that's the overseer's job. The worker sees: goal.md, exec command, optional steer directive. That's it.
- A failed `agent_run` exits the round non-zero but does not abort the loop (consistent with slice 02's "exec failure is a `_warn`, loop continues" policy).

## Progress

- 2026-05-26: Added worker prompt template/rendering, shared agent seam invocation, worker-authored commit flow, one-shot steer consumption, structured report parser, and converge worker tests - fulfills criteria 1, 2, 3, 4, 5, 6, 7.
