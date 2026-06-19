---
name: grill-with-docs
description: Use when stress-testing a plan against the existing domain model + decisions. Challenges terminology, cross-references code, updates CONTEXT.md and ADRs inline as decisions crystallize.
disable-model-invocation: true
metadata:
  dependencies:
    - grilling
    - domain-model
  upstream: mattpocock/skills/skills/engineering/grill-with-docs
  upstream-sha: bed05d2bd3245306267cea57cd696b5dd94d50fe
  adapted-date: "2026-06-19"
---

Use the `grilling` skill for the interview loop. Use the `domain-model` skill to maintain domain language and ADRs as decisions crystallize.

## Domain awareness

These commands run automatically when the skill loads — output replaces each line below:

- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`
- CONTEXT-MAP.md: !`cat CONTEXT-MAP.md 2>/dev/null || true`
- ADR list: !`ls docs/adr/ 2>/dev/null || true`

Use the output above:

- **`CONTEXT.md`** — glossary of domain terms. If content is in context, use its vocabulary in all output. If empty, create one when the first term is resolved.
- **`CONTEXT-MAP.md`** — if content is in context, the repo has multiple bounded contexts. The map points to where each one lives.
- **`docs/adr/`** — architecture decision records. If files were listed, read the relevant ones. Create the directory when the first ADR is needed.

## During the session

Follow the `grilling` skill for question order, recommendations, specificity, and code exploration.

Follow the `domain-model` skill for glossary challenges, fuzzy-term sharpening, scenario stress tests, code cross-checks, `CONTEXT.md` updates, and ADR creation rules.
