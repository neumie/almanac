---
name: harden-loop
description: "Use when hardening a target (file, PR, module, diff) to an explicit contract — parallel read-only reviewers, ratify-by-execution, single fixer, convergence loop. Triggers: harden, make bulletproof."
disable-model-invocation: true
metadata:
  source: docs/plans/harden-loop/prd.md (technique only — no upstream SKILL.md to SHA-sync)
  adapted-date: "2026-05-25"
---

# Harden Loop

A **convergence loop** that hardens one target until it meets an explicit, per-task contract. You give it a target and a one-line goal; the conductor drafts a `rubric.md`; you edit and lock it; then it runs **rounds** of parallel review → ratify-by-execution → fix → feedback until the target is bulletproof or a round budget is hit.

Unlike `ralph-loop` (a slice-queue loop that builds a PRD task-by-task), harden-loop is **review-driven**: it discovers and fixes defects in code that already exists. Both sit on the same shared bash engine (`lib/loop-core.sh`), exposed as `almanac harden <target>`.

## The contract: convergence, not infinite review

LLM reviewers never stop finding things — they drift into subjective opinions ("I'd prefer composition here") and the bar silently rises every round, so the loop runs forever. harden-loop fixes this:

- Every finding must carry a **demonstration** — a failing test, a specific breaking input, or a cited rubric violation.
- The conductor **ratifies by execution**: a finding is **blocking** only if its demonstration actually reproduces against the current code. Unreproducible findings and pure opinion become **non-blocking notes** — visible, but they never gate the loop.
- The bar (`rubric.md` `## Acceptance`) grows **only** by ratified, falsifiable criteria — monotonically, visibly, as a diff.

Because real defects are finite, opinions can't produce a failing test, and green checks stay green (a ratchet), the loop **terminates**: convergence = a round adds zero new falsifiable findings AND every acceptance criterion is met. If it keeps finding real, test-backed bugs, *not* converging is the correct answer — and you see why.

## CLI

Run from the repo holding the target. All state lives under `docs/plans/harden/<target-slug>/` (rubric + findings ledger) and `.almanac/` (runtime).

```bash
almanac harden <target> --goal "<one-line goal>"   # draft rubric.md
# edit docs/plans/harden/<target-slug>/rubric.md by hand
almanac harden <target> --approve                  # lock the contract
almanac harden <target> --loop [--rounds N]        # run the convergence loop
```

Other modes:

| Command | What it does |
|---------|--------------|
| `almanac harden <target>` | One round: fan out one read-only reviewer per lens, aggregate findings into the ledger, print them. Gated on an approved rubric if one was drafted; runs ad-hoc if none exists. |
| `almanac harden <target> --goal "<goal>"` | Draft `rubric.md` (Goal, Acceptance, In/Out of scope, Severity, Context) from the target + goal. Refuses to overwrite an existing rubric. |
| `almanac harden <target> --approve` | Mark an edited draft `Status: approved` — the lock the loop enforces. |
| `almanac harden <target> --fix` | Run one sequential write-capable fixer over the open blocking findings, then the project's feedback loops, reporting a pass/fail verdict per loop. |
| `almanac harden <target> --loop [--rounds N]` | The full convergence loop: fan-out → ratify → fix → feedback → gate, in rounds, until converged or the budget is hit (default 5). HITL checkpoint each round. |
| `almanac harden <target> --watch` | Redraw the live supervision dashboard for the target's most recent run. |
| `almanac harden <target> --watch-worker <lens\|worker-id>` | Stream one reviewer's live event log (e.g. `security` or `reviewer-security`). |

`<target>` is any ref you can describe — a PR, a file, a module, a diff. A target with **no** `docs/plans` entry runs ad-hoc, with the rubric created on the fly.

## A round

`--loop` repeats this until the gate says stop:

1. **Fan out** N reviewers in parallel, one per lens, **read-only** against the target (no worktrees needed — reviewers never write). Each emits structured findings, each with a demonstration.
2. **Ratify by execution.** The conductor runs each finding's demonstration. Reproduces → **blocking**, and the criterion is appended to `rubric.md`. Otherwise → **non-blocking note**.
3. **Fix.** A single sequential write-capable fixer applies the open blocking findings and leaves a failing-then-passing regression test per fix. No concurrent writers.
4. **Feedback.** The project's feedback loops (tests / typecheck / lint) run — the objective half of "bulletproof", reusing the repo's existing detection.
5. **Gate.** Exit when acceptance is met AND zero open blocking findings remain, or the round budget is hit (a clear NON-CONVERGED status). Each round prints the **kill-list** (open blocking findings) and a **verdict**.

The deliverable is hardened code **plus the regression suite the loop built to prove it**.

## Lenses

Reviewers fan out one per lens. Default lens set: `correctness security perf edge-cases contracts`. Override per run:

```bash
HARDEN_LENSES="correctness security thread-safety" almanac harden <target> --loop
```

Comma- or whitespace-separated; no enforced cap on reviewer count — you decide throughput and cost.

## Providers per role (Claude or Codex)

Every role — **conductor** (judges/ratifies), **reviewer** (one per lens), **fixer** — selects its own `(provider, model, effort)`. Resolution layers most-specific first and reads only `HARDEN_*` env, so it is identical whether you launched from Claude Code or Codex:

```
HARDEN_<ROLE>[_<LENS>]_{PROVIDER,MODEL,EFFORT}  →  HARDEN_<ROLE>_*  →  HARDEN_*  →  default (claude)
```

Only reviewers consult the lens, so providers **mix across lenses in one round** — different model families catch different defects:

```bash
HARDEN_REVIEWER_SECURITY_PROVIDER=codex \
HARDEN_REVIEWER_CORRECTNESS_PROVIDER=claude \
HARDEN_FIXER_PROVIDER=claude \
  almanac harden <target> --loop
```

Defaults are sensible (`provider=claude`, the provider's own default model/effort) and overridable per role.

## Supervision

You supervise through the CLI, not by chatting with one model:

- **Dashboard** (`--watch`) — a `gum`-styled redraw loop showing reviewer status + health, round, findings tallies, rubric progress, and the feedback verdict. Stalled / idle / looping workers are detected and surfaced.
- **Watch one worker** (`--watch-worker <lens>`) — tail a single reviewer's live event stream when you care to.
- **HITL checkpoint** — between rounds the loop pauses on a `continue` verdict and offers **ship / continue / steer**. Drive it non-interactively with `HARDEN_HITL=ship|continue|steer`.
- **Steer** — `steer` captures a directive (interactively, or from `HARDEN_STEER`) that threads into every subsequent round's reviewers and fixer, so you can redirect or amend the run between rounds. The rubric is **immutable to agents during a run** — only you amend it directly between rounds; an edit is picked up on the next round.

## Round budget

A hard cap so a pathological target can't loop forever:

```bash
almanac harden <target> --loop --rounds 8     # or HARDEN_ROUND_BUDGET=8
```

Reaching the budget without convergence exits NON-CONVERGED — the honest answer when real bugs remain.

## gum is optional

The dashboard and HITL prompts use [`gum`](https://github.com/charmbracelet/gum), a single optional Go binary. When `gum` is absent (or output is piped, or `ALMANAC_NO_GUM=1`), the CLI **degrades gracefully** to plain output — almanac keeps its near-zero-dependency promise. Run `almanac doctor` to check whether `gum` is installed.

## Notes

- Reviewers are read-only and the fixer is a single sequential agent, so v1 needs **no worktrees** and has no parallel-writer conflicts.
- The findings ledger adjudicates each finding once, so a rejected subjective finding can't be re-litigated every round; a finding reopens only if the code changed in a way that re-triggers its demonstration.
- Out of scope for v1: a fully autonomous headless conductor, interactive "take the wheel" on a worker, parallel fixers + worktrees, GitHub PR comment integration, multi-target batch runs, and any dangerous-command safety gating (the loop oversees progress and correctness, not safety).
