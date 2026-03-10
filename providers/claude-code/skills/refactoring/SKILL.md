---
name: refactoring
description: Use when improving code structure, reducing duplication, simplifying complexity, or modernizing legacy code without changing external behavior. Use this whenever the user wants to clean up, restructure, or simplify existing code.
---

# Code Refactoring

Improve structure without changing behavior. Tests green at every step.

## Prerequisites

Before refactoring, ensure:
1. **Tests exist** that cover the code you're changing
2. If tests don't exist, write characterization tests first (tests that capture current behavior)
3. Run tests — they must pass before you start

## Process

### 1. Identify the Smell

Common code smells that warrant refactoring:

| Smell | Symptom | Typical Fix |
|-------|---------|-------------|
| Long function | >30 lines, multiple responsibilities | Extract method |
| Deep nesting | >3 levels of indentation | Early return, extract |
| Duplication | Same logic in 2+ places | Extract shared function |
| God class | One class does everything | Split by responsibility |
| Feature envy | Method uses another class's data more than its own | Move method |
| Primitive obsession | Using strings/numbers for domain concepts | Introduce value object |
| Long parameter list | >3 parameters | Introduce parameter object |
| Shotgun surgery | One change requires edits in many places | Move related logic together |

### 2. Choose the Refactoring

**Extract method**: Pull a block of code into a named function. Use when a function does multiple things or has comments explaining sections.

**Inline variable/method**: Replace a variable with the expression it holds, or a method with its body. Use when the name adds no clarity.

**Rename**: Make names match what the code actually does. Cheap, high-impact.

**Decompose conditional**: Replace complex `if/else` chains with named helper functions.

**Replace magic values**: Use named constants for numbers and strings that have domain meaning.

**Move to caller/callee**: Shift logic to where it naturally belongs.

### 3. Execute in Small Steps

For each refactoring:
1. Make one structural change
2. Run tests — they must pass
3. Commit if green
4. Repeat

Never combine refactoring with behavior changes in the same step. If you discover a bug while refactoring, note it and fix it in a separate commit.

### 4. Verify

After refactoring:
- All existing tests pass
- Behavior is unchanged (run the full suite, not just unit tests)
- Code is measurably simpler (fewer lines, less nesting, clearer names)
- No new abstractions were introduced unless they removed duplication in 3+ places

## Anti-Patterns

- **Premature abstraction**: Don't create a helper for code that exists in only one place
- **Refactoring without tests**: You'll break things and not know it
- **Big bang refactoring**: Rewriting everything at once is not refactoring — it's rewriting
- **Gold plating**: Refactoring until the code is "perfect" — good enough is good enough
