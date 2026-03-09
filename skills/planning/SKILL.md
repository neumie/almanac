---
name: planning
description: Use when designing new features, breaking down large tasks, making architectural decisions, or planning implementation strategy. Guides structured exploration, trade-off analysis, and incremental implementation planning. Use this before jumping into any multi-step coding task.
---

# Architecture and Planning

Understand before you build. Explore before you change. Plan before you code.

## Process

### 1. Clarify Requirements

Before designing anything:
- What problem are we solving? (not "what feature are we adding")
- Who is affected? (users, other developers, CI, downstream services)
- What are the constraints? (time, compatibility, performance, tech stack)
- What does "done" look like? (acceptance criteria)
- What is explicitly out of scope?

### 2. Explore the Codebase

Before proposing changes, understand what exists:
- Find related code: search for similar features, patterns, utilities
- Trace the data flow: where does input come in, how is it transformed, where does output go?
- Identify the boundaries: what modules/services will this touch?
- Check for existing abstractions that can be reused
- Read recent changes in the affected areas: `git log --oneline -10 -- path/`

### 3. Evaluate Approaches

For any non-trivial change, consider 2-3 approaches:

| Criteria | Approach A | Approach B |
|----------|-----------|-----------|
| Complexity | How much new code? | |
| Risk | What could go wrong? | |
| Reversibility | How easy to undo? | |
| Dependencies | What does it touch? | |
| Testing | How do we verify? | |

Pick the approach that minimizes risk and complexity while meeting requirements. When in doubt, choose the more reversible option.

### 4. Sequence the Work

Break the chosen approach into ordered steps:

1. Each step should be independently testable and committable
2. Start with a vertical slice — one thin end-to-end path
3. Order by dependencies: foundational changes first
4. Identify what can be parallelized
5. Flag risks and unknowns for each step

### 5. Define Verification

For each step, specify how to verify it works:
- What test to run
- What to check manually
- What the expected output looks like
- How to roll back if it breaks

## Plan Format

```
## Goal
[One sentence: what we're building and why]

## Approach
[Which approach we chose and why]

## Steps
1. [Step] — [verification]
2. [Step] — [verification]
3. ...

## Risks
- [Risk] → [mitigation]

## Out of Scope
- [Thing we're explicitly not doing]
```

## Anti-Patterns

- **Planning without exploring**: designing in the abstract leads to solutions that don't fit the codebase
- **Over-planning**: if the plan is longer than the implementation will be, you've gone too far
- **No verification steps**: a plan without "how to check it works" is a wish list
- **Big bang**: prefer 5 small PRs over 1 large PR
