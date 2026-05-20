---
name: prd-create
description: Use when turning a conversation or idea into docs/plans/<name>/prd.md. Synthesizes existing context into user stories, module design, testing decisions. Do NOT interview — just synthesize.
disable-model-invocation: true
metadata:
  upstream: mattpocock/skills/engineering/to-prd
  adapted-date: "2026-04-28"
---

Synthesize the current conversation context and codebase understanding into a PRD. Do NOT interview the user — just synthesize what you already know.

## Process

These commands run automatically when the skill loads — output replaces each line below:

- Current branch: !`git branch --show-current 2>/dev/null || true`
- CONTEXT.md: !`cat CONTEXT.md 2>/dev/null || true`

### 0. Determine `<name>` and load the brief

Before anything else:

1. If the user passed a name as an argument (e.g. `/prd-create auth-system`), use that as `<name>`.
2. Otherwise derive `<name>` from the current branch above by stripping a leading type prefix (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, `ci/`, `perf/`). Example: `feat/auth-system` → `auth-system`.
3. If on `main`/`master`/`develop` with no argument passed, ask the user for an explicit name before continuing.

Then load any existing brief from a previous grilling session:

```bash
cat docs/plans/<name>/brief.md 2>/dev/null || true
```

If that brief has content, those are decisions from a grilling session — use them. If `CONTEXT.md` content is present, use its vocabulary throughout the PRD. Also explore the repo to understand the current state of the codebase, if you haven't already.

1. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

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
