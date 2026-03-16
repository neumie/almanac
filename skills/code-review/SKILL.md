---
name: code-review
description: Use when reviewing code changes on the current branch for technical quality. Diffs against the base branch, reviews all changes for correctness, security, performance, readability, and test coverage, and produces a structured report. Use this when asked to review code, check a branch, audit changes, or provide technical feedback before merging.
---

# Code Review

Review all technical changes on the current branch. Understand intent before critiquing implementation.

## Phase 1 — Discovery

### Step 1: Detect the base branch

Try these in order:

1. **Check for a PR:** `gh pr view --json baseRefName -q '.baseRefName'`. If a PR exists, use its base branch.
2. **Try main:** `git rev-parse --verify origin/main 2>/dev/null`. If it exists, use `origin/main`.
3. **Try master:** `git rev-parse --verify origin/master 2>/dev/null`. If it exists, use `origin/master`.

Store the result as `<base>`.

### Step 2: Gather changes

Run these commands:

- `git log <base>..HEAD --oneline` — all commits on the branch
- `git diff <base>..HEAD --stat` — files changed summary
- `git diff <base>..HEAD` — full diff

Then **read every changed file in full** (not just diff hunks). Context reveals issues the diff hides.

### Step 3: Understand intent

- Read commit messages for the **why**
- Identify the scope: bug fix, feature, refactor, config change
- Note the domains and modules affected

## Phase 2 — Review

Apply the checklist to **ALL** changes on the branch, not just the latest commit.

### Correctness

- Does the code do what the commit messages say?
- Edge cases: empty input, null, boundary values, concurrent access
- Error paths: network failure, invalid data, timeout
- Conditional completeness: all branches covered?
- Off-by-one in loops or slices?
- Type safety: are types consistent at boundaries?

### Security

- User input validated and sanitized before use?
- Injection vectors: SQL, XSS, command injection
- Secrets hardcoded or logged?
- Permissions checked before sensitive operations?
- Dependencies: known vulnerabilities?

### Performance

- N+1 query patterns or unnecessary database calls?
- Unbounded operations at scale?
- Expensive computations cached when reused?
- Blocking operations that should be async?

### Readability

- Understandable without the PR description?
- Names descriptive and consistent with codebase?
- Logical organization? Related things together, clear flow?
- Complex sections commented with **why**, not **what**?

### Testing

- Tests for new or changed behavior?
- Happy path AND error case coverage?
- Behavior-focused, not implementation-focused?
- Regression test for bug fixes?

## Phase 3 — Report

Use this exact output structure:

```
# Code Review: <branch-name> vs <base-branch>

**Commits:** N | **Files changed:** N | **Insertions:** +N | **Deletions:** -N

## Blockers
[Issues that must be fixed before merge — bugs, security, data loss]

## Suggestions
[Improvements that would make the code better but are not blocking]

## Nits
[Style/preference, take it or leave it]

## Looks Good
[Acknowledge well-done aspects]
```

Each finding includes:

- **Category:** correctness / security / performance / readability / testing
- **Location:** `file_path:line`
- **Issue:** what's wrong (specific, not vague)
- **Why it matters:** the risk or consequence
- **Suggested fix:** concrete recommendation

### Guidelines

- Be specific. "This function is too complex" is useless. "This function has 4 nesting levels; extract the validation into a helper" is actionable.
- Acknowledge good work. If something is well-designed, say so.
- Review the full branch scope, not individual commits in isolation.
- Read files in full — context reveals issues the diff hides.
- Classify every finding: blocker, suggestion, or nit.

## Phase 4 — Save

Save the report to `.mine/context/code-review.md` using the Write tool. Create the `.mine/context/` directory first if it doesn't exist. Tell the user where the file was saved.
