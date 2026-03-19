---
name: interview-me
description: Use when stress-testing a plan, design, or architecture through relentless questioning. Walks down each branch of the decision tree, resolving dependencies one-by-one until reaching shared understanding. Use this whenever the user says interview me, grill me, challenge my design, or wants to pressure-test their thinking.
metadata:
  upstream: mattpocock/skills/grill-me
  upstream-sha: f1543a9113277dd442fc84fab929321703df1fc7
  adapted-date: "2026-03-19"
---

# Interview Me

Interview the user relentlessly about every aspect of their plan until reaching shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

## Rules

- For each question, provide your recommended answer
- If a question can be answered by exploring the codebase, explore the codebase instead of asking
- Don't accept vague answers — push for specifics
- Track which branches of the decision tree are resolved vs. open
- When all branches are resolved, summarize the final shared understanding
