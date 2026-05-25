## Problem Statement

I regularly want to point an agent at something — a PR, a file, a module, a diff — and say "review this and fix it until it's bulletproof." What "bulletproof" means is different for every task, and I want to define it per task.

The recurring failure is **non-convergence**. When the bar is tight, LLM reviewers never stop finding things: they drift into *subjective* findings ("I'd prefer composition here," "this could be cleaner," speculative "what if" concerns). Each round invents new opinions, so the bar silently rises every round and the loop runs forever. But a *frozen* bar is no answer either — the whole point of the loop is to let the agents discover real problems I didn't know about up front.

I also want to **supervise** the run — see that the workers are doing what they're meant to do and aren't stuck — and spin up several worker instances for throughput and diverse perspectives, **without babysitting each one** and without a safety guard watching for dangerous commands (that is not the concern here; progress and correctness are).

Finally, I don't want a one-off. I want a **proper, good-looking CLI** for this, and I want the *same* engine to power almanac's existing `ralph` loop — one orchestration runtime, not two.

## Solution

`harden-loop` is a **convergence loop** that hardens one target until it meets an explicit, per-task contract, run from a shared CLI: `almanac harden <target>`.

You give it a target and a one-line goal. The conductor drafts a `rubric.md` contract; you edit and lock it. Then it runs **rounds**:

1. **Fan out** N reviewers in parallel, one per lens (correctness, security, perf, edge-cases/tests, contracts), read-only against the target. Each emits **structured findings**, and each finding carries a **demonstration** — a failing test, a specific breaking input, or a cited rubric violation.
2. **Ratify by execution.** The conductor runs each finding's demonstration. A finding is **blocking** only if its test/input actually reproduces against the current code. Unreproducible findings and pure opinion are recorded as **non-blocking notes** — visible, but they never gate the loop.
3. **Fix** the blocking findings, then run the project's feedback loops (tests / typecheck / lint).
4. **Grow the bar.** Ratified findings append to `rubric.md`'s acceptance list — monotonically, visibly, as a diff.

The bar is allowed to **grow**, but only via falsifiable, ratified criteria. Because real defects are finite and front-loaded, opinions cannot produce a failing test, and green tests stay green (a ratchet), the loop **terminates**: convergence = a full review round adds zero new falsifiable findings AND every acceptance criterion is met. If it keeps finding real, test-backed bugs, the target genuinely isn't bulletproof yet — *not* converging is the correct answer, and you see why.

Every role — **conductor/overseer, reviewers, fixer** — is a pluggable provider (**Claude or Codex**), switchable per role, with reviewers *mixable* across providers so different model families catch different defects in the same round. You run the CLI and supervise through a live, `gum`-styled dashboard (reviewer status, round, findings tallies, rubric progress, feedback verdict) plus steer keys and `gum` HITL prompts — you do not chat with one fixed model. The deliverable is hardened code **plus the regression suite the loop built to prove it.**

The orchestration runtime is a **shared bash engine**; `almanac ralph` is refactored onto it as the second consumer.

## User Stories

1. As a developer, I want to point the loop at a target (PR, file, module, or diff) with a one-line goal, so that I can start hardening without writing a full spec first.
2. As a developer, I want the conductor to draft a `rubric.md` contract from my target and goal, so that I get a starting bar without authoring it from scratch.
3. As a developer, I want to edit and approve the drafted rubric before the loop runs, so that the real bar and the context only I know get injected.
4. As a developer, I want the rubric to capture intentional decisions ("this swallowed error is deliberate," "this O(n²) is fine, n<10"), so that reviewers stop flagging known false positives.
5. As a developer, I want each round to spin up several reviewers in parallel, each with a distinct lens, so that I get broad, diverse coverage in one pass.
6. As a developer, I want reviewers to run read-only against the target, so that they cannot mutate the code and need no isolation.
7. As a developer, I want every reviewer finding to carry a concrete demonstration (failing test, breaking input, or cited criterion), so that opinions without evidence are separable from real defects.
8. As a developer, I want the conductor to ratify a finding by actually executing its demonstration, so that "blocking" means objectively reproducible, not a reviewer's assertion.
9. As a developer, I want subjective or unreproducible findings recorded as non-blocking notes, so that I can still see them but they never keep the loop alive.
10. As a developer, I want ratified findings to grow the rubric's acceptance criteria monotonically and visibly, so that the bar moves up in the open and never silently drifts.
11. As a developer, I want a findings ledger that adjudicates each finding once, so that a rejected subjective finding cannot be re-litigated every round.
12. As a developer, I want a re-raised finding to reopen only if the code changed in a way that re-triggers its demonstration, so that churn is impossible.
13. As a developer, I want a single sequential fixer to apply changes, so that there is no parallel-writer merge conflict and no worktrees are needed.
14. As a developer, I want the project's feedback loops (tests/typecheck/lint) run every round, so that the objective half of "bulletproof" is enforced automatically.
15. As a developer, I want the loop to exit when a full round adds zero falsifiable findings and all acceptance criteria are met, so that convergence is a real, terminating condition.
16. As a developer, I want a hard round budget as a safety cap, so that a pathological target cannot loop forever.
17. As a developer, I want a HITL checkpoint where the dashboard reports each round's kill-list and verdict, so that I can say "ship it" or "keep going."
18. As a developer, I want to steer or amend the contract while the loop runs, so that I supervise without babysitting each worker.
19. As a developer, I want to watch any single reviewer's live event stream, so that I can see what a worker is doing when I care to.
20. As a developer, I want the loop to detect a stuck or stalled reviewer (no progress, looping), so that I am told rather than discovering it myself.
21. As a developer, I want the contract immutable to the agents during a run (only I amend it directly), so that the goalposts move only by a deliberate human act.
22. As a developer, I want the lens set configurable per task, so that I can add (e.g.) thread-safety or drop perf when it does not apply.
23. As a developer, I want the number of parallel reviewers to be a runtime argument with no enforced cap, so that I decide throughput and cost.
24. As a developer, I want the loop to reuse the repo's existing feedback-loop detection, so that it works across project types without per-project config.
25. As a developer, I want the final output to include the regression tests the loop generated, so that "bulletproof" is executable and stays enforced afterward.
26. As a developer, I want the loop to work on a target with no docs/plans entry yet, so that I can harden ad-hoc things, with the rubric created on the fly.
27. As a developer, I want to choose which provider (Claude or Codex) plays the conductor/overseer role, so that I can use whichever model I trust to judge findings.
28. As a developer, I want to choose the provider for the reviewers, so that I can pick the model family that reviews best for my code.
29. As a developer, I want to mix providers across reviewer lenses (some Codex, some Claude), so that different model families catch different classes of issue in one round.
30. As a developer, I want to choose the provider for the fixer, so that the agent applying changes is the one I prefer.
31. As a developer, I want per-role model and thinking-effort overrides (like ralph's RALPH_MODEL / RALPH_EFFORT), so that I can tune cost and depth per role.
32. As a developer, I want to run the loop from either host (Claude Code or Codex), so that the agent I talk to is independent of which providers do the work.
33. As a developer, I want a good-looking CLI with a live dashboard, so that supervising a fleet feels like a real tool, not a shell script.
34. As a developer, I want the same engine to power `almanac ralph`, so that there is one orchestration runtime to learn and maintain, not two.
35. As a developer, I want the CLI to degrade gracefully when `gum` is absent, so that the rest of almanac keeps its zero-dependency promise.
36. As a maintainer, I want harden-loop to follow almanac's authoring, validation, and doc-sync rules, so that it lands consistently with the rest of the repo.

## Implementation Decisions

**Form factor — a shared bash CLI engine, two consumers.** The orchestration runtime is a set of shared bash libraries built on `lib/core.sh` and styled with Charm's `gum`, exposed as `almanac harden <target>` and `almanac ralph <prd>`. harden-loop's loop *logic* is a convergence loop (review rounds + ratification), distinct from ralph's slice-queue loop; both sit on the same engine. ralph's existing scripts are refactored onto the engine in a later, careful phase that preserves today's behavior — harden is the engine's first consumer, ralph the second.

**Stack — bash + `gum`.** No compiled binary, no runtime, to keep almanac's near-zero-dependency install. The accepted cost: no true TUI. The dashboard is a `gum`-styled **redraw loop** (`clear` + reprint of composed styled blocks read from per-worker state files), with mild flicker and no smooth per-cell animation. `gum` itself is one new optional dependency (a single Go binary); install/doctor detects it and the CLI **degrades gracefully** to plain output when it is absent.

**The CLI is the conductor runtime; conductor judgment is a configured agent call.** You run `almanac harden`; the bash engine drives the loop and renders the dashboard. The judgment work — ratify findings, filter, decide fixes, declare convergence — is an agent-runner call to the *configured conductor provider*, not hardcoded to the host you launched from. You interact through the CLI (dashboard + steer keys + `gum` prompts), not by chatting with one fixed model. Provider selection for every role ships in v1; a fully autonomous headless run is a later increment.

**Major modules** (favoring deep modules with simple, testable interfaces; "shared" = used by both harden and ralph):

- **Agent runner (shared).** A uniform interface over both providers: (provider, model, effort, sandbox, prompt, output schema / last-message) → (event stream, structured result). Generalizes ralph's dual-provider exec branches into one seam every role calls. The substrate that makes roles pluggable.
- **Role config (shared).** Conductor, reviewer, and fixer roles each carry provider + model + effort. Reviewers map lens → provider, so providers can be mixed across lenses. Sensible defaults, overridable per role (ralph-style env vars / args), no enforced cap on reviewer count.
- **Worker orchestration (shared).** Spawns background agent-runner processes, tracks PID + per-worker log/status files, detects stall (log mtime not advancing), idle, and loop, and collects results.
- **Reviewer fan-out.** Spawns N reviewers in parallel (provider per lens, via the agent runner) as background, **read-only** processes, one per lens, each constrained by the rubric and emitting structured findings via the findings schema. Interface: (target ref, lens→provider map, rubric, concurrency) → aggregated raw findings. Because reviewers never write, v1 needs **no worktrees**.
- **Findings schema + parser.** A fixed schema for a finding: lens, severity, location, claim, and a demonstration (proposed failing test, breaking input, or cited rubric criterion). The parser normalizes reviewer output into ledger entries and rejects malformed output cleanly.
- **Findings ledger.** Append-only record: id, lens, severity, status (`open` | `fixed` | `rejected-subjective` | `wontfix-per-context`), round, demonstration, adjudication note. Pure data operations: add, dedupe against prior adjudications, mark status, query open-blocking.
- **Ratification engine.** Given a finding + demonstration, decide blocking vs. note by executing the demonstration: reproduces against current code → blocking, and the criterion is appended to the rubric; otherwise → non-blocking note. Dedupes against the ledger (already-adjudicated findings auto-drop unless the code changed to re-trigger).
- **Rubric contract.** `rubric.md` with sections: Goal, Acceptance (objective/checkable), In scope, Out of scope (+ non-goals), Severity (what blocks vs. notes), Context (intentional decisions / false-positive pre-emptions). Amendment is a controlled append (visible diff); agents propose, conductor/human ratifies. Immutable to agents during a run.
- **Convergence gate.** A pure predicate: exit when all Acceptance items are met AND zero open blocking findings remain (optionally requiring N consecutive clean rounds), or the round budget is hit. Reports the verdict each round.
- **Feedback-loop runner (shared — extracted from ralph).** Reuses ralph's detection (package.json → npm test/typecheck/lint, Makefile, Cargo/go/python equivalents, this repo's own test scripts) to run the objective gate every round; one implementation for both consumers.
- **UI primitives (shared).** `gum`-based styling helpers (header, bordered panel, status dot, key/value row, table) plus the redraw loop composing a dashboard from worker-state files. Each consumer composes its own layout; render logic (state → printable rows) is kept pure so it can be tested without a terminal.

**Convergence invariants.** The bar grows monotonically (criteria are only added, never silently removed); a finding raises the bar only if falsifiable (test / input / criterion); green checks stay green (regression ratchet); subjective notes never gate.

**Falsifiability bar (chosen).** "Concrete demonstration" — a failing test OR a specific breaking input/repro OR a cited criterion violation — biased toward automated tests wherever possible. Stricter (test-only) would resist hard-to-automate real issues; looser reopens the subjectivity hole.

**Reuse, don't duplicate.** Reviewer prompts draw on the `code-review` skill; fixers draw on `ci-fix`/`diagnose`; codex/claude invocation and feedback-loop detection draw on `ralph-loop`; the contract borrows the acceptance-criteria discipline from `issues-create-local`.

**Almanac conventions.** The shared engine lives in new lib(s) (e.g. `lib/loop-core.sh`) sourced like `lib/core.sh`, using `_die`/`_info`/`_success`/`_warn`/`_error` — never raw `echo`. New skill-format rules extend `almanac_validate_skill()`; layout rules extend the structure test. User-facing instructions print absolute `~/.claude/skills/almanac/harden-loop/scripts/…` paths. Adding the skill triggers doc-sync (README, ARCHITECTURE, CONTRIBUTING) in the same commit.

## Testing Decisions

- **What makes a good test:** assert external behavior of the deep modules, not their internals. Given synthetic inputs (findings JSON, a rubric, round state, project marker files, worker-state inputs), assert the output (ratification verdict, ledger transition, gate decision, detected commands, printable rows). Do not assert on prompt strings or provider internals.
- **Modules to test:**
  - *Findings ledger* — add / dedupe / status-transition / open-blocking-query over synthetic findings.
  - *Ratification engine* — decision logic (reproducible → blocking + rubric-append; not reproducible → note; already-adjudicated → drop), with demonstration *execution* mocked behind a seam.
  - *Convergence gate* — predicate over (acceptance state, open-blocking count, round budget): exits exactly when it should, never early, never forever.
  - *Findings parser* — malformed / partial reviewer output is normalized or rejected cleanly.
  - *Agent runner* — given a role config, it builds the right invocation per provider and parses each provider's result into the common shape; tested behind a fake provider executable, no real model calls.
  - *Role config resolution* — defaults + per-role env/arg overrides resolve to the expected (provider, model, effort) per role, including mixed lens→provider maps.
  - *Feedback-loop detection* — given a set of project marker files, the correct command list comes back (table-driven, no execution).
  - *Render logic* — given worker-state inputs, the dashboard composer returns the expected printable rows/sections (pure function; `gum`/terminal not involved).
- **Reviewer fan-out** is integration-tested behind a **mock provider** (a fake runner emitting canned events + findings): asserts N reviewers spawn with the right per-lens providers, run read-only, and aggregate — without real model calls.
- **Skill format** is validated by `almanac_validate_skill()` via `tests/test-skills.sh`; **layout** by `tests/test-structure.sh`. Both run after any skill edit.
- **Prior art:** ralph-loop's scripts (provider invocation, feedback-loop detection); the `tests/test-skills.sh` / `tests/test-structure.sh` harness; `cmd/*.sh` + `lib/core.sh` helper conventions.

## Out of Scope

- **Autonomous headless conductor.** Provider *selection* for every role (incl. conductor) is in v1; a self-running conductor loop with no human present (ralph-overseer style) is later.
- **Live "take the wheel."** Attaching an interactive TUI to a running worker to type at it yourself (codex `app-server` / `remote-control` / `--remote`) is deferred — read-only watching + redirect-through-the-conductor covers v1.
- **Parallel fixers + worktree fan-out.** v1 uses a single sequential fixer (any provider), so there are no concurrent writers and no worktrees. Multiple fixers at once — and the worktree isolation + sequential merge they require — only earn their keep when findings cluster into disjoint files; a later increment.
- **GitHub PR integration.** Posting findings as inline PR comments and PR-status gating are out for v1.
- **Multi-target batch.** v1 hardens one target per run.
- **Safety / policy interception.** The loop oversees progress and correctness, not dangerous-command gating; no mid-turn approve/deny machinery.
- **True TUI dashboard.** Bubble Tea / ratatui-grade live UI is explicitly out — the stack is bash + `gum`, so the dashboard is a styled redraw loop. Accepted ceiling, chosen to keep a near-zero-dependency install.

## Further Notes

- **Build order — engine-first, crawl-first.** Build the shared engine (agent runner, role config, orchestration, feedback detection, UI primitives), then `almanac harden` on top: draft/lock rubric → parallel read-only reviewers → ratify-by-execution → single sequential fixer → feedback loops → gate. Defer autonomous headless, take-the-wheel, and parallel fixers. Port ralph onto the engine afterward.
- **Why no worktrees in v1:** reviewers are read-only and the fixer is a single sequential agent (any provider), so there are no concurrent writers to isolate. Worktrees return only with parallel fixers.
- **Cross-provider reviewing is a feature, not just a knob:** running some lenses on Codex and others on Claude in the same round surfaces defects one model family alone would miss. The lens→provider map makes this first-class.
- **Related prior art in-repo:** `pr-watch` (watch → auto-fix via `ci-fix` → bounded retries) is the same loop shape with a poorer failure signal; harden-loop generalizes it to review-driven findings with provider fan-out.
- **`gum` rendering is proven:** a mock dashboard (rounded panels joined horizontally, color-coded status dots, findings tallies, rubric/feedback strip, footer with live action + steer keys) renders cleanly at 256-color; the only trade vs a compiled TUI is buttery live motion.
