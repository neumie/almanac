---
name: test-flow
description: Use when locking down user paths as E2E regression tests. Explores the actual UI in a browser, proposes user flows, writes automated E2E tests (Playwright/Cypress/etc.), and runs them until green. Use this whenever the user says test flow, test path, test user journey, cover this flow, or wants regression tests for user-facing behavior.
---

# Test Flow

Lock down user paths as E2E regression tests. Explore the feature in a real browser, discover flows, write automated tests, and run them until green.

## Purpose

These tests exist to detect regressions. Once a user path works, it should keep working. The tests are the contract.

## Process

### 0. Verify Browser Tooling

Before exploring, confirm a browser MCP is available — Playwright MCP or `mcp__claude-in-chrome__*` tools. Without one, you'd be inventing selectors from JSX/HTML source, which produces brittle tests. If nothing is wired up, ask the user to install Playwright MCP, or fall back to `npx playwright codegen <url>` and have them paste the recorded interactions.

### 1. Detect E2E Framework

These commands run automatically when the skill loads — output replaces each line below:

- E2E config files: !`ls playwright.config.* cypress.config.* wdio.conf.* 2>/dev/null || true`
- E2E directories: !`ls -d e2e tests/e2e cypress/e2e test/e2e 2>/dev/null || true`
- E2E scripts in package.json: !`cat package.json 2>/dev/null | grep -E '"(e2e|playwright|cypress|test:e2e)"' || true`

Look for an existing setup in this order:

1. Config files (`playwright.config.*`, `cypress.config.*`, `wdio.conf.*`, etc.) — see pre-run output
2. `package.json` scripts referencing e2e or test runners — see pre-run output
3. Existing e2e test files for patterns and conventions
4. If nothing found, see Scaffolding section below

Also detect:
- Where e2e tests live — see pre-run directory output
- Naming conventions used in existing tests
- Page object patterns or test utilities already in place

### 2. Explore the UI

**Do not skip this step.** Open the browser and actually use the feature before writing anything.

1. Navigate to the relevant page or entry point for the feature
2. Click through it — follow the primary user path end-to-end
3. Note the actual UI elements: buttons, forms, navigation, states, loading indicators
4. Try obvious variations: empty states, validation errors, edge cases
5. Pay attention to what happens — URLs change, modals open, data updates, redirects occur

You are building a mental model of what the user actually experiences. Code analysis alone is not enough — the browser shows you reality.

### 3. Propose User Flows

Based on what you experienced in the browser, propose a list of flows:

```
I explored [feature] and found these user flows:

1. **Happy path** — [describe the primary successful journey]
2. **Validation** — [describe what happens with bad input]
3. **Empty state** — [describe the zero-data experience]
4. **[Other flow]** — [describe it]

Want to modify this list, add flows, or remove any?
```

Rules:
- Each flow is a complete user journey with a clear start and end
- Name flows by what the user is trying to do, not by what the code does
- Include the happy path first, then variations
- Be specific — "user submits form with empty required fields" not "validation"

**Wait for the user to approve, modify, or extend the list before continuing.**

### 4. Write Tests

For each approved flow, write an E2E test that:

- Replays the exact user journey from start to finish
- Uses selectors from the ladder below (never invent them from source)
- Asserts on user-visible outcomes (text appears, page navigates, element is visible)
- Is independent — each test can run in isolation
- Has a clear, descriptive name that reads like a user story

**Selector ladder** — use in order, only drop down when the above is ambiguous:

1. `getByRole` with accessible name
2. `getByLabel` for form controls
3. `getByText` for unique visible copy
4. `getByTestId` only when 1–3 are ambiguous
5. CSS/XPath as last resort, with a comment explaining why

Pull selectors from the live a11y snapshot (MCP), not from reading the source. If a selector matches multiple elements, narrow with role + name + scope — never `nth-child` or index.

Follow the project's existing conventions for:
- File location and naming
- Import style and test utilities
- Page object patterns (if any)
- Test data setup and teardown

If no conventions exist, use sensible defaults for the detected framework.

### 5. Run Tests

Execute the tests immediately after writing them.

**Before declaring green:** verify the test exercised the *intended* path, not a backdoor. Did the assertions pin user-visible outcomes that would actually break if the feature regressed? If the test passed by skipping a step, navigating directly to a success URL, or asserting something trivially always-true, fix the test — passing ≠ correct.

**If tests pass:** Move to the next flow.

**If tests fail — determine the cause:**

**A) Test is wrong** (bad selector, timing issue, wrong assertion, missing setup):
- Fix the test yourself. This is your mistake, not a bug in the app.
- Fix selectors by *narrowing* (more specific role + name + scope) — never by loosening. Never relax assertions to make a test pass. If a selector matches multiple elements, disambiguate scope rather than picking `nth-match`.
- Re-run until it passes.
- Do not ask the user about test-level issues.

**B) App is broken** (the test accurately represents the flow but the feature doesn't work):
- Stop and report the finding:

```
⚠ Found a regression: [flow name]

The test expects [expected behavior] but the app [actual behavior].
This appears to be a real bug, not a test issue.

Want me to investigate and fix it, or continue writing the remaining flow tests?
```

- Do not silently adjust the test to match broken behavior.

### 6. Report

When all approved flows have passing tests:

```
Flows tested: 4
  e2e/checkout.spec.ts
    ✓ user completes checkout with valid payment
    ✓ user sees validation errors for expired card
    ✓ user returns to cart from checkout
  e2e/checkout-empty.spec.ts
    ✓ user sees empty cart message when checking out with no items

All passing.
```

Then mention anything extra you noticed while exploring:

```
While exploring, I also noticed:
- A password reset flow accessible from the login page
- An invite-a-friend modal in account settings

Want me to cover any of these?
```

Only mention flows that are genuinely distinct — don't pad the list.

## Scaffolding

If no E2E framework is detected:

1. Identify the project's language, runtime, and frontend framework
2. Recommend Playwright as the default (or the most natural fit for the stack)
3. Install it and create a minimal config
4. Add an e2e test script to package.json (for Node projects)
5. Verify the setup works with a trivial navigation test before writing real tests

**Ask the user before installing dependencies.**

## Principles

- **Explore first** — always use the feature in a browser before writing tests
- **User perspective** — flows describe what a user does, not what the code does
- **Regression detection** — tests lock down working behavior so it stays working
- **Fix your own mistakes** — broken tests are your problem, broken features are the user's decision
- **Framework-agnostic** — detect what exists, default to Playwright
- **Independence** — each test runs on its own, no ordering dependencies
