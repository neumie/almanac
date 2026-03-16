---
name: push
description: Use when pushing commits to a remote repository. Checks branch tracking, shows what will be pushed, sets upstream if needed, and handles diverged branches safely. Use this whenever the user says push, wants to send their work to the remote, or is preparing for a PR.
---

# Push

Push the current branch to remote safely.

## Phase 1 — Analyze

### Step 1: Check current state

- `git status` — warn if there are uncommitted changes (dirty working tree)
- `git branch --show-current` — get the current branch name
- `git log --oneline -5` — see recent commits

### Step 2: Check remote tracking

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

- If a tracking branch exists, note it
- If no tracking branch, note that upstream will be set on push

### Step 3: Determine what will be pushed

- If tracking exists: `git log @{u}..HEAD --oneline` — unpushed commits
- If no tracking: `git log origin/main..HEAD --oneline` (or `origin/master`) — all branch commits

### Step 4: Safety checks

- **main/master branch:** Regular push is fine. Force-push is **NEVER** allowed — refuse and explain why.
- **Diverged branch:** `git status` shows "diverged" — warn and suggest rebasing first (use the rebase skill).
- **Force-push requested:** Warn explicitly that this rewrites remote history. If target is main/master, **REFUSE**. For other branches, proceed only with `--force-with-lease` (never bare `--force`).

## Phase 2 — Confirm

Present to the user:

- **Branch:** `<branch-name>`
- **Remote target:** `origin/<branch-name>`
- **Commits to push:** count and list (oneline)
- **Warnings:** diverged, dirty tree, force-push implications
- Ask: **"Push these N commits to origin/`<branch>`?"**

Wait for confirmation.

## Phase 3 — Execute

### Step 1: Push

- If tracking exists: `git push`
- If no tracking: `git push -u origin <branch-name>`
- If user confirmed force (non-main): `git push --force-with-lease`

### Step 2: Verify

- Confirm push succeeded
- Report: **"Pushed N commits to origin/`<branch>`"**

## Edge Cases

- **Nothing to push** (up to date): Report and stop.
- **Diverged branch:** Suggest rebase first. Do not force-push without explicit user request.
- **Push rejected** (non-fast-forward): Explain the situation, suggest pulling or rebasing.
- **No remote configured:** Report error, suggest `git remote add origin <url>`.
- **Authentication failure:** Report and suggest checking credentials or SSH keys.
