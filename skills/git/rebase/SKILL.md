---
name: rebase
description: "Use when rebasing the current branch onto main or another base. Auto-detects base, handles conflicts, supports squashing. Triggers: rebase, sync with main, clean history before PR."
---

# Rebase

Rebase the current branch onto the base branch. Handle conflicts gracefully.

## Safety invariant

A rebase must preserve both sides of history: replay the feature branch on top of the updated base, without turning old base files from the feature branch into reversions of newer base changes.

Before rebasing, capture the original branch tip and merge base. After rebasing or squashing, audit the final PR diff against that snapshot. Files that changed only on the updated base must not appear in the final PR diff unless you intentionally edited and reviewed them.

## Ask the user when unsure

Bias toward caution over cleverness. A rebase rewrites history and can silently drop another developer's work, and the damage often surfaces only days later. When you cannot proceed with high confidence, **stop and ask the user a specific question** instead of guessing — asking is always cheaper than reverting a bad rebase.

Stop and ask (do not guess) when any of these hold:

- A conflict is not mechanical: both sides changed the same logic, or a moved/renamed/redesigned file must absorb a base change, or merging the behavior is a judgment call. Show both sides and your proposed resolution, then get confirmation before continuing.
- The diff-preservation audit flags a file you cannot confidently explain, or you are unsure whether a change is an intended feature edit or an accidental reversion of base work.
- A base change may be lost at the **semantic** level — a new field, validation, permission, label, guard, or migration that the branch's moved or rewritten file does not carry — and you are not certain how to port it. File-level presence is not proof the change survived; a passing typecheck is not proof either (a missing UI field or dropped option compiles fine).
- Resolving would require deleting code that looks like business logic, or choosing a whole-file side.

To ask mid-rebase, leave the rebase paused — do not `git rebase --continue` past an unresolved decision — and tell the user the exact file and the choice you need. If pausing is risky, `git rebase --abort` first, then ask. Never resolve a conflict you do not understand just to make the rebase proceed.

## Phase 1 — Analyze

These commands run automatically when the skill loads — output replaces each line below:

- PR base (if any): !`gh pr view --json baseRefName -q '.baseRefName' 2>/dev/null || true`
- origin/main exists: !`git rev-parse --verify origin/main 2>/dev/null && echo origin/main || true`
- origin/master exists: !`git rev-parse --verify origin/master 2>/dev/null && echo origin/master || true`
- Working tree status: !`git status`
- Current branch: !`git branch --show-current`
- In-progress rebase: !`ls -d .git/rebase-merge .git/rebase-apply 2>/dev/null || true`

### Step 1: Detect the base branch

Pick `<base-name>` and `<base-ref>` from the pre-run output:

1. PR base if `gh pr view` returned one. Example: `<base-name>` is `main`, `<base-ref>` is `origin/main`.
2. Otherwise `origin/main` if it exists. Use `<base-name>` `main` and `<base-ref>` `origin/main`.
3. Otherwise `origin/master`. Use `<base-name>` `master` and `<base-ref>` `origin/master`.

### Step 2: Check prerequisites

- From `git status`: if uncommitted changes, **STOP**. Ask the user to commit or stash first.
- If `ls .git/rebase-*` returned a path, an in-progress rebase exists. Ask the user if they want to `--continue`, `--abort`, or `--skip`.

### Step 3: Fetch latest

```bash
git fetch origin
```

### Step 4: Assess the situation

- `git rev-parse HEAD` — save this as `<old-tip>`
- `git merge-base HEAD <base-ref>` — save this as `<old-base>`
- `git log <base-ref>..HEAD --oneline` — commits on this branch
- `git log HEAD..<base-ref> --oneline` — new commits on base since divergence
- `git diff --stat <base-ref>..HEAD` — summary of branch changes
- `git diff --name-status <old-base>..<old-tip>` — original feature file set
- `git diff --name-status <old-base>..<base-ref>` — files changed on the updated base since divergence

If the original feature file set contains files unrelated to the user's requested work, stop and investigate before rebasing. The branch may already contain accidental reversions from an earlier sync.

### Step 5: Predict conflicts

- `git diff --name-only <old-base>..<old-tip>` — files changed on branch
- `git diff --name-only <old-base>..<base-ref>` — files changed on base since divergence
- Intersect: files changed in both are conflict candidates
- Report: **"N files potentially conflicting: `<list>`"**
- Treat files that changed only on base as protected. They are not feature changes, and if they appear in the final PR diff after the rebase/squash, investigate before committing or pushing.

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

If Phase 1 surfaced anything unusual — files in the feature set unrelated to the requested work, protected base files that overlap with branch changes, or a larger-than-expected conflict set — call it out prominently here and recommend the user review before choosing.

Wait for confirmation. Do not start the rebase until the user has chosen.

## Phase 3 — Execute

### Standard rebase

```bash
git rebase <base-ref>
```

Do NOT use the `-i` flag — interactive mode requires terminal input that is not available in agent contexts.

### Handling conflicts

Resolve one conflict at a time, and only when you understand both sides. Before resolving each one, gauge your confidence: if the resolution is not mechanical (see the conflict rules below), treat it as a stop-and-ask decision per "Ask the user when unsure" rather than guessing.

If the rebase stops with conflicts:

1. `git status` to identify conflicted files
2. `git diff` to inspect the conflict. During a rebase, `ours` is the updated base and `theirs` is the branch commit being replayed.
3. Read each conflicted file in full.
4. Understand both sides: read the commit messages for context.
5. Resolve the conflict by editing the file — remove all conflict markers.
6. Run `rg '<<<<<<<|=======|>>>>>>>'` before staging.
7. `git add <resolved-file>`.
8. Run the cheapest relevant project check if available before continuing. Examples: typecheck, unit test for touched package, `cargo check`.
9. `git rebase --continue`.
10. Repeat if more conflicts arise.

Conflict rules:

- Import/use-statement conflicts: combine both sets, remove duplicates, keep local sort style.
- Modify/delete conflicts: identify why the file was deleted or moved, then port the **surviving side's** change into the replacement file. When the branch moved or redesigned a file that base then modified in place, the base modification must land in the branch's replacement — verify at the semantic level that base's specific additions (new fields, options, validations) survive, not just that a file exists. Never just `git rm` and continue unless you verified the change is obsolete. If you cannot tell which file is the replacement, or how the surviving change maps onto it, pause and ask the user.
- Content conflicts: merge the behavior logically. Do not choose a whole-file side just to clear the conflict.
- Removed code on one side: keep the removal only after reading the commit that removed it and verifying it was intentional.
- Base-only additions such as new required fields, validations, guards, labels, or permissions must be preserved. Layer branch changes on top of them.
- Avoid `git checkout --ours <file>` or `git checkout --theirs <file>` for non-generated files. Whole-file side selection is allowed only after you inspect both versions and can explain why the other side is obsolete.

If a conflict is too complex to resolve with high confidence, do not guess: pause the rebase and ask the user with both sides shown, or `git rebase --abort` and report. Always prefer asking over a low-confidence resolution.

### Squash (if requested)

Since `-i` is unavailable, use the soft-reset pattern:

```bash
git rebase <base-ref>
git reset --soft <base-ref>
git diff --cached --name-status
```

Run the staged diff-preservation audit with `<old-base>` and `<old-tip>`. Do not commit if unexplained base-only files appear in the staged diff.

If the audit is clean, commit:

```bash
git commit -m "$(cat <<'EOF'
type(scope): combined commit message

Body summarizing all squashed changes.
EOF
)"
```

## Phase 4 — Verify

- `git log --oneline -10` to show the new history
- `git diff --stat <base-ref>..HEAD` to confirm changes are preserved
- `git diff --check <base-ref>..HEAD`
- `git diff --name-status <base-ref>..HEAD` to review the final PR file set

### Diff-preservation audit

Use the `<old-base>` and `<old-tip>` captured before rebasing:

```bash
git diff --name-only <base-ref>..HEAD | sort > /tmp/rebase-after-files
git diff --name-only <old-base>..<old-tip> | sort > /tmp/rebase-before-files
git diff --name-only <old-base>..<base-ref> | sort > /tmp/rebase-base-files

comm -23 /tmp/rebase-after-files /tmp/rebase-before-files
comm -12 /tmp/rebase-after-files /tmp/rebase-base-files
```

For a staged squash commit that does not exist yet, replace the first command with:

```bash
git diff --cached --name-only | sort > /tmp/rebase-after-files
```

Interpretation:

- First `comm`: files now in the PR diff that were not in the original feature diff. Each one needs a concrete explanation.
- Second `comm`: files in the PR diff that also changed on the updated base since divergence. Inspect each with `git diff <base-ref>..HEAD -- <file>` and confirm your change layers on top of base rather than reverting it — check that none of base's added lines appear as removals (`^-`) in your diff. Presence of the file is not the whole check: verify base's *specific* additions (fields, options, labels, validations, guards, migrations) are still in the final content. Preserve base behavior unless the user explicitly asked to change it.

If either command reports a file you cannot confidently explain, or you are unsure whether base behavior survived, **stop and ask the user before committing, squashing, or pushing** — do not assume it is fine. A common fix is restoring the protected file from the updated base, then reapplying only the intended feature change.

- Report: **"Rebased N commits onto `<base-ref>`. Branch is now up to date."**

## Edge Cases

- **Already up to date:** Report and stop.
- **Dirty working tree:** STOP. Ask to commit or stash.
- **Rebase in progress:** Detect via `.git/rebase-merge` or `.git/rebase-apply`. Ask user: continue, abort, or skip.
- **Merge commits on branch:** Warn that rebase will linearize history, removing merge commits.
- **Branch already pushed:** Warn that rebasing will require a force-push to update the remote. Suggest using the push skill with force after rebase.
