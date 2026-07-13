---
title: Multi-round budget loop with per-round CONVERGE commits
status: done
type: AFK
blocked-by: [01-cli-skeleton-single-round-exec-with-safe-trap]
user-stories: [3, 5]
---

## What to build

Promote the single-round skeleton into a true multi-round loop. `--rounds N` (default 10 or `CONVERGE_ROUND_BUDGET`) runs the exec N times. After each round, if the worktree has uncommitted changes, the worker commits with `CONVERGE(<slug>): <round-N>` prefix. Registry progress is flushed each round so `almanac hub` can show advancement.

End user invocation:

```bash
cd /tmp/empty-repo && git init -q
almanac converge --goal "make markers" --exec "touch m-\$(date +%s%N)" --rounds 3
```

Result: 3 rounds, 3 commits on `HEAD` each prefixed `CONVERGE(make-markers):`, registry `round=3` and a `summary=` field updated each round.

## Acceptance criteria

- [x] `--rounds N` is honored — the loop runs N rounds, never N+1, never N-1 (off-by-one regression test).
- [x] Default round budget is `${CONVERGE_ROUND_BUDGET:-10}` (matches the harden / loop convention of "env var or hardcoded default").
- [x] After each round's exec exits, `lib/converge-core.sh` checks `git status --porcelain` in the working dir. If non-empty, runs `git add -A && git commit -m "CONVERGE(<slug>): round <N>" --no-verify` (best-effort; a failed commit logs a `_warn` but does not abort the loop).
- [x] No diff after a round = no commit (verify in tests: `--exec "true" --rounds 2` produces zero commits).
- [x] `almanac_loop_update_run_progress` is called at the end of each round with `round=<N>` and `summary=goal=<slug>` (or whatever the contract supports — match the field set loop/harden write).
- [x] Per-round `agent-reports.log` entries grow correctly: round N appends the line `===== tick=N ts=<ISO> exit=<rc> =====` (same shape slice 01 wrote, but now per-round).
- [x] Exit code: `0` if all rounds complete cleanly. Non-zero ONLY if an exec returns non-zero AND `CONVERGE_FAIL_ON_EXEC_ERROR=1` is set; otherwise an exec failure is logged via `_warn` and the loop continues to the next round (the exec is user-supplied; transient failures shouldn't kill the loop by default).
- [x] `tests/test-converge.sh` adds:
  - [x] Round count exactness: `--rounds 3` runs exactly 3 times
  - [x] Default budget: no `--rounds` flag → 10 iterations
  - [x] `CONVERGE_ROUND_BUDGET=2` env override works
  - [x] Commit prefix is correct, commits land on HEAD, count matches diff-producing rounds
  - [x] Zero-diff rounds skip the commit
  - [x] `CONVERGE_FAIL_ON_EXEC_ERROR=1` propagates an exec exit code; default mode does not
- [x] `tests/test-structure.sh` and `tests/test-skills.sh` stay green.

## Notes

- The git-commit step needs a working tree. Tests should `git init` in a `mktemp` dir and run from there. Reuse the test fixtures pattern from `tests/test-loop-push.sh` / `tests/test-harden-cli.sh::new_tmpdir`.
- The commit is `--no-verify` — converge runs are autonomous; commit hooks that prompt would deadlock.
- Per-round progress write goes through `almanac_loop_update_run_progress` if it exists; otherwise extend `lib/run.sh` with the minimum needed (do not invent a parallel contract).
- This slice does **not** introduce the overseer or any provider call — keep the exec as a direct `bash -c` subshell. The agent runner arrives in slice 03.

## Progress

- 2026-05-26: Added multi-round budget execution, per-round reports/progress, best-effort CONVERGE commits, zero-diff skip, and exec failure policy - fulfills criteria 1, 2, 3, 4, 5, 6, 7, 8, 9.
