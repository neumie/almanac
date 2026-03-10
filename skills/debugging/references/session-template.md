# Hypothesis-Driven Debugging

A systematic approach to finding root causes. Never guess — always test.

## The Loop

```
Observe → Hypothesize → Experiment → Narrow → Fix → Verify → Prevent
```

### 1. Observe
Collect all available evidence before forming theories:
- Exact error message and stack trace
- Steps to reproduce
- Recent changes (`git log`, `git diff`)
- Environment details (versions, config, platform)
- Frequency: always, sometimes, only under specific conditions?

### 2. Hypothesize
Form 2-3 ranked hypotheses based on evidence:

| # | Hypothesis | Probability | Test |
|---|-----------|-------------|------|
| 1 | [Most likely cause] | High | [How to confirm/deny] |
| 2 | [Second most likely] | Medium | [How to confirm/deny] |
| 3 | [Less likely but possible] | Low | [How to confirm/deny] |

### 3. Experiment
Test the highest-probability hypothesis first:
- Design a test that clearly confirms or denies it
- Change one variable at a time
- Log before and after the suspected failure point

### 4. Narrow
Based on the experiment:
- **Confirmed**: Move to Fix
- **Denied**: Update probabilities, test next hypothesis
- **Inconclusive**: Add more logging, design a better test

Use binary search to narrow scope:
- In code: comment out half, does it still fail?
- In time: `git bisect` to find the introducing commit
- In data: try minimal input, add fields back one at a time

### 5. Fix
Change as little as possible. Fix the root cause, not the symptom.

### 6. Verify
- The original error no longer occurs
- The reproducing steps now succeed
- No regressions in related functionality

### 7. Prevent
- Write a test that fails without the fix and passes with it
- Check for the same pattern in related code
- Document if the cause was non-obvious

## Session Template

```markdown
## Bug: [brief description]

**Observed**: [what happened]
**Expected**: [what should happen]
**Reproduced**: [yes/no, steps]

### Hypotheses
1. [hypothesis] — [test to run]
2. [hypothesis] — [test to run]

### Investigation
- [experiment 1]: [result]
- [experiment 2]: [result]

### Root Cause
[what actually caused it]

### Fix
[what was changed and why]

### Prevention
[test added, pattern to watch for]
```
