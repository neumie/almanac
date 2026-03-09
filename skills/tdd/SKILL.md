---
name: tdd
description: Use when building features or fixing bugs with a test-first approach. Guides the red-green-refactor cycle with vertical slice methodology and behavior-focused testing. Use this whenever the user mentions TDD, test-driven, writing tests first, or wants to ensure code correctness through testing.
---

# Test-Driven Development

Write one failing test, make it pass, refactor. Repeat. Never write implementation without a failing test.

## The Cycle

### RED — Write one failing test

Write the smallest test that expresses the next behavior you need. Run it. It must fail. If it passes, you didn't need it — delete it and think harder about what's missing.

Focus on:
- Test behavior through public interfaces, not implementation details
- Name tests after what the code should do, not how: `should_reject_expired_tokens` not `test_check_expiry_method`
- One assertion per test (or closely related assertions about the same behavior)

### GREEN — Make it pass with minimal code

Write the simplest code that makes the test pass. No more. Hardcode return values if that's all it takes. The test suite tells you when you need more.

Rules:
- Don't write code the tests don't require
- Don't optimize yet
- Don't refactor yet
- If you need to touch unrelated code, stop — write a test for that first

### REFACTOR — Clean up while green

All tests passing? Now improve the code. Remove duplication, extract functions, rename for clarity. Run tests after each change.

Never refactor and add behavior in the same step.

## Vertical Slice Approach

Build one thin end-to-end slice first:

```
1. Pick one specific scenario (e.g., "user logs in with valid credentials")
2. Write a test for it
3. Implement just enough to pass
4. Pick the next scenario
5. Repeat
```

**Anti-pattern — horizontal slicing:**
Don't write all tests first, then all implementation. You lose the feedback loop that makes TDD valuable.

## When TDD Helps Most

- New features with clear requirements
- Bug fixes (write the test that exposes the bug first)
- Complex business logic with edge cases
- API contract development
- Refactoring existing code (write characterization tests first)

## When to Adapt

- Exploratory prototypes: skip TDD, but add tests before committing
- UI layout: visual inspection beats assertions on pixel positions
- Glue code with no logic: a passing integration test suffices

## Common Mistakes

- **Testing implementation**: Tests that break when you refactor (but behavior hasn't changed) are testing the wrong thing
- **Too many mocks**: If you need 5 mocks to test a function, the function does too much
- **Test names that describe code**: `test_process_returns_dict` tells you nothing about expected behavior
- **Skipping refactor step**: The refactor phase is where design emerges — don't skip it
