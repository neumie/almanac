---
name: grill-me
description: Use when stress-testing a plan, design, or architecture through relentless questioning. Walks each branch of the decision tree one question at a time; hand the resolved decisions to /prd-create to persist.
disable-model-invocation: true
metadata:
  dependencies:
    - grilling
  upstream: mattpocock/skills/skills/productivity/grill-me
  upstream-sha: 9470cfcfe231a35e46494cddbacdd395991afb1e
  adapted-date: "2026-06-19"
---

# Grill Me

Run the interactive interview using the `grilling` skill: walk every branch of the
decision tree, one question at a time, until no open questions remain.

Keep the crystallized decisions in the conversation — do **not** write a file. The
decisions live in this session; `/prd-create` synthesizes them into the PRD.

## Finishing

When all branches are resolved (no open questions remain), tell the user:

```
Grilling complete. Next step: /prd-create — it synthesizes these decisions into docs/plans/<name>/prd.md.
```
