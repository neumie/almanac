---
name: code-review
description: Use when reviewing changes since a fixed point (branch, commit, tag, or PR base). Runs independent behavior, architecture, security, and verification/operations reviews.
metadata:
  dependencies:
    - codebase-design
  upstream: mattpocock/skills/skills/engineering/code-review
  upstream-sha: 2a0b5240731b927caa9ac0bf43c3e2af9dc3f0a7
  adapted-date: "2026-07-31"
---

# Code Review

Review the diff between `HEAD` and a fixed point through four independent lenses:

- **Behavior** — spec conformance, scope, correctness, and reliability.
- **Architecture** — module design, maintainability, and repository standards.
- **Security** — trust boundaries, authorization, privacy, abuse resistance, and supply chain.
- **Verification & Operations** — tests, compatibility, performance, accessibility where relevant, and operability.

Run each lens in a separate read-only context so one kind of strength cannot mask another kind of failure. A finding must satisfy the evidence bar in [review-lenses.md](references/review-lenses.md); generic advice and hypothetical risks are not findings.

This is a review workflow. Do not edit the reviewed code unless the user separately asks for fixes.

## Process

### 1. Pin the fixed point

Whatever the user supplied is the fixed point: a commit SHA, branch, tag, `main`, `HEAD~5`, PR base, or similar. If they did not supply one, ask for it.

Resolve it before doing any review:

```sh
git rev-parse <fixed-point>
git diff --name-status <fixed-point>...HEAD
git diff --stat <fixed-point>...HEAD
git log <fixed-point>..HEAD --oneline
```

The canonical committed patch is `git diff <fixed-point>...HEAD` (three-dot, against the merge-base). If the user asked to review current work and the working tree is dirty, add `git diff HEAD` as a clearly labelled supplemental patch; never silently omit it.

Fail early on an invalid ref or an empty combined patch. Capture the diff commands and commit list once and give the same scope to every reviewer.

### 2. Gather shared context

Find sources before spawning reviewers.

**Spec**, in this order:

1. Issue references in commits (`#123`, `Closes #45`, and similar), fetched with `gh issue view <number> --comments`.
2. A path supplied by the user.
3. A branch-matching file under `docs/plans/`, `docs/`, or `specs/` (`spec.md`, legacy `prd.md`, or equivalent).
4. Ask once if none is found. If the user confirms there is no spec, continue: the Behavior reviewer marks spec conformance unverified but still reviews correctness and reliability.

**Repository rules:** relevant `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, style guides, and local instructions for changed directories.

**Architecture context:** relevant `CONTEXT.md`, `CONTEXT-MAP.md`, ADRs, dependency rules, and module documentation. Follow the `codebase-design` skill for architecture vocabulary and principles.

**Risk signals:** note whether the patch touches authentication, authorization, external input, secrets, personal data, persistence, migrations, public APIs, dependencies, infrastructure, concurrency, caching, or user interfaces. These signals focus conditional checks; they do not predetermine findings.

Read [review-lenses.md](references/review-lenses.md) in full. Identify the repository's normal validation commands. Run practical static checks and targeted tests once centrally, then pass their results to reviewers. Do not duplicate formatter or linter output as hand-written findings; report failed commands separately. Record any expensive or unavailable checks as unverified rather than implying they passed.

### 3. Spawn four reviewers in parallel

Spawn one read-only general-purpose sub-agent per lens in a single parallel batch. Give each a fresh context. If the host cannot run parallel sub-agents, run the lenses sequentially with fresh contexts; never collapse them into one review prompt.

Every prompt must include:

- the fixed point, exact diff command(s), changed-file list, and commit list;
- the relevant spec, rules, architecture-context paths, and validation output;
- the shared finding bar, severity scale, and output schema from `review-lenses.md`;
- the applicable lens contract from `review-lenses.md`, pasted in full because a child may not inherit this skill;
- instructions to inspect surrounding definitions, callers, tests, and configuration where needed to prove impact, not just read isolated diff hunks;
- instructions to remain read-only and return either evidence-backed findings or `No findings`.

Use these lens briefs:

1. **Behavior:** compare the patch with the spec and apply the Behavior contract. Find missing or unintended behavior, concrete correctness defects, violated invariants, edge cases, and failure-mode problems.
2. **Architecture:** follow the `codebase-design` skill and apply the Architecture contract. Check changed module interfaces, seams, dependency direction, locality, testability, documented decisions, repository standards, and maintainability smells.
3. **Security:** apply the Security contract. Trace changed data and control flow across trust boundaries; check authorization at the operation/object level and seek a concrete exploit or abuse path before reporting.
4. **Verification & Operations:** apply that contract. Assess whether tests prove changed behavior and conditionally check compatibility, migrations, performance, accessibility/UX states, rollout safety, and observability.

### 4. Aggregate without masking

Present findings first, grouped under these headings and sorted by severity within each:

- `## Behavior`
- `## Architecture`
- `## Security`
- `## Verification & Operations`

Keep lens attribution. Deduplicate only when two reports identify the same root cause and consequence; retain both lens labels on the surviving finding. Do not promote stylistic preferences into blockers and do not include pre-existing issues unless the patch materially worsens them.

Then add:

- `## Validation` — commands actually run and their exact pass/fail status.
- `## Coverage & Residual Risk` — missing spec, unreadable context, checks not run, conditional areas judged not applicable, and unresolved uncertainty.
- `## Summary` — counts by severity and lens plus the worst issue in each lens.

Use `Blocked` when a concrete P0 or P1 remains; otherwise use `No blocking findings`. The latter is not a claim that the change is safe or bug-free. Never say the review or tests passed when required context or validation was unavailable.

## Why Separate Lenses

A patch can implement the requested behavior while weakening authorization, follow every style rule while creating a shallow module, or carry excellent tests for the wrong behavior. Independent contexts and separate reporting prevent one success from averaging away an unrelated failure.
