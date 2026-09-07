---
name: grilling
description: Use when stress-testing a plan, decision, or idea through dependency-aware rounds of grilling, especially for explicit "grill" requests.
metadata:
  upstream: mattpocock/skills/skills/productivity/grilling
  upstream-sha: 8ca78c6d8f901aab0c5a1f896034b70e666ff2a3
  adapted-date: "2026-09-07"
---

# Grilling

Interview the user about every aspect of a plan, decision, or idea until reaching shared understanding. Map it as a **design tree**: each decision branches into decisions that depend on it.

## Work In Rounds

The **frontier** contains decisions whose prerequisites are settled. Ask the independent questions on that frontier together, number each question, and provide a recommended answer with its reason. Wait for the user's answers before advancing to the next round.

A question that depends on another unanswered question belongs to a later round. Recompute the frontier after each response; revisit downstream decisions if an earlier answer changes. If the host question tool limits batch size, split the frontier into supported batches without guessing answers. Honor a user's request for one question at a time.

Find discoverable facts by exploring the environment, not by asking the user. Delegate independent fact-finding to read-only sub-agents when available and useful; otherwise look it up directly. A pending exploration is an unsettled prerequisite: ask unrelated frontier questions while it runs, but defer questions that depend on its result.

## Question Quality

- Provide a recommended answer for each question.
- Give enough context before every question for a user who is not holding the full decision tree in working memory. State the source fact or current constraint, define any local term, walk through one concrete scenario, and explain why the choice matters downstream. Never present a bare label or abstract either/or without this setup.
- Present options with their practical consequences, then give the recommendation and its reason before asking for the decision. Keep easy questions compact; spend more context where architecture, domain behavior, or irreversible trade-offs are involved.
- If the user says they are unsure, confused, or asks for more context, stop advancing the tree. Restate the same decision with a concrete example, current behavior, and consequences of each option; do not treat uncertainty as confirmation.
- Put each *decision* to the user and wait for their answer. Do not fill unanswered decisions with your recommendation.

## Finish

The interview is complete only when every branch has been visited and the frontier is empty, with no unanswered decisions, pending fact-finding, or silent assumptions. Summarize the resolved decisions and wait for the user to confirm shared understanding before acting on the plan.
