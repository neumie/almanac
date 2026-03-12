---
name: branch-review
description: Use when you want a detailed narrative review of all changes on the current branch compared to its base. Groups changes by feature and explains what each feature does in plain English with file:line references, so you can understand the branch without reading code. Use this before merging, when catching up on what was built, or when you need to brief someone on the branch.
---

# Branch Review

Produce a detailed, structured prose narrative of all changes on the current branch. The reader directed the work but did not write the code — they need to understand what was built by reading words, not code. Be thorough. Every claim should reference specific files and line numbers so the reader can click straight into their IDE.

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
# Branch Review: <branch-name> vs <base-branch>

**Commits:** N | **Files changed:** N | **Insertions:** +N | **Deletions:** -N

## Features

1. Feature Name — one-line summary
2. Feature Name — one-line summary
...
```

Then, for each feature, write a detailed section with these subsections:

### What it does

Explain the purpose and behavior in plain English. What does this feature accomplish from the user's perspective? Avoid code jargon — describe it like you're explaining to someone who directed the work but hasn't seen the implementation.

### Structure

Describe what files make up this feature and what role each file plays. Reference each file as `file_path:line` so the reader can click into it. Explain how the files are organized relative to each other — which file is the entry point, which are helpers, which hold data structures.

### How it works

Trace the full execution flow step by step. This is the most important section — be thorough.

Walk through the path: "A request arrives at `routes/api.ts:23`, which extracts the payload and calls `services/processor.ts:45`. The processor validates the input against the schema defined in `models/task.ts:12-30`, then enqueues the job via `worker/queue.ts:67`..."

Every step should have a `file_path:line` reference. The reader should be able to follow the entire flow in their IDE by clicking the references in order.

### Key decisions

Describe the patterns, data structures, and architectural choices visible in the code. What approach was taken, and what does the structure reveal about the design? For example: "Uses an event-driven pattern with a central event bus at `lib/events.ts:15` rather than direct function calls between modules."

### What changed

Be specific about what was added, modified, or removed. Do not write vague descriptions like "updated the handler." Instead write: "Added a retry mechanism in `handler.ts:89-102` that catches timeout errors from the upstream API and re-enqueues the job with exponential backoff, starting at 1 second and capping at 30 seconds."

Every change description must include `file_path:line` references to the exact location.

If a feature connects to or depends on another feature in this branch, note the connection: "This feature provides the queue infrastructure that Feature 3 (notification dispatch) uses to send messages."

## Writing Guidelines

- **Be purely descriptive.** Do not critique, suggest improvements, or flag concerns. The reader will make their own judgments.
- **Be dense with references.** Every paragraph should contain `file_path:line` references. The reader should never have to guess where something lives.
- **Read the files, not just the diffs.** Explain how things work in context, not just what lines changed.
- **Write for someone who directed the work.** They know the intent but not the implementation. Explain mechanism and structure, not motivation.
- **Features are about purpose, not location.** A feature is "added webhook retry logic," not "changes to src/webhooks/."
- **Be detailed.** This review replaces reading the code. If you skip something, the reader won't know it exists. When in doubt, include it.
