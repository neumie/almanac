---
name: push
description: "Use when pushing commits to a remote. Checks tracking, shows what will be pushed, sets upstream if needed, handles diverged branches safely. Triggers: push, prepare for PR."
metadata:
  dependencies:
    - commit
---

# Push

Push the current branch to remote safely.

## Phase 1 — Analyze

### Step 1: Check current state and tracking

These commands run automatically when the skill loads — output replaces each line below:

- Working tree status: !`git status`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Tracking branch: !`git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true`
- Open PR: !`gh pr view --json number,title,url,state 2>/dev/null || true`

From the output:

- If there are uncommitted changes: commit your own in-scope work first (follow the `commit` skill) without asking. Warn about, and leave out of the push, only changes that are not yours or are unrelated to the task.
- Note the current branch name and recent commits
- If `@{u}` returned a tracking branch, note it
- If the tracking branch is not `origin/<current-branch>`, treat it like a mismatched upstream that must be repaired on push
- If `@{u}` was empty, upstream will be set on push
- If `gh pr view` returned an open PR, you'll update its description after pushing

### Step 3: Determine what will be pushed

- If tracking exists: `git log @{u}..HEAD --oneline` — unpushed commits
- If no tracking: `git log origin/main..HEAD --oneline` (or `origin/master`) — all branch commits

### Step 4: Safety checks

- **main/master branch:** Regular push is fine. Force-push is **NEVER** allowed — refuse and explain why.
- **Rewritten history after your own rebase or squash** (this session, not main/master): push without asking, using a lease pinned to the remote tip recorded before the rewrite (`<old-remote-tip>` from the rebase or commits-squash skill). This is safe only because that skill verified `<old-remote-tip>` was an ancestor of the pre-rewrite local tip; the lease then rejects the push if anyone pushed since. If it is rejected, stop and ask. If the branch does not exist on the remote, no force is needed: push normally with `-u`. If it exists on the remote but no tip was recorded before the rewrite, do not force-push: stop and ask.
- **Diverged branch** (not from your own rewrite): `git status` shows "diverged" — warn and suggest rebasing first (use the rebase skill).
- **Force-push requested:** Warn explicitly that this rewrites remote history. If target is main/master, **REFUSE**. For other branches, proceed only with `--force-with-lease` (never bare `--force`).

## Phase 2 — Execute

### Step 1: Push

- After your own rebase or squash of a pushed branch (see Step 4) — this takes precedence over the cases below: `git push -u --force-with-lease=<branch-name>:<old-remote-tip> origin HEAD:refs/heads/<branch-name>`
- If tracking is exactly `origin/<branch-name>`: `git push`
- If no tracking exists, or tracking points somewhere else such as `origin/main`: `git push -u origin HEAD:refs/heads/<branch-name>`
- If user confirmed force (non-main): `git push --force-with-lease`

### Step 2: Update PR description (if open PR exists)

After pushing, check if there's an open PR for this branch:

```bash
gh pr view --json number,title,url,state 2>/dev/null
```

If an **open** PR exists (state is `OPEN` — ignore `MERGED` or `CLOSED` PRs):

1. Gather the full branch content against the base:
   - `git log origin/<base>..HEAD --oneline` — all commits
   - `git diff origin/<base>..HEAD --stat` — files changed summary
   - `git diff origin/<base>..HEAD` — full diff for understanding
   - Read changed files for context
2. Generate an updated PR body using the same format as the `pr-create` skill:
   ```markdown
   ## Summary
   <1-3 bullet points describing what this PR does and why>

   ## Changes
   <grouped by logical feature, not by file>

   ## Test plan
   <bulleted checklist of how to verify the changes work>
   ```
3. Update the PR:
   ```bash
   gh pr edit <number> --body "$(cat <<'EOF'
   ...
   EOF
   )"
   ```
4. Also update the PR title if the scope of the branch has changed significantly.

If no PR exists, skip this step.

### Step 3: Verify

- Confirm push succeeded
- Report: **"Pushed N commits to origin/`<branch>`"**
- If PR was updated, report: **"Updated PR #N description"**

## Edge Cases

- **Nothing to push** (up to date): Report and stop.
- **Diverged branch:** Suggest rebase first. Do not force-push without explicit user request, except the lease-pinned push after your own rebase or squash (Step 4).
- **Push rejected** (non-fast-forward): If you just rebased or squashed, do not pull — use the lease-pinned push from Step 4. Otherwise explain the situation and suggest rebasing.
- **No remote configured:** Report error, suggest `git remote add origin <url>`.
- **Authentication failure:** Report and suggest checking credentials or SSH keys.
