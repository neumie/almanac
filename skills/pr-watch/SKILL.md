---
name: pr-watch
description: Use when waiting for CI checks on a pull request. Watches check status, auto-fixes failures via ci-fix (max 2 attempts), and reports when done with a suggested merge command. Use this whenever the user says watch PR, watch CI, wait for checks, or wants to monitor a PR until it's ready to merge.
---

# PR Watch

Watch a PR's CI checks until they complete. If checks fail, attempt to fix them automatically. Report the result with a suggested next step.

## Detect the PR

If the user provides a PR number, use it. Otherwise detect from the current branch:

```bash
gh pr view --json number,title,url,state,headRefName
```

If no PR exists or state is not `OPEN`, stop and report.

## Watch Checks

Run:

```bash
gh pr checks --watch --interval 30
```

This blocks until all checks complete.

## Evaluate Results

After checks finish, get the full status:

```bash
gh pr checks --json name,state,conclusion
```

### All checks passed

Report and suggest merge:

```
Watching PR #42 (feat/add-tdd-and-test-write-skills)...
  CI: 5/5 passed

Result: All checks passed
Ready to merge: gh pr merge #42 --squash --delete-branch
```

### Some checks failed (fix attempts remaining)

If this is the 1st or 2nd failure, attempt an automatic fix:

1. Identify the failing checks from the output
2. Run the ci-fix workflow:
   - Fetch the failing run logs
   - Read the error output
   - Find and fix the root cause in the code
   - Commit and push the fix
3. Re-watch: run `gh pr checks --watch --interval 30` again

Track fix attempts. Maximum 2 fix attempts total.

```
Watching PR #42...
  CI: 1/5 failed (test-unit)
  Running ci-fix... fixed and pushed
  Re-watching...
  CI: 5/5 passed

Result: All checks passed (1 fix applied)
Ready to merge: gh pr merge #42 --squash --delete-branch
```

### Some checks failed (no fix attempts remaining)

If 2 fix attempts have been made and checks still fail, stop and report:

```
Watching PR #42...
  CI: 1/5 failed (test-unit)
  Running ci-fix... fixed and pushed (attempt 1)
  Re-watching...
  CI: 1/5 failed (test-unit)
  Running ci-fix... fixed and pushed (attempt 2)
  Re-watching...
  CI: 1/5 failed (test-unit)

Result: 1/5 checks still failing after 2 fix attempts
  FAIL: test-unit
Needs manual investigation.
```

## Rules

- Never merge the PR — only report and suggest
- Maximum 2 ci-fix attempts to prevent infinite loops
- If ci-fix itself fails (can't identify the issue), stop and report immediately
- Each fix attempt gets its own commit (never amend)
- If the PR is closed or merged while watching, stop and report the new state
