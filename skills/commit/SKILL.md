---
name: commit
description: Use when committing code changes. Analyzes staged and unstaged changes, writes a conventional commit message, stages specific files intelligently, and executes the commit. Use this whenever the user says commit, wants to save their work, or is done with a change.
---

# Commit

Analyze changes, write a good message, commit safely.

## Phase 1 — Analyze

### Step 1: Survey the working tree

Run these commands:

- `git status` (never use `-uall`)
- `git diff --staged --stat` and `git diff --stat` to understand scope
- `git diff --staged` and `git diff` for full content
- `git log --oneline -5` to see recent commit style

If nothing is staged and nothing is modified, report "Nothing to commit" and stop.

### Step 2: Read changed files

For each changed file, read the full file (not just the diff) to understand context. Determine:

- What logical change this represents
- Whether this is one atomic change or multiple — if multiple, advise the user to split into separate commits

### Step 3: Safety checks

Scan for dangerous patterns before proceeding:

- **Secrets:** `.env` files, API keys, tokens, passwords, `credentials.json`, private keys, connection strings with embedded passwords
- **Large binaries:** Files over 1MB (images, compiled assets, archives)
- **Should be gitignored:** `node_modules/`, `.DS_Store`, `__pycache__/`, `build/`, `dist/`, `.next/`

If any secrets are found: **STOP.** List the files. Do NOT proceed until the user explicitly confirms exclusion.

### Step 4: Draft the commit message

Read `skills/git-workflow/references/commit-format.md` for the format reference.

1. Classify the change type: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
2. Identify scope from the primary area affected
3. Write the subject line: imperative mood, under 72 chars, no trailing period
4. Write the body: explain **why**, not **what** (the diff shows what)
5. Add footer if applicable: `Fixes #123`, `BREAKING CHANGE:`, etc.

## Phase 2 — Confirm

Present to the user:

- **Files to stage** — list each by path
- **Files to exclude** — list with reason (secret, unrelated, binary)
- **Proposed commit message** — full format: `type(scope): subject` + body
- Ask: **"Ready to commit? You can adjust the message, add/remove files, or cancel."**

Wait for confirmation before proceeding.

## Phase 3 — Execute

### Step 1: Stage files

Stage each file individually by name:

```bash
git add path/to/file
```

**NEVER** use `git add -A` or `git add .`

### Step 2: Commit

Use heredoc format to preserve message formatting:

```bash
git commit -m "$(cat <<'EOF'
type(scope): subject

Body explaining why.

Footer
EOF
)"
```

Always create a **new** commit. Never amend unless the user explicitly requested it.

### Step 3: Verify

- Run `git status` to confirm the working tree state
- Run `git log --oneline -1` to show the result
- Report: **"Committed `<hash>`: `<subject>`"**

## Edge Cases

- **Nothing to commit:** Report and stop
- **Pre-commit hook failure:** The commit did NOT happen. Fix the issue, re-stage, and create a **NEW** commit. Never use `--amend` after a hook failure — it would modify the previous commit.
- **Mixed staged + unstaged changes:** Show both clearly. Ask the user which to include.
- **Merge conflict markers in files:** Warn and refuse to commit those files.
- **Multiple logical changes:** Advise splitting. Offer to commit a subset.
