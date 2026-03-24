---
name: pr-create
description: Use when creating a GitHub pull request. Pushes the branch if needed, generates a title and description from branch commits, and creates the PR with gh CLI. Use this whenever the user says create PR, open PR, submit PR, or is ready to merge their work.
compatibility: Requires gh CLI (GitHub CLI) for PR creation.
---

# Create PR

Push the branch and open a GitHub pull request with a well-crafted description.

## Phase 1 — Analyze

### Step 1: Detect the base branch

Try these in order:

1. **Try main:** `git rev-parse --verify origin/main 2>/dev/null`. If it exists, use `main`.
2. **Try master:** `git rev-parse --verify origin/master 2>/dev/null`. If it exists, use `master`.

Store the result as `<base>`.

### Step 2: Check prerequisites

- `git status` — warn if uncommitted changes exist (suggest committing first using the commit skill)
- `git branch --show-current` — get the branch name
- Verify not on main/master — cannot create a PR from the base branch to itself

### Step 3: Gather branch content

- `git log origin/<base>..HEAD --oneline` — all commits on the branch
- `git diff origin/<base>..HEAD --stat` — files changed summary
- `git diff origin/<base>..HEAD` — full diff for understanding
- Read changed files for context

### Step 4: Check remote state

- Is the branch pushed? `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
- Are all commits pushed? `git log @{u}..HEAD --oneline 2>/dev/null`
- Does a PR already exist? `gh pr view 2>/dev/null`

### Step 5: Generate PR content

**Title:**
- Under 70 characters
- Clear description of what the PR does
- Use branch commits to determine if this is a feat, fix, refactor, etc.

**Body:**

```markdown
## Summary
<1-3 bullet points describing what this PR does and why>

## Changes
<grouped by logical feature, not by file>

## Test plan
<bulleted checklist of how to verify the changes work>
```

## Phase 2 — Execute

### Step 1: Push if needed

- If branch not pushed: `git push -u origin <branch-name>`
- If unpushed commits exist: `git push`

### Step 2: Create the PR

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
...

## Changes
...

## Test plan
...
EOF
)" --base <base>
```

If the user requested a draft: add `--draft` flag.

### Step 3: Report

- Show the PR URL
- Report: **"Created PR #N: `<title>` — `<url>`"**

## Edge Cases

- **PR already exists:** Show the URL. Ask if the user wants to update the title/body with `gh pr edit`.
- **No commits on branch** (identical to base): Report and stop.
- **Branch has a generic name** (e.g. `temp`, `wip`, `test`, or auto-generated names): Suggest using the `branch-name` skill to rename it before creating the PR.
- **Not a GitHub repo:** Report error — this skill requires GitHub and the `gh` CLI.
- **gh CLI not installed:** Report error with install instructions (`brew install gh` or see https://cli.github.com).
- **Draft PR:** If user says "draft", add `--draft` flag to `gh pr create`.
- **Uncommitted changes:** Suggest using the commit skill first before creating the PR.
