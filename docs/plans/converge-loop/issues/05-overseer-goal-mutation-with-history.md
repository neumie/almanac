---
title: Overseer goal mutation with audit log
status: open
type: AFK
blocked-by: [04-overseer-verdict-steer-stop]
user-stories: [9]
---

## What to build

Wire the `GOAL_UPDATE` field of the overseer verdict (specified in slice 04 but inert there) so the overseer can rewrite `goal.md` between rounds. Every mutation appends a structured entry to `goal.history.log` with the tick number, the overseer's reason, and a before/after diff. The next round's worker reads the new `goal.md` via the prompt template from slice 03 — no special handoff needed.

This is the slice that delivers user story 9: a steerable goal that evolves visibly without human intervention.

## Acceptance criteria

- [ ] On overseer verdict, if `GOAL_UPDATE` is not `unchanged`:
  - [ ] The new content is written to `goal.md` (full replace; not a diff/patch — the overseer is responsible for outputting the complete new goal)
  - [ ] An entry is appended to `goal.history.log` with the exact format:
    ```
    ===== tick=<N> ts=<ISO> overseer=<provider> =====
    REASON: <verdict.reason copied verbatim>
    --- DIFF ---
    <unified diff of old goal.md → new goal.md>
    ```
- [ ] If `GOAL_UPDATE` equals `unchanged` (or is missing — conservative parse from slice 04), `goal.md` is **untouched** and `goal.history.log` is **not** appended.
- [ ] The diff is generated via `diff -u <old> <new>` (POSIX standard); if `diff` is absent, the entry omits `--- DIFF ---` and includes the full new content as `--- AFTER ---` (graceful degrade — almanac's zero-dependency promise).
- [ ] `overseer.log` records the goal mutation tick with a one-line summary: `[tick=<N>] goal updated: <first 80 chars of new goal.md>`.
- [ ] Worker iteration prompt (slice 03) re-reads `goal.md` at the start of every round, so the mutated goal takes effect on the next round with zero plumbing — verify in tests by asserting the prompt of round N+1 contains the new goal text.
- [ ] `tests/test-converge.sh` adds:
  - [ ] `GOAL_UPDATE: <new text>` overwrites `goal.md`
  - [ ] `GOAL_UPDATE: unchanged` leaves `goal.md` byte-identical
  - [ ] `goal.history.log` entry format matches the schema above (header + REASON + DIFF)
  - [ ] Successive goal updates accumulate in `goal.history.log` in chronological order
  - [ ] Round N+1's worker prompt contains the new goal text (end-to-end propagation)
  - [ ] `diff` command absence falls back gracefully (mock $PATH; assert `--- AFTER ---` block instead of `--- DIFF ---`)
- [ ] `tests/test-structure.sh` and `tests/test-skills.sh` stay green.

## Notes

- The overseer outputs the **complete new goal.md**, not a patch. This is the cleaner contract: the LLM produces text, we write text. Patches are fragile against whitespace and line-ending drift.
- `goal.history.log` is **append-only** — no rewriting, no compaction. If it grows large, that's a signal the loop is churning the goal too much (which is itself worth seeing).
- The first goal (from `--goal` at launch) is **not** logged to `goal.history.log` — that file records *mutations*, and the initial value is the baseline. The initial `goal.md` content IS the baseline.
- Be careful with very long `GOAL_UPDATE` values from the overseer — bound the parser at slice 04 to handle multi-line content (the verdict format already allows it since `GOAL_UPDATE` is the last field; everything after the `GOAL_UPDATE:` marker through EOF is the content).
- An overseer that mutates goal AND emits STEER in the same tick: apply both. The next round sees the new goal AND the `.converge-steer` directive. This is fine — they're orthogonal handles on the next round.
