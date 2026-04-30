---
name: rebase
description: Use when rebasing the current branch onto main or another base branch. Auto-detects the base branch, handles conflicts gracefully, and supports squashing commits. Use this whenever the user says rebase, wants to update their branch, sync with main, or clean up commit history before a PR.
---

# Rebase

Rebase the current branch onto the base branch. Handle conflicts gracefully.

## Phase 1 — Analyze

These commands run automatically when the skill loads — output replaces each line below:

- PR base (if any): !`gh pr view --json baseRefName -q '.baseRefName' 2>/dev/null`
- origin/main exists: !`git rev-parse --verify origin/main 2>/dev/null && echo origin/main`
- origin/master exists: !`git rev-parse --verify origin/master 2>/dev/null && echo origin/master`
- Working tree status: !`git status`
- Current branch: !`git branch --show-current`
- In-progress rebase: !`ls -d .git/rebase-merge .git/rebase-apply 2>/dev/null`

### Step 1: Detect the base branch

Pick `<base>` from the pre-run output:

1. PR base if `gh pr view` returned one
2. Otherwise `origin/main` if it exists
3. Otherwise `origin/master`

### Step 2: Check prerequisites

- From `git status`: if uncommitted changes, **STOP**. Ask the user to commit or stash first.
- If `ls .git/rebase-*` returned a path, an in-progress rebase exists. Ask the user if they want to `--continue`, `--abort`, or `--skip`.

### Step 3: Fetch latest

```bash
git fetch origin <base>
```

### Step 4: Assess the situation

- `git log origin/<base>..HEAD --oneline` — commits on this branch
- `git log HEAD..origin/<base> --oneline` — new commits on base since divergence
- `git diff --stat origin/<base>..HEAD` — summary of branch changes

### Step 5: Predict conflicts

- `git diff --name-only origin/<base>..HEAD` — files changed on branch
- `git diff --name-only HEAD..origin/<base>` — files changed on base
- Intersect: files changed in both are conflict candidates
- Report: **"N files potentially conflicting: `<list>`"**

## Phase 2 — Confirm

Present to the user:

- **Current branch** and **base branch**
- **Commits to rebase:** count and list
- **New commits on base:** count
- **Potential conflict files** (if any)
- Options:
  - a) **Rebase** — replay commits on updated base
  - b) **Rebase and squash** — combine all commits into one (if user requested)
  - c) **Cancel**

Wait for confirmation.

## Phase 3 — Execute

### Standard rebase

```bash
git rebase origin/<base>
```

Do NOT use the `-i` flag — interactive mode requires terminal input that is not available in agent contexts.

### Handling conflicts

If the rebase stops with conflicts:

1. `git status` to identify conflicted files
2. Read each conflicted file in full
3. Understand both sides: read the commit messages for context
4. Resolve the conflict by editing the file — remove all conflict markers
5. `git add <resolved-file>`
6. `git rebase --continue`
7. Repeat if more conflicts arise

If conflicts are too complex to resolve confidently: `git rebase --abort` and report to the user.

### Squash (if requested)

Since `-i` is unavailable, use the soft-reset pattern:

```bash
git rebase origin/<base>
git reset --soft origin/<base>
git commit -m "$(cat <<'EOF'
type(scope): combined commit message

Body summarizing all squashed changes.
EOF
)"
```

## Phase 4 — Verify

- `git log --oneline -10` to show the new history
- `git diff --stat origin/<base>..HEAD` to confirm changes are preserved
- Report: **"Rebased N commits onto origin/`<base>`. Branch is now up to date."**

## Edge Cases

- **Already up to date:** Report and stop.
- **Dirty working tree:** STOP. Ask to commit or stash.
- **Rebase in progress:** Detect via `.git/rebase-merge` or `.git/rebase-apply`. Ask user: continue, abort, or skip.
- **Merge commits on branch:** Warn that rebase will linearize history, removing merge commits.
- **Branch already pushed:** Warn that rebasing will require a force-push to update the remote. Suggest using the push skill with force after rebase.
