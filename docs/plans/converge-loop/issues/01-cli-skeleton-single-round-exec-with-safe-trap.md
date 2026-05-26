---
title: CLI skeleton + single-round exec with safe EXIT trap
status: done
type: AFK
blocked-by: []
user-stories: [1, 2, 3, 11, 16, 17]
---

## What to build

A working `almanac converge` command that runs **one round** of a user-supplied exec command toward a user-supplied goal. End-to-end vertical tracer: CLI → arg validation → plan-dir scaffold → registry entry → exec → clean exit. No overseer, no agent runner yet — the exec runs directly in the shell. The EXIT trap is wired with the printf-`%q` baking pattern so a mid-loop `_die` cannot crash under `set -u`.

End user invocation:

```bash
almanac converge --goal "say hello" --exec "echo hello world"
```

Result: `docs/plans/converge/say-hello/` exists with `goal.md` (the goal text), an empty `agent-reports.log`, an empty `goal.history.log`. The exec runs once; a timestamped marker is appended to `agent-reports.log`. The registry shows `type=converge`, `status=done` on clean exit, `status=aborted` on mid-loop `_die`.

## Acceptance criteria

- [x] `cmd/converge.sh` parses `--goal "..."` (required), `--exec "..."` (required), `--rounds N` (optional, default 1 for this slice — multi-round comes in slice 02). Missing required args → `_die` with usage hint.
- [x] `lib/converge-core.sh::almanac_converge_run` scaffolds `docs/plans/converge/<slug>/` with `goal.md`, empty `agent-reports.log`, empty `goal.history.log`. The slug is derived from the goal via the same kebab-case lowercaser used by `almanac_harden_slug` (extract if needed; do not duplicate).
- [x] The exec command runs once via a bash subshell; the slice records a single line in `agent-reports.log` of the form `===== tick=1 ts=<ISO> exit=<N> =====`.
- [x] The run registers in `.almanac/runs/index.tsv` as `type=converge` via `almanac_loop_register_run`, with the same status-file contract ralph/harden use.
- [x] The EXIT trap uses `printf -v ... %q` baking (same pattern as `lib/harden-core.sh:1527-1538` from commit `1467073`) so a mid-loop `_die` marks the run `aborted`, NOT crashes with `root: unbound variable`.
- [x] `bin/almanac` dispatches `converge` to `cmd/converge.sh` (one-line case branch).
- [x] `tests/test-converge.sh`:
  - [x] CLI errors on missing `--goal` / `--exec`
  - [x] Plan dir scaffolded with the three files
  - [x] Exec runs (smoke: `--exec "touch $tmp/marker"` produces the file)
  - [x] Registry entry has `type=converge`, `target=<slug>`, `status=done` on clean exit
  - [x] Mid-loop `_die` (e.g. unwritable plan dir) leaves `status=aborted`, no `unbound variable` in stderr — mirrors `test_run_aborts_cleanly_when_target_missing` in `tests/test-harden-cli.sh`
- [x] `tests/test-structure.sh` and `tests/test-skills.sh` stay green.

## Notes

- Reuse helpers — do **not** duplicate. `almanac_harden_slug` (or move it to a shared helper in this slice if needed for hygiene) is the slug source of truth. `almanac_loop_register_run`, `almanac_loop_mark_run_status`, `almanac_loop_run_status_file` are the registry contract.
- This slice has **no provider invocation**. The exec is a shell command run via `bash -c "$exec"`. Provider/agent-runner arrives in slice 03.
- `--rounds` is parsed and stored but only round 1 runs in this slice. Multi-round looping lands in slice 02 so the round bookkeeping has its own commit.
- Doc sync is **not** required in this slice — slice 07 owns README/ARCHITECTURE/CONTRIBUTING/SKILL.md updates. This keeps the doc churn at the end where validation runs once.
- The trap pattern is the **load-bearing** part of this slice. Cite the harden commit (`1467073`) in the regression test comment so future readers see the rationale.

## Progress

- 2026-05-26: Added converge CLI skeleton, core runner, tests, dispatch, and safe abort trap - fulfills criteria 1, 2, 3, 4, 5, 6, 7, 8.
