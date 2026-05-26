---
title: Hub integration + --watch dashboard + --stop control
status: open
type: AFK
blocked-by: [04-overseer-verdict-steer-stop]
user-stories: [11, 12, 13]
---

## What to build

Wire converge runs into the shared `almanac hub` so they appear alongside ralph and harden runs in the registry view. Add `almanac converge <slug> --watch` (live dashboard, redraw loop) and `almanac converge <slug> --stop` (graceful halt via `.converge-stop`). Slice 04 already writes `.converge-stop` from the overseer; this slice exposes the same signal to the human operator.

Goal: converge feels like a first-class citizen alongside the two other loops.

## Acceptance criteria

- [ ] `cmd/hub.sh` recognizes `type=converge` rows in `.almanac/runs/index.tsv` and renders them with the same columns as ralph/harden. No converge-specific branch in the hub — the registry's uniform contract carries everything needed (id, type, target, pid, status, started_at, round, summary, failure_reason).
- [ ] `lib/loops/converge.sh` (the auto-discovered loop adapter, per CLAUDE.md's loop-adapter map) declares its control contract:
  - [ ] `signal_file stop` → `.converge-stop`
  - [ ] `signal_file steer` → `.converge-steer`
  - This lets the hub's generic stop/steer codepaths work without code change.
- [ ] `almanac converge <slug>` with no other flags prints a status summary (current round, last verdict, recent reports tail) — matches harden's `almanac harden <target>` no-flag behavior shape.
- [ ] `almanac converge <slug> --watch` runs a redraw loop showing:
  - [ ] Current round / round budget
  - [ ] Last overseer verdict + reason
  - [ ] Last self-report header line (`===== tick=N ts=... =====`)
  - [ ] Goal summary (first 80 chars of `goal.md`)
  - [ ] Goal mutation count (lines in `goal.history.log` matching the header regex)
  - [ ] Worker health (alive / dead via the registry pid, same check the hub uses)
  - [ ] Degrades to plain output when `gum` is absent (reuse `lib/ui.sh` primitives, do not duplicate)
- [ ] `almanac converge <slug> --stop` writes `.converge-stop` to the plan dir and exits 0. The running loop picks it up at its next round-boundary check and exits cleanly (registry marks `status=aborted`).
- [ ] The launcher (`lib/loop-launcher.sh`) does NOT need to gain a converge mode for this slice — converge is launched directly via `almanac converge --goal ... --exec ...`. The launcher integration is a v2 concern (interactive prompt-style launching for converge).
- [ ] `tests/test-converge.sh` adds:
  - [ ] Hub list output (via `almanac hub` invoked as a subprocess) shows a converge run
  - [ ] `almanac converge <slug>` (no flags) prints status with current round + last verdict
  - [ ] `almanac converge <slug> --stop` writes `.converge-stop` and the loop exits cleanly on next round
  - [ ] `--watch` smoke test: launches in a subshell, asserts dashboard has all 6 fields, then `--stop` it
  - [ ] Plain-text degrade: `ALMANAC_NO_GUM=1 almanac converge <slug> --watch` produces parseable output
- [ ] `tests/test-structure.sh`, `tests/test-skills.sh`, and `tests/test-hub.sh` stay green.

## Notes

- The hub already handles the heavy lifting via the registry's uniform contract — most of this slice is small-glue. The big asks are: declare the loop adapter (`lib/loops/converge.sh`), wire `--watch` rendering, wire `--stop` signal writing.
- `--watch` should reuse the same redraw loop / styling primitives harden uses. If they're not yet extracted into a shareable lib helper, do not extract in this slice — open a separate refactor issue and inline the styling. Don't let extraction become a yak in this slice.
- `--stop` is the human's mirror of the overseer's STOP verdict. Same signal file, same handler. The loop driver doesn't care who wrote it.
- The "auto-discovered loop adapter" file (`lib/loops/converge.sh`) needs to follow the same shape as `lib/loops/ralph.sh` and `lib/loops/harden.sh`. Read them first, then mirror.
