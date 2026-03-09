# Code Review Checklist

## Correctness
- [ ] Does the code do what the PR description says?
- [ ] Are edge cases handled? (empty input, null, boundary values)
- [ ] Are error paths handled? (network failure, invalid data, timeout)
- [ ] Are all conditional branches complete?
- [ ] Are there off-by-one errors in loops or slices?

## Security
- [ ] Is user input validated and sanitized?
- [ ] No SQL injection, XSS, or command injection vectors?
- [ ] No hardcoded secrets or credentials?
- [ ] Permissions checked before sensitive operations?
- [ ] Dependencies free of known vulnerabilities?

## Performance
- [ ] No N+1 query patterns?
- [ ] No unbounded loops or large allocations at scale?
- [ ] Expensive computations cached when reused?
- [ ] No blocking operations that should be async?

## Readability
- [ ] Code understandable without the PR description?
- [ ] Names descriptive and consistent with codebase conventions?
- [ ] Complex sections commented with **why**, not **what**?
- [ ] Related code grouped together?

## Testing
- [ ] Tests cover new/changed behavior?
- [ ] Both happy path AND error cases tested?
- [ ] Tests check behavior, not implementation?
- [ ] Bug fix includes a regression test?

## Severity Guide

- **Blocker**: Must fix before merge (bugs, security, data loss)
- **Suggestion**: Would improve the code but not blocking
- **Nit**: Style/preference, take it or leave it
