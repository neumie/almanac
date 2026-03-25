---
name: ship
description: Use when shipping work end-to-end. Names the branch, commits changes, pushes, and creates a PR — all without confirmation. Use this whenever the user says ship, ship it, send it, or wants to go from uncommitted changes to an open PR in one step.
---

# Ship

Run the full workflow: name the branch, commit, push, and open a PR. Each step runs unconditionally — the step itself decides whether to act or skip. Stop immediately if any step fails.

If the user says "ship draft" or "draft", create the PR as a draft.

## Step 1 — Name the branch

### Analyze

Gather context in this order (use whatever is available):

1. `git diff --cached --stat` and `git diff --cached` — staged changes
2. `git diff --stat` and `git diff` — unstaged changes
3. `git log main..HEAD --oneline 2>/dev/null || git log master..HEAD --oneline 2>/dev/null` — commits on branch
4. `git log main..HEAD --format="%B" 2>/dev/null || git log master..HEAD --format="%B" 2>/dev/null` — full commit messages

### Naming rules

- Format: `<type>/<short-description>` where type is `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, or `perf`
- Lowercase kebab-case, under 50 characters total
- Imperative mood: `fix/handle-null-response` not `fix/handled-null-response`

### Execute

- If the branch already has a good descriptive name (matches `<type>/<description>` pattern and accurately describes the work), keep it.
- Otherwise, rename: `git branch -m <new-name>`
- If the old branch had a remote tracking branch, rename via GitHub API:
  ```bash
  gh api -X POST repos/{owner}/{repo}/branches/<old-name>/rename -f new_name="<new-name>"
  git branch -u origin/<new-name>
  ```
  Fallback if `gh` fails: `git push -u origin <new-name> && git push origin :<old-name>`

### Record

Note for the summary: `Branch: <name>` (or `Branch: <name> (kept)` if unchanged).

## Step 2 — Commit

### Analyze

- `git status` — check for uncommitted changes
- `git diff` and `git diff --cached` — review all changes

### Skip condition

If there are no staged or unstaged changes, skip this step. Record: `Commit: nothing to commit (skipped)`.

### Commit message format

```
<type>(<scope>): <short summary in imperative mood>
```

Types: `feat`, `fix`, `refactor`, `perf`, `chore`, `ci`, `docs`, `test`. Lowercase, no period, under 72 characters. Add a body only if the "why" isn't obvious.

### Execute

- Stage relevant files with `git add <specific files>` (never `git add -A` or `git add .`)
- Split into multiple logical commits if changes cover distinct topics
- If you spot `.env` files, API keys, tokens, credentials, or private keys — **stop and warn**
- If pre-commit hook fails: fix the issue, re-stage, create a **new** commit (never `--amend`)

### Record

Note for the summary: `Commit: "<message>"` (or multiple lines if split into multiple commits).

## Step 3 — Push

### Analyze

- `git branch --show-current` — current branch name
- `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null` — check tracking branch

### Safety checks

- **main/master:** Regular push is fine. Force-push is **NEVER** allowed.
- **Diverged branch:** Stop and suggest rebasing. Do not force-push.

### Execute

- If tracking exists: `git push`
- If no tracking: `git push -u origin <branch-name>`

### Skip condition

If there are no unpushed commits (already up to date), skip the push itself but still check for an open PR to update its description.

### Update PR description (if open PR exists)

After pushing, check: `gh pr view --json number,title,url,state 2>/dev/null`

If an **open** PR exists (state is `OPEN` — ignore `MERGED` or `CLOSED` PRs):

1. Gather the full branch diff against base:
   - `git log origin/<base>..HEAD --oneline`
   - `git diff origin/<base>..HEAD --stat`
   - `git diff origin/<base>..HEAD`
2. Generate an updated PR body:
   ```markdown
   ## Summary
   <1-3 bullet points>

   ## Changes
   <grouped by logical feature>

   ## Test plan
   <bulleted checklist>
   ```
3. Update: `gh pr edit <number> --body "..."` (and title if scope changed significantly)

### Record

Note for the summary: `Push: N commits to origin/<branch>` (or `Push: already up to date (skipped)`). If PR was updated: `PR #N: description updated`.

## Step 4 — Create PR

### Detect the base branch

Try `origin/main`, then `origin/master`.

### Skip condition

Check: `gh pr view --json number,url,state 2>/dev/null`

If an **open** PR already exists for this branch (state is `OPEN`), skip creation. Record: `PR: #N already exists — <url>`.

If the PR is `MERGED` or `CLOSED`, treat it as if no PR exists — proceed to create a new one.

### Generate PR content

**Title:** Under 70 characters, clear description of what the PR does.

**Body:**

```markdown
## Summary
<1-3 bullet points describing what this PR does and why>

## Changes
<grouped by logical feature, not by file>

## Test plan
<bulleted checklist of how to verify the changes work>
```

### Execute

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

If draft was requested: add `--draft` flag.

### Record

Note for the summary: `PR: Created #N — <url>` (add `(draft)` if applicable).

## Final Summary

After all steps complete, print a compact summary:

```
Shipped:
  Branch: feat/add-user-avatar
  Commit: "feat(avatar): add upload endpoint"
  Push: 1 commit to origin/feat/add-user-avatar
  PR: Created #42 — https://github.com/org/repo/pull/42
```

Replace any skipped steps with their skip message (e.g., `Commit: nothing to commit (skipped)`).

After the summary, ask: **"Watch CI?"** If the user says yes, invoke the `pr-watch` skill on the PR.
