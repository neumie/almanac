---
name: branch-summary
description: Use when you want a business-focused summary of all changes on the current branch. Groups changes by feature and explains what each feature does for users and the product, with a light technical summary and manual testing steps. Use this before merging, when catching up on what was built, or when you need to brief someone on the branch. This is NOT a technical code review — use code-review for that.
---

# Branch Summary

Produce a business-focused narrative of all changes on the current branch. The reader directed the work but did not write the code — they need to understand what was built, what it means for users, and how to quickly verify it works. Lead with business impact, not implementation details.

This is a two-phase process: first discover and group changes into features, then write the narrative after the user confirms the grouping.

## Phase 1 — Discovery & Grouping

### Step 1: Detect the base branch

Try these in order:

1. **Check for a PR:** Run `gh pr view --json baseRefName -q '.baseRefName'`. If a PR exists, use its base branch.
2. **Try main:** Run `git rev-parse --verify origin/main 2>/dev/null`. If it exists, use `origin/main`.
3. **Try master:** Run `git rev-parse --verify origin/master 2>/dev/null`. If it exists, use `origin/master`.

Store the result as `<base>` for all subsequent commands.

### Step 2: Gather raw material

Run these commands and read their output:

- `git log <base>..HEAD --oneline` — list of commits on the branch
- `git diff <base>..HEAD --stat` — summary of files changed with insertion/deletion counts
- `git diff <base>..HEAD` — the full diff

Then **read every changed file in full** (not just the diff hunks). Diffs show what changed but miss the surrounding context that explains *why* something works the way it does. You need both.

### Step 3: Auto-detect features

Analyze the commits, diffs, and file contents to identify logical feature groups. A "feature" is a coherent unit of work that accomplishes something — it might span many files, and a single file might contribute to multiple features.

Group by what the changes **accomplish**, not by file path. For example:
- "Added retry logic to the task queue" (spans worker, config, and tests)
- "Migrated authentication to OAuth2" (spans routes, middleware, models, and env)

Do NOT group by directory (e.g., "changes to src/worker/") — that tells the reader nothing about purpose.

### Step 4: Present the grouping

Show the user a numbered list of detected features. For each feature, include:
- A short descriptive name
- A one-line summary of what it accomplishes
- The list of changed files associated with this feature (as clickable `file_path` references)

Format:

```
## Detected Features

### 1. [Feature Name]
[One-line summary]

**Files:**
- `path/to/file.ts` (modified)
- `path/to/other.ts` (new)
- `path/to/removed.ts` (deleted)

### 2. [Feature Name]
...
```

After presenting, ask the user: **"Does this grouping look right? You can rename, split, merge, or reorder features before I write the full review."**

Wait for confirmation before proceeding to Phase 2.

## Phase 2 — Narrative Writing

Once the user confirms the grouping, write the full review. Use this exact output structure:

```
# Branch Summary: <branch-name> vs <base-branch>

**Commits:** N | **Files changed:** N | **Insertions:** +N | **Deletions:** -N

## Features

1. Feature Name — one-line summary
2. Feature Name — one-line summary
...
```

Then, for each feature, write a section with these subsections:

### What it does

Lead with business impact. What does this feature mean for users or the product? What behavior changes, what rules are enforced, what outcomes are different? Write for someone who cares about the product, not the codebase. No file references in this section — pure business narrative.

For example: "Users can now retry failed webhook deliveries instead of losing them permanently. Failed deliveries are retried up to 3 times with increasing delays, and the user sees the retry status in their dashboard."

### How it's built

A brief technical summary — 3-5 sentences max. Name the key files with `file_path:line` references for entry points only. Describe the high-level approach and any notable architectural choices. This is NOT a step-by-step execution trace.

For example: "Built as a background job triggered from `worker/retry.ts:12`. Uses the existing job queue infrastructure with a new retry policy defined in `config/retry.ts:5`. Retry state is persisted in the webhooks table via a new `retry_count` column."

### How to test it

Numbered manual walkthrough steps the reader can follow to quickly verify the feature works. Written for someone who knows the product but hasn't seen the code. Cover the happy path; mention edge cases only if they're important to verify.

For example:
1. Open the webhooks dashboard
2. Trigger a webhook to a failing endpoint
3. Observe the delivery marked as "Failed" with a "Retrying" badge
4. Wait 30 seconds — the delivery should show "Retry 1 of 3"
5. After all retries exhaust, status should show "Failed permanently"

### What changed

Describe changes in terms of behavioral impact rather than code mechanics. Instead of "Added retry mechanism in handler.ts:89-102 that catches timeout errors," write "Failed webhook deliveries are now automatically retried instead of being marked as permanently failed." Include `file_path:line` references for the key locations only.

If a feature connects to or depends on another feature in this branch, note the connection: "This feature provides the queue infrastructure that Feature 3 (notification dispatch) uses to send messages."

## Writing Guidelines

- **Lead with business value.** Every feature section should first answer: what does this change mean for users or the product?
- **Be purely descriptive.** Do not critique, suggest improvements, or flag concerns. The reader will make their own judgments.
- **References at key entry points only.** Include `file_path:line` references for main entry points and important locations, not every paragraph. The reader should know where to look, not trace every line.
- **Read the files, not just the diffs.** Explain how things work in context, not just what lines changed.
- **Write for someone who directed the work.** They know the intent but not the implementation. Explain what was built and why it matters — the code is there for those who want depth.
- **Features are about purpose, not location.** A feature is "added webhook retry logic," not "changes to src/webhooks/."
- **Make testing easy.** The "How to test it" section should let someone verify the feature in under a minute.

## Phase 3 — Save the Summary

After writing the summary to the conversation, save the complete output (from `# Branch Summary:` through the end) to `.mine/context/branch-summary.md` using the Write tool. Create the `.mine/context/` directory first if it doesn't exist. Tell the user where the file was saved.
