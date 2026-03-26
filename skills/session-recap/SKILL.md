---
name: session-recap
description: Use when the user wants a summary of what happened on the current branch or work session. Gathers git log, diff, branch name, PR status, and uncommitted changes to produce a concise recap. Use this whenever the user says recap, catch me up, what did I do, where was I, what happened, summarize this session, or wants to pick up where they left off.
---

# Session Recap

Summarize what happened on the current branch so the user can pick up where they left off.

## Gather Context

Run all of these. Use whatever succeeds — not every repo has a remote, PR, or diverged branch.

### 1. Branch and base

```bash
BRANCH=$(git branch --show-current)
```

Detect the base branch:

```bash
git rev-parse --verify origin/main 2>/dev/null && BASE=main || {
  git rev-parse --verify origin/master 2>/dev/null && BASE=master || BASE=""
}
```

### 2. Commits on this branch

```bash
git log origin/$BASE..HEAD --oneline 2>/dev/null
```

For richer context, also get full commit messages:

```bash
git log origin/$BASE..HEAD --format="%h %s%n%b" 2>/dev/null
```

### 3. What changed (files)

```bash
git diff origin/$BASE..HEAD --stat 2>/dev/null
```

### 4. Uncommitted changes

```bash
git status --short
```

If there are uncommitted changes:

```bash
git diff --stat
git diff --cached --stat
```

### 5. Open PR

```bash
gh pr view --json number,title,url,state,body,reviews,statusCheckRollup 2>/dev/null
```

If `gh` is unavailable or no PR exists, skip.

## Produce the Recap

Print a concise summary using this structure. Omit any section that has no content.

```
## Session Recap: <branch-name>

### Goal
<1-2 sentences describing WHY this work exists — the initial task or motivation.
 Infer from: branch name (e.g. feat/add-user-avatar → "Add user avatar support"),
 PR description body (if exists), first commit message, and the overall shape of changes.
 If the PR body contains context, prefer that — it's the most intentional description.>

### What was done
<1-5 bullet points summarizing the commits, grouped by intent — not one bullet per commit.
 Derive intent from commit messages, branch name, and the diff.>

### Current state
- Branch: <branch> (<N commits ahead of <base>>)
- PR: #<N> <title> (<state>) — <url>   OR   No PR yet
- CI: <passing/failing/pending>   (from statusCheckRollup, if available)
- Uncommitted changes: <none / N files modified, M staged>

### What might be next
<1-3 bullets. Infer from:
 - Uncommitted changes → unfinished work
 - No PR yet → create one
 - PR is draft → mark ready
 - CI failing → fix CI
 - PR has review comments → address feedback
 - Everything clean and merged → done>
```

## Edge Cases

- **On main with no divergent commits:** Report "On main — no branch work in progress." Show uncommitted changes if any, otherwise say the working tree is clean.
- **Detached HEAD:** Report the detached state and show recent commits from `git log -5 --oneline`. Skip PR and branch-relative sections.
- **No remote configured:** Skip PR and base-branch comparison. Use `git log -10 --oneline` and uncommitted changes only.
- **Brand new repo (no commits):** Report "New repository — no commits yet." Show staged/untracked files if any.
- **gh CLI unavailable:** Skip PR section entirely. Do not error.

## Rules

- This is **read-only** — never modify files, branches, or PRs.
- Keep the output compact. The user wants a glance, not a report.
- Do not print raw diffs or full file contents. Summarize.
- If everything is clean (on main, no changes, no open PR), say so in one line and stop.
