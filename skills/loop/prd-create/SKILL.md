---
name: prd-create
description: Use when turning a conversation or idea into docs/plans/<name>/prd.md. Synthesizes existing context into user stories, module design, testing decisions. Do NOT interview — just synthesize.
disable-model-invocation: true
metadata:
  dependencies:
    - codebase-design
  upstream: mattpocock/skills/skills/engineering/to-prd
  upstream-sha: e5f11413b09c19f59150dac52125536ccda34e2d
  adapted-date: "2026-06-19"
---

Synthesize the current conversation context and codebase understanding into a PRD. Do NOT interview the user — just synthesize what you already know.

## Process

These commands run automatically when the skill loads — output replaces each line below:

- Current branch: !`git branch --show-current 2>/dev/null || true`
- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`

### 0. Determine `<name>`

Before anything else:

1. If the user passed a name as an argument (e.g. `/prd-create auth-system`), use that as `<name>`.
2. Otherwise derive `<name>` from the current branch above by stripping a leading type prefix (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, `ci/`, `perf/`). Example: `feat/auth-system` → `auth-system`.
3. If on `main`/`master`/`develop` with no argument passed, ask the user for an explicit name before continuing.

If this session included a `/grill-me` grilling, those crystallized decisions are in the conversation — use them. If `CONTEXT.md` content is present, use its vocabulary throughout the PRD. Respect ADRs in the area you're touching. Also explore the repo to understand the current state of the codebase, if you haven't already.

1. Sketch out the seams where the feature should be tested. Prefer existing seams to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. Fewer seams are better; one seam is ideal.

Also sketch the major modules you will need to build or modify to complete the implementation. Follow the `codebase-design` skill for seam, interface, and deep-module vocabulary.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

2. Write the PRD using the template below and save it to `docs/plans/<name>/prd.md`:

```bash
mkdir -p docs/plans/<name>
```

Report the file path (`docs/plans/<name>/prd.md`) so the user knows which PRD to pass to `/ralph-loop`.

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

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo.

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
