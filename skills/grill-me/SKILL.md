---
name: grill-me
description: Use when stress-testing a plan, design, or architecture through relentless questioning. Walks down each branch of the decision tree, resolving dependencies one-by-one until reaching shared understanding. Writes decisions to plans/brief.md as they crystallize. Use this whenever the user says grill me, interview me, challenge my design, or wants to pressure-test their thinking.
metadata:
  upstream: mattpocock/skills/grill-me
  upstream-sha: f1543a9113277dd442fc84fab929321703df1fc7
  adapted-date: "2026-04-28"
---

# Grill Me

Interview the user relentlessly about every aspect of their plan until reaching shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

## Setup

Pre-run on skill load — output replaces the line below:

- Existing brief: !`cat plans/brief.md 2>/dev/null || true`

If the content is present above, you're continuing a previous grilling session — acknowledge what's already decided and pick up from open questions. If empty, this is a fresh session.

```bash
mkdir -p plans
```

## Rules

- For each question, provide your recommended answer
- If a question can be answered by exploring the codebase, explore the codebase instead of asking
- Don't accept vague answers — push for specifics
- Track which branches of the decision tree are resolved vs. open
- Ask one question at a time, wait for the answer before continuing

## Writing the Brief

After each decision is resolved, update `plans/brief.md` immediately. Don't batch — capture as you go.

Use the format in `${CLAUDE_SKILL_DIR}/references/brief-format.md`.

## Finishing

When all branches are resolved (no open questions remain), update `plans/brief.md` one final time and tell the user:

```
Grilling complete. Brief saved to plans/brief.md.
Next step: /prd-create
```
