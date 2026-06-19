---
name: prototype-build
description: Use when building throwaway logic or UI prototypes to answer design questions before production implementation; terminal state app or UI variants.
metadata:
  upstream: mattpocock/skills/skills/engineering/prototype
  upstream-sha: ddebc187ed68bae0e90f3aa6dab3f9a8740ced3a
  adapted-date: "2026-06-19"
---

# Prototype Build

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick A Branch

Identify the question from the prompt, nearby code, or by asking if the user is around:

- **Logic / state model question**: read `~/.claude/skills/almanac/prototype-build/references/logic.md`. Build a tiny interactive terminal app that pushes state through hard cases.
- **UI shape question**: read `~/.claude/skills/almanac/prototype-build/references/ui.md`. Generate several radically different UI variants switchable from one route.

If ambiguous and user is unavailable, default to the branch matching surrounding code: backend module means logic; page/component means UI. State the assumption at the top of the prototype.

## Rules

1. **Throwaway from day one.** Place code near where it informs real work, but name it so readers know it is a prototype.
2. **One command to run.** Use the project's existing task runner. Do not add a package manager or runtime just for the prototype.
3. **No persistence by default.** State lives in memory unless persistence is the question.
4. **Skip polish.** No tests, no broad error handling, no abstractions beyond what makes it runnable.
5. **Surface state.** After every logic action or UI variant switch, show the relevant state.
6. **Delete or absorb when done.** Keep the decision, not the prototype shell.

## When Done

Capture the answer somewhere durable: commit message, ADR, issue, or `NOTES.md` beside the prototype. Include the question it answered. Then delete the prototype or fold the validated part into real code.
