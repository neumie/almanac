---
name: test-write
description: Use when backfilling tests on existing code. Analyzes code through public interfaces, detects the project's test framework, and writes behavior-focused regression tests. Supports targeted mode (specific files) and diff-based mode (changed files from git). Use this whenever the user says write tests, add tests, cover this, or wants regression tests for existing code.
---

# Test Write

Generate regression tests for existing code. Detect the test framework, analyze behavior through public interfaces, write tests, and run them.

## Modes

### Targeted Mode

When the user specifies files or modules:

```
/test-write src/actions/createOrder.ts
/test-write src/utils/
```

Analyze the specified code and generate tests for its public interface.

### Diff-Based Mode

When no target is specified:

```
/test-write
```

Read `git diff` (staged + unstaged) to find changed files. Generate tests for the modified behaviors.

If the working tree is clean, check the last commit with `git diff HEAD~1`.

## Process

### 1. Detect Test Framework

These commands run automatically when the skill loads — output replaces each line below:

- Test config files: !`ls vitest.config.* jest.config.* pytest.ini pyproject.toml 2>/dev/null`
- Test directories: !`ls -d __tests__ tests test src/__tests__ 2>/dev/null`
- Test scripts in package.json: !`cat package.json 2>/dev/null | grep -E '"test"' || true`
- Unstaged changes: !`git diff --stat`
- Staged changes: !`git diff --cached --stat`

Look for existing setup in this order:

1. Test config files (`vitest.config.*`, `jest.config.*`, `pytest.ini`, etc.) — see pre-run output
2. `package.json` test scripts — see pre-run output
3. Existing test files for patterns and conventions
4. If nothing found, see Scaffolding section below

Also detect:
- Where tests live — see pre-run directory output
- Naming conventions used in existing tests
- Import patterns and assertion style

The `git diff` pre-run feeds Diff-Based Mode — if the user gave no target, use the changed files from the diff output.

### 2. Analyze the Code

Read the target files and identify:

- **Public interfaces** — exports, public methods, API endpoints
- **Key behaviors** — what does this code do from a caller's perspective?
- **Inputs and outputs** — parameters, return values, thrown errors
- **Edge cases** — nulls, empty collections, boundary values
- **Side effects** — if any exist at system boundaries

Do NOT test:
- Private/internal functions
- Implementation details
- Code you'd have to mock extensively to isolate

### 3. Write Tests

For each identified behavior, write a test that:

- Describes WHAT the code does, not HOW
- Uses the public interface only
- Would survive an internal refactor
- Has a clear, descriptive name

Follow the project's existing conventions for:
- File location and naming
- Import style
- Assertion library
- Test organization (describe blocks, etc.)

If no conventions exist, use sensible defaults for the detected framework.

### 4. Run Tests

Execute the tests immediately after writing them.

- **All pass**: Report what was covered
- **Some fail**: This is a discovered bug, not a test error
  - Report the failure and what it reveals about the code
  - Do NOT silently adjust the test to make it pass
  - Ask the user: is this a bug to fix, or should the test expectation change?

### 5. Report

```
Tests written: 5
  src/actions/createOrder.test.ts — 3 tests (validation, calculation, error handling)
  src/utils/formatCurrency.test.ts — 2 tests (formatting, locale handling)
Passed: 5
Failed: 0
Not covered: createOrder webhook side effects (requires external service mock)
```

## Scaffolding

If no test framework is detected:

1. Identify the project language and runtime
2. Suggest a minimal framework (Vitest for Node/TS, pytest for Python, etc.)
3. Install it and create a minimal config
4. Add a test script to package.json (for Node projects)

Ask the user before installing dependencies.

## Principles

- **Behavior over implementation** — test what the code does through its public API
- **One behavior per test** — each test verifies one thing
- **Readable names** — test names are documentation: "calculates total from line items"
- **No mocking internals** — only mock at system boundaries (external APIs, databases)
- **Discovered bugs are valuable** — a failing test means the skill found something
