---
name: prototype-build
description: Use when building throwaway logic or UI prototypes to answer design questions before production implementation; shareable HTML state demos or UI variants.
metadata:
  upstream: mattpocock/skills/skills/engineering/prototype
  upstream-sha: a0044501fe0d385b4d8575b610188ede9b236ccf
  adapted-date: "2026-09-07"
---

# Prototype Build

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick A Branch

Identify the question from the prompt, nearby code, or by asking if the user is around:

- **Logic / state model question**: read [logic.md](references/logic.md). Build a single shareable HTML file with free-play buttons and tabbed guided walkthroughs that let non-developers push state through hard cases.
- **UI shape question**: read [ui.md](references/ui.md). Generate radically different UI variants in parallel, with one subagent per variant, switchable from one route.

If ambiguous and user is unavailable, default to the branch matching surrounding code: backend module means logic; page/component means UI. State the assumption at the top of the prototype.

## Rules

1. **Throwaway from day one.** Place code near where it informs real work, but name it so readers know it is a prototype.
2. **Trivial to run.** A logic demo is one HTML file the user double-clicks, with no server or install. A UI prototype uses one command in the project's existing task runner. Do not add a package manager or runtime just for the prototype.
3. **No persistence by default.** State lives in memory unless persistence is the question.
4. **Skip polish.** No tests, no broad error handling, no abstractions beyond what makes it runnable.
5. **Surface state.** After every logic action or UI variant switch, show the relevant state.
6. **Delete or absorb when done.** Keep the decision, not the prototype shell. Do not preserve a prototype-only branch.

## When Done

Capture the answer somewhere durable: commit message, ADR, issue, or `NOTES.md` beside the prototype. Include the question it answered. Then delete the prototype or fold the validated part into real code.
