---
name: grill-me
description: Use when stress-testing a plan, design, or architecture before writing a spec. Keeps resolved decisions in the conversation for spec-create.
metadata:
  dependencies:
    - grilling
  upstream: mattpocock/skills/skills/productivity/grill-me
  upstream-sha: 3947ff9c4ad980d14fc07fccbf659d47c114e81d
  adapted-date: "2026-09-07"
---

# Grill Me

Follow the `grilling` skill for the interactive interview, dependency-aware question rounds, and the user's confirmation of shared understanding.

Keep the crystallized decisions in the conversation — do **not** write a file. The
decisions live in this session; `/spec-create` synthesizes them into the spec.

## Finishing

After all branches are resolved and the user confirms shared understanding, tell the user:

```text
Grilling complete. Next step: /spec-create — it synthesizes these decisions into docs/plans/<name>/spec.md.
```
