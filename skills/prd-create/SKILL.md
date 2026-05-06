---
name: prd-create
description: Use when turning a conversation or idea into plans/prd.md. Synthesizes existing context into user stories, module design, testing decisions. Do NOT interview — just synthesize.
metadata:
  upstream: mattpocock/skills/engineering/to-prd
  adapted-date: "2026-04-28"
---

Synthesize the current conversation context and codebase understanding into a PRD. Do NOT interview the user — just synthesize what you already know.

## Process

These commands run automatically when the skill loads — output replaces each line below:

- Existing brief: !`cat plans/brief.md 2>/dev/null || true`
- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`

1. If `Existing brief` content is present above, those are decisions from a grilling session — use them. If `CONTEXT.md` content is present, use its vocabulary throughout the PRD. Also explore the repo to understand the current state of the codebase, if you haven't already.

2. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

3. Derive a short kebab-case name for the PRD from the feature (e.g. `auth-system`, `dashboard-redesign`, `link-shortener`). Write the PRD using the template below and save it to `plans/<name>.md`:

```bash
mkdir -p plans
```

Report the file path so the user knows which PRD to pass to `/ralph-loop`.

## PRD Template

```markdown
## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

This list should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.
```
