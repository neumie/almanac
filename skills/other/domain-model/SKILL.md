---
name: domain-model
description: Use when pinning down domain terms, ubiquitous language, CONTEXT.md glossary entries, ADRs, or when another skill needs domain-model maintenance.
metadata:
  upstream: mattpocock/skills/skills/engineering/domain-modeling
  upstream-sha: d0f7e1a5ccb06a7184056ff9af02b67bc77f9dda
  adapted-date: "2026-06-19"
---

# Domain Model

Build and sharpen a project's domain model as design work happens. This is active work: challenge terms, invent edge-case scenarios, cross-check code, and write the glossary or ADR once a decision crystallizes.

Reading `CONTEXT.md` for vocabulary is a habit any skill can do. Use this skill when the model changes.

## File Structure

Most repos have one context:

```text
/
  CONTEXT.md
  docs/
    adr/
      0001-event-sourced-orders.md
```

Multi-context repos use `CONTEXT-MAP.md` at the root. It points to each context's `CONTEXT.md` and local ADR directory.

Create files lazily. If no `CONTEXT.md` exists, create one only when the first term is resolved. If no `docs/adr/` exists, create it only when the first ADR is needed.

## During The Session

### Challenge Against Glossary

When the user uses a term that conflicts with `CONTEXT.md`, call it out immediately:

> `CONTEXT.md` defines "cancellation" as X, but you seem to mean Y. Which is it?

### Sharpen Fuzzy Language

When the user uses vague or overloaded terms, propose a precise canonical term:

> You said "account"; do you mean Customer or User? Those are different concepts here.

### Discuss Concrete Scenarios

Stress-test relationships with concrete scenarios. Use edge cases to force precise boundaries between concepts.

### Cross-Reference Code

When the user states how something works, check whether code agrees. If code contradicts the statement, surface the mismatch and ask which source should win.

### Update CONTEXT.md Inline

When a term is resolved, update `CONTEXT.md` immediately. Do not batch. Use `~/.claude/skills/almanac/domain-model/references/context-format.md`.

`CONTEXT.md` is a glossary, not a spec, scratchpad, or implementation note. Keep implementation details out.

### Offer ADRs Sparingly

Offer an ADR only when all three are true:

1. **Hard to reverse**: changing later has real cost.
2. **Surprising without context**: future readers will wonder why.
3. **Real trade-off**: there were genuine alternatives.

If any are missing, skip the ADR. Use `~/.claude/skills/almanac/domain-model/references/adr-format.md`.
