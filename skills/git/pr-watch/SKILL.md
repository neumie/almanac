---
name: pr-watch
description: "Use when waiting for CI checks on a PR. Watches status, auto-fixes failures via ci-fix (max 2 retries), reports merge-ready. Triggers: watch PR, watch CI, wait for checks."
metadata:
  dependencies:
    - ci-fix
---

# PR Watch

Watch a PR's CI checks until they complete. If checks fail, attempt to fix them automatically. Report the result with a suggested next step.

Every merge-ready command in this skill must resolve `<method-api>` from repository settings using **Merge Method Detection** below. Never print the placeholder literally.

## Detect the PR and CI

These commands run automatically when the skill loads — output replaces each line below:

- PR for current branch: !`gh pr view --json number,title,url,state,headRefName 2>/dev/null || true`
- Workflow count: !`gh api repos/{owner}/{repo}/actions/workflows --jq '.total_count' 2>/dev/null || true`

If the user provides a PR number, use that instead of the detected one.

If no PR exists or state is not `OPEN`, stop and report.

## Check for CI

If the workflow count is 0, report and suggest merge:

```
No CI workflows configured — nothing to watch.
Ready to merge: gh api repos/{owner}/{repo}/pulls/42/merge -X PUT -f merge_method=<method-api>
```

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
Ready to merge: gh api repos/{owner}/{repo}/pulls/42/merge -X PUT -f merge_method=<method-api>
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
Ready to merge: gh api repos/{owner}/{repo}/pulls/42/merge -X PUT -f merge_method=<method-api>
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

- Never merge the PR automatically during watching — only report and suggest
- Maximum 2 ci-fix attempts to prevent infinite loops
- If ci-fix itself fails (can't identify the issue), stop and report immediately
- Each fix attempt gets its own commit (never amend)
- If the PR is closed or merged while watching, stop and report the new state

## Merge Procedure

When the user asks to merge after watching:

### Merge Method Detection

Query repository settings before suggesting or performing a merge:

```bash
gh api repos/{owner}/{repo} --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}'
```

Map enabled methods to API values:

| Setting | API value |
| --- | --- |
| `merge: true` | `merge` |
| `squash: true` | `squash` |
| `rebase: true` | `rebase` |

- If the user explicitly requested a method, use it only when enabled. Otherwise stop and list enabled methods.
- If exactly one method is enabled, use it.
- If multiple methods are enabled and the user did not choose one, ask. Never infer a global preference.
- If no method is enabled or the settings query fails, stop and report the error.

Record the selected `<method-api>`.

### Execute

Use the GitHub API, not `gh pr merge --delete-branch`. The latter can delete the local branch and switch the current worktree to its base branch.

1. Record the PR's head branch before merging:
   ```bash
   gh pr view <number> --json headRefName --jq .headRefName
   ```
2. Merge via API using the detected method:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/merge -X PUT -f merge_method=<method-api>
   ```
3. Even if the merge command reports an error, check whether the PR merged:
   ```bash
   gh pr view <number> --json state,mergedAt,headRefName
   ```
4. If the PR is not merged, stop and report the API error. Do not delete any branch.
5. Delete only the remote head branch after confirming the PR is merged. A missing branch means cleanup already succeeded:
   ```bash
   if gh api repos/{owner}/{repo}/git/ref/heads/<branch> --silent 2>/dev/null; then
     gh api repos/{owner}/{repo}/git/refs/heads/<branch> -X DELETE
   fi
   ```
6. Verify the PR state is `MERGED` and report the method used. Leave the local branch and current worktree unchanged.
