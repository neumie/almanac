---
name: branch-name
description: Use when naming or renaming the current git branch based on its contents. Use this whenever the user says name this branch, rename branch, needs a branch name, or is on a default/placeholder branch like main with uncommitted work.
---

# Branch Name

Generate a descriptive branch name from the branch's contents and rename the current branch.

## What to analyze

Gather context in this order (use whatever is available):

1. `git diff --cached --stat` and `git diff --cached` — staged changes
2. `git diff --stat` and `git diff` — unstaged changes
3. `git log main..HEAD --oneline 2>/dev/null || git log master..HEAD --oneline 2>/dev/null` — commits on the branch
4. `git log main..HEAD --format="%B" 2>/dev/null || git log master..HEAD --format="%B" 2>/dev/null` — full commit messages

Use whatever is available. If on main/master with uncommitted changes, use the diff only.

## Naming rules

- Format: `<type>/<short-description>` where type is `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, or `perf`
- Use lowercase kebab-case for the description
- Keep total length under 50 characters
- Be specific: `feat/add-user-avatar-upload` not `feat/update-users`
- Use imperative mood: `fix/handle-null-response` not `fix/handled-null-response`
- No issue numbers unless the user asks for them

## Procedure

1. Analyze the branch contents (diffs and/or commits as above).
2. Determine the primary type from the changes.
3. Generate the branch name.
4. Present the name and rename:

```bash
git branch -m <new-name>
```

5. After renaming, check if the old branch had a remote tracking branch:

```bash
git for-each-ref --format='%(upstream:short)' refs/heads/<new-name>
```

If a remote tracking branch exists, rename the remote branch using GitHub's API (this preserves any open PRs):

```bash
gh api -X POST repos/{owner}/{repo}/branches/<old-name>/rename -f new_name="<new-name>"
git branch -u origin/<new-name>
```

If the `gh` command fails (e.g. not a GitHub repo), fall back to:

```bash
git push -u origin <new-name> && git push origin :<old-name>
```

## Edge cases

- **No changes and no commits:** Report "nothing to name — no changes or commits found" and stop.
- **Already on a well-named branch:** Suggest keeping it, or offer the new name as an alternative.
- **Detached HEAD:** Report error — must be on a branch to rename.
- **Mixed change types:** Use the dominant type. If truly split, suggest the user commit separately and name after the primary purpose.
