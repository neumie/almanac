---
name: code-review
description: Use when reviewing pull requests, diffs, or code changes. Provides structured review focusing on correctness, security, performance, and maintainability. Use this whenever asked to review code, check a PR, or provide feedback on changes.
---

# Code Review

Review code changes systematically. Understand intent before critiquing implementation.

## Before Reading Code

1. Read the PR description / commit message — understand **why** this change exists
2. Check the scope — is this a bug fix, feature, refactor, or config change?
3. Note the files changed and their domains

## Review Checklist

### Correctness

- Does the code do what the description says it does?
- Are edge cases handled? (empty input, null, boundary values, concurrent access)
- Are error paths handled? (network failure, invalid data, timeout)
- Do new conditions cover all branches? (if/else completeness)
- Are off-by-one errors possible in loops or slices?

### Security

- Is user input validated and sanitized before use?
- Are there SQL injection, XSS, or command injection vectors?
- Are secrets hardcoded or logged?
- Are permissions/authorization checked before sensitive operations?
- Are dependencies up to date and free of known vulnerabilities?

### Performance

- Are there N+1 query patterns or unnecessary database calls?
- Could any operation be unexpectedly slow at scale? (unbounded loops, large allocations)
- Are expensive computations cached when the result is reused?
- Are there blocking operations that should be async?

### Readability

- Can you understand the code without the PR description?
- Are names descriptive and consistent with the codebase?
- Is the code organized logically? (related things together, clear flow)
- Are complex sections commented with **why**, not **what**?

### Testing

- Are there tests for the new/changed behavior?
- Do tests cover happy path AND error cases?
- Are tests testing behavior, not implementation?
- If this is a bug fix, is there a regression test?

## Giving Feedback

Classify each comment:
- **Blocker** — must be fixed before merge (bugs, security issues, data loss risks)
- **Suggestion** — would improve the code but not blocking (better naming, simpler approach)
- **Nit** — style/preference, take it or leave it

Be specific. Instead of "this could be better", say what and why:
- Bad: "This function is too complex"
- Good: "This function has 4 levels of nesting. Extract the inner validation into a helper — it would make the happy path clearer"

Acknowledge good work. If something is well done, say so.
