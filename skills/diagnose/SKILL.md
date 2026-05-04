---
name: diagnose
description: Use when debugging hard bugs or performance regressions. Disciplined loop — reproduce, minimise, hypothesise, instrument, fix, regression-test. Use this whenever the user says diagnose, debug this, something is broken/throwing/failing, or reports a performance regression.
metadata:
  upstream: mattpocock/skills/engineering/diagnose
  upstream-sha: 49cec7be019bc408e87b77670f3d442f536da254
  adapted-date: "2026-04-28"
---

# Diagnose

Discipline for hard bugs. Skip phases only when explicitly justified.

Domain context runs automatically when the skill loads — output replaces each line below:

- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`
- ADR list: !`ls docs/adr/ 2>/dev/null || true`

If `CONTEXT.md` content is present above, use that vocabulary. If `ADR list` showed files, read the relevant ones before exploring the codebase. If both were empty, proceed silently.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. Fast, deterministic, agent-runnable pass/fail signal for the bug → you will find the cause. Without one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try roughly in this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with fixture input, diffing stdout against known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) — drives UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay through code path in isolation.
6. **Throwaway harness.** Spin up minimal subset of system (one service, mocked deps) that exercises bug code path with single fn call.
7. **Property / fuzz loop.** If bug is "sometimes wrong output", run 1000 random inputs and look for failure mode.
8. **Bisection harness.** If bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run same input through old-version vs new-version (or two configs) and diff outputs.
10. **HITL bash script.** Last resort. If human must click, drive _them_ with `${CLAUDE_SKILL_DIR}/scripts/hitl-loop.template.sh` so loop is still structured. Captured output feeds back to you.

Build the right feedback loop → bug is 90% fixed.

### Iterate on the loop itself

Treat loop as product. Once you have _a_ loop, ask:

- Can I make it faster? (Cache setup, skip unrelated init, narrow test scope.)
- Can I make signal sharper? (Assert on specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

30-second flaky loop ≈ no loop. 2-second deterministic loop = debugging superpower.

### Non-deterministic bugs

Goal is not clean repro but **higher reproduction rate**. Loop trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. 50%-flake bug is debuggable; 1% is not — keep raising rate until debuggable.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask user for: (a) access to whatever environment reproduces it, (b) captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

Do not proceed to Phase 2 until you have a loop you believe in.

## Phase 2 — Reproduce

Run the loop. Watch bug appear.

Confirm:

- [ ] Loop produces failure mode **user** described — not a different failure nearby. Wrong bug = wrong fix.
- [ ] Failure reproducible across multiple runs (or, for non-deterministic bugs, at high enough rate to debug against).
- [ ] Exact symptom captured (error message, wrong output, slow timing) so later phases can verify fix addresses it.

Do not proceed until you reproduce the bug.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any. Single-hypothesis generation anchors on first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make bug disappear / <changing Z> will make it worse."

Can't state prediction → hypothesis is a vibe — discard or sharpen.

**Show ranked list to user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses already ruled out. Cheap checkpoint, big time saver. Don't block on it — proceed with your ranking if user is AFK.

## Phase 4 — Instrument

Each probe must map to specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at end becomes single grep. Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs usually wrong. Instead: establish baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix + regression test

Write regression test **before the fix** — but only if there is a **correct seam** for it.

Correct seam = test exercises **real bug pattern** as it occurs at call site. If only available seam is too shallow (single-caller test when bug needs multiple callers, unit test that can't replicate trigger chain), regression test there gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it. Codebase architecture prevents bug from being locked down. Flag for next phase.

If correct seam exists:

1. Turn minimised repro into failing test at that seam.
2. Watch it fail.
3. Apply fix.
4. Watch it pass.
5. Re-run Phase 1 feedback loop against original (un-minimised) scenario.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run Phase 1 loop)
- [ ] Regression test passes (or absence of seam documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to clearly-marked debug location)
- [ ] Hypothesis that turned out correct stated in commit / PR message — so next debugger learns

**Then ask: what would have prevented this bug?** If answer involves architectural change (no good test seam, tangled callers, hidden coupling) hand off to the `codebase-improve` skill with specifics. Make recommendation **after** fix is in, not before — you have more information now than when you started.
