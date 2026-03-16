---
name: branch-fix
description: Use after branch-summary to fix problems you spotted in the summary. Tell it what's wrong and it uses the saved summary as context to locate and fix the actual code. Reads from .context/branch-summary.md.
---

# Branch Fix

Fix problems on the current branch using the saved branch summary as your map. The user has already read the review and knows what's wrong — your job is to locate the relevant code using the review's `file_path:line` references and make the fix.

This is a two-phase process: first load context from the review, then fix what the user tells you to fix.

## Phase 1 — Load Context

### Step 1: Read the branch summary

Read `.context/branch-summary.md` using the Read tool.

If the file does not exist, tell the user:

> "No branch summary found at `.context/branch-summary.md`. Run the `branch-summary` skill first to generate one."

Then stop. Do not proceed without a review.

### Step 2: Internalize the review

Parse the review to build your mental model:

- **Features** — what logical units of work exist on the branch
- **File map** — which files belong to which features, and what role each plays
- **Execution flows** — how the code works step by step, per the "How it works" sections
- **Key decisions** — architectural patterns and design choices already in place

This is your navigation map. You will use it to find the right code when the user describes a problem.

### Step 3: Ask for problems

Tell the user:

> "I've loaded the branch summary. What problems do you see?"

Wait for the user to describe what's wrong before proceeding.

## Phase 2 — Fix

For each problem the user describes:

1. **Locate** — Match the problem to the relevant feature(s) and `file_path:line` references from the review. Identify which files need to change.
2. **Read** — Read the actual source files to understand the current state. The review is a summary — always verify against the real code before editing.
3. **Fix** — Make the change using the Edit tool. Keep fixes minimal and focused on what the user asked for.
4. **Confirm** — Briefly state what you changed and where (`file_path:line`), so the user can verify.

After addressing all stated problems, ask:

> "Anything else to fix?"

### Guidelines

- **Trust the review as your map.** Use its `file_path:line` references to navigate. Do not re-analyze the branch from scratch.
- **Always read before editing.** The review summarizes — the source file is the truth. Read the file before making changes.
- **Fix what was asked.** Do not refactor, clean up, or improve code beyond what the user identified as a problem.
- **Stay in the review's frame.** If the user describes a problem that doesn't appear in the review, read the relevant files directly, but note that the review didn't cover it.
- **One problem at a time.** Confirm each fix before moving to the next.
