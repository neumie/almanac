---
name: git-workflow
description: Use when making commits, creating branches, resolving merge conflicts, or managing git history. Guides clean commit practices, branching strategy, and safe operations. Use this whenever working with git beyond simple status checks.
---

# Git Workflow

Clean commits, safe operations, clear history.

## Commits

### Message Format

```
<type>(<scope>): <subject>

<body>
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

**Rules:**
- Subject line: imperative mood, under 72 chars, no period
- Body: explain **why**, not **what** (the diff shows what)
- Reference issues: `Fixes #123` or `Relates to #456`

**Examples:**
```
feat(auth): add JWT token refresh on expiry

Tokens were silently expiring after 1 hour, causing 401 errors
for long-running sessions. Now automatically refreshes 5 minutes
before expiry.

Fixes #234
```

### Atomic Commits

Each commit should be one logical change that passes all tests:
- Don't mix refactoring with feature work
- Don't mix formatting with logic changes
- If a change requires multiple steps, each step is a commit

### Staging

Stage specific files, not everything:
```bash
git add path/to/specific/file.ts
```

Never use `git add -A` or `git add .` — it risks including secrets, build artifacts, or unrelated changes.

## Branches

### Naming

```
<prefix>/<short-description>
```

Prefixes: `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`

Keep names under 30 characters, use concrete language:
- Good: `feat/jwt-refresh`, `fix/null-user-crash`
- Bad: `feature/implementing-the-new-authentication-system-v2`

### Strategy

- Create branches from the latest `main`
- Keep branches short-lived (days, not weeks)
- Rebase on main before creating PR: `git rebase main`
- Prefer small, focused PRs over large ones

## Safety Rules

**Never:**
- Force-push to `main` or `master`
- Use `--no-verify` to skip hooks
- Use `git reset --hard` without understanding what you'll lose
- Commit `.env` files, credentials, or API keys

**Always:**
- Check `git status` and `git diff` before committing
- Create a new commit rather than amending (unless explicitly asked)
- Investigate lock files before deleting them
- Resolve merge conflicts rather than discarding changes

## Merge Conflicts

1. Understand both sides: read the conflicting changes and their commit messages
2. Decide which version is correct (or merge both)
3. Edit the file to resolve — remove all conflict markers
4. Test that the resolved code works
5. Stage and commit with a message explaining the resolution
