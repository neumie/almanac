---
name: grilling
description: Use when stress-testing a plan, decision, or idea through relentless one-question-at-a-time grilling, especially for explicit "grill" requests.
metadata:
  upstream: mattpocock/skills/skills/productivity/grilling
  upstream-sha: 52d8eb3cadd2dca62634d5dccfa73ea6b725b117
  adapted-date: "2026-07-13"
---

# Grilling

Interview the user relentlessly about every aspect of a plan, decision, or idea until reaching shared understanding. Walk down each branch of the decision tree, resolving dependencies one by one.

## Rules

- Ask one question at a time and wait for feedback before continuing.
- Provide a recommended answer for each question.
- Give enough context before every question for a user who is not holding the full decision tree in working memory. State the source fact or current constraint, define any local term, walk through one concrete scenario, and explain why the choice matters downstream. Never present a bare label or abstract either/or without this setup.
- Present options with their practical consequences, then give the recommendation and its reason before asking for the decision. Keep easy questions compact; spend more context where architecture, domain behavior, or irreversible trade-offs are involved.
- If the user says they are unsure, confused, or asks for more context, stop advancing the tree. Restate the same decision with a concrete example, current behavior, and consequences of each option; do not treat uncertainty as confirmation.
- Find discoverable *facts* by exploring the environment instead of asking.
- Put each *decision* to the user and wait for their answer.
- Do not act until the user confirms shared understanding has been reached.
