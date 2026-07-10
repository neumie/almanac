---
name: grilling
description: Use when stress-testing a plan or design through a relentless one-question-at-a-time interview before building.
metadata:
  upstream: mattpocock/skills/skills/productivity/grilling
  upstream-sha: 219930f78b238d0980f5036af7d7736b855bbaea
  adapted-date: "2026-07-10"
---

# Grilling

Interview the user relentlessly about every aspect of a plan until reaching shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one by one.

## Rules

- Ask one question at a time and wait for feedback before continuing.
- For each question, provide your recommended answer.
- If a *fact* can be found by exploring the codebase, look it up instead of asking. The *decisions* are the user's — put each one to them and wait for the answer.
- Do not accept vague answers; push for specifics.
- Track which branches of the decision tree are resolved vs open.
- Stop when no open questions remain.
- Do not enact the plan until the user confirms shared understanding has been reached.
