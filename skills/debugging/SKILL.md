---
name: debugging
description: Use when encountering errors, test failures, unexpected behavior, or bugs. Guides systematic hypothesis-driven debugging through root cause analysis, isolation, and regression prevention. Use this whenever something isn't working as expected.
---

# Systematic Debugging

Don't guess. Form hypotheses, test them, narrow scope. Every bug has a cause — find it methodically.

## Process

### 1. Capture the Error

Before anything else, collect:
- Exact error message and full stack trace
- Steps to reproduce (or the failing test)
- What changed recently: `git log --oneline -10`, `git diff`
- Expected vs actual behavior

### 2. Form Hypotheses

Based on the error, list 2-3 most likely causes. Rank by probability. Common categories:
- **Data**: wrong input, missing field, type mismatch, null/undefined
- **State**: race condition, stale cache, incorrect initialization order
- **Environment**: missing dependency, wrong version, config difference
- **Logic**: off-by-one, wrong operator, inverted condition, missing edge case

### 3. Isolate with Binary Search

Narrow scope systematically:
- **In code**: comment out half the logic. Does the error persist? Narrow to the half that causes it.
- **In time**: `git bisect` to find the commit that introduced the bug
- **In data**: try minimal input. Add fields back one at a time.
- **In layers**: test each layer independently (DB query, API handler, frontend render)

### 4. Read Before You Write

Before changing any code:
- Read the function that's failing, and the functions it calls
- Check the types and contracts at each boundary
- Look at recent changes to the relevant files: `git log -5 --patch -- path/to/file`
- Search for similar patterns elsewhere: if this bug exists here, does it exist in similar code?

### 5. Fix Minimally

Change as little as possible:
- Fix the root cause, not the symptom
- Don't refactor while debugging — that's a separate step
- One change at a time, test after each

### 6. Verify and Prevent

- Write a test that fails without the fix and passes with it
- Check for the same bug pattern in related code
- Document what caused it if it's non-obvious (a code comment at the fix site is fine)

## Strategic Logging

When the cause isn't obvious, add temporary logging at layer boundaries:

```
Entry point → log input
  → Service call → log args and return value
    → DB query → log query and results
```

Remove after debugging. Don't commit temporary logs.

## Red Flags During Debugging

- "It works on my machine" → environment difference. Compare configs, versions, env vars.
- "It worked yesterday" → find the change. `git bisect` is your friend.
- "It only fails sometimes" → likely a race condition or external dependency. Add logging to capture the failing state.
- "The fix should work but doesn't" → your mental model is wrong. Re-read the code with fresh eyes. Explain it to someone (or to yourself out loud).
