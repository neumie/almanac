---
name: tdd
description: "Use when writing code test-first via the red-green loop. Vertical-slice TDD at pre-agreed seams: one failing test, then minimal code to pass. Triggers: TDD, test-first, red-green."
metadata:
  dependencies:
    - codebase-design
  upstream: mattpocock/skills/skills/engineering/tdd
  upstream-sha: 9a2e1d2a1ad856b0d5903dd002209ff8c32c9a48
  adapted-date: "2026-07-10"
---

# Test-Driven Development

TDD is the red -> green loop. This skill is the reference that makes that loop produce tests worth keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop. Every section applies on every cycle — consult them before and during the loop, not after.

When exploring the codebase, use `CONTEXT.md` vocabulary (if it exists) so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching.

## What A Good Test Is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification — "user can checkout with valid cart" tells you exactly what capability exists — and survives refactors because it doesn't care about internal structure.

See `~/.claude/skills/almanac/tdd/references/tests.md` for examples and `~/.claude/skills/almanac/tdd/references/mocking.md` for mocking guidelines.

## Seams — Where Tests Go

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals. Follow the `codebase-design` skill for seam, interface, and deep-module vocabulary.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything — agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Ask: "What's the public interface, and which seams should we test?"

## Anti-Patterns

- **Implementation-coupled** — mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behavior hasn't changed.
- **Tautological** — the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth — a known-good literal, a worked example, the spec.
- **Horizontal slicing** — writing all tests first, then all implementation. Bulk tests verify _imagined_ behavior: you test the _shape_ of things rather than user-facing behavior, the tests go insensitive to real changes, and you commit to test structure before understanding the implementation. Work in **vertical slices** instead — one test -> one implementation -> repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Rules Of The Loop

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to the review stage after the cycles are done, not the red -> green implementation cycle. When you get there, see `~/.claude/skills/almanac/tdd/references/refactoring.md` for candidates. Never refactor while RED.
