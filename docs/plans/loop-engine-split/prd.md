## Problem Statement

The loop engine works, but it has converged into shapes that fight maintenance and AI-navigability:

- **`lib/loop-core.sh` is a 1619-line god-module** holding eleven loosely-cohesive concerns (run registry, role config, agent run, worker orchestration, feedback, UI seam, worker health, hub views, run control, new-run composer). Answering "how does an agent run?" means scrolling past UI and registry code to line ~480 of one file.
- **Provider knowledge is smeared across ~6 sites.** `detect_provider` is copy-pasted in `once.sh`/`afk.sh`; provider availability is checked in at least six places; model/effort menus live only in the launcher; the `codex …`/`claude …` invocation details + the `sandbox`→permission mapping + the event-stream jq filters live inside `agent_run` (and the filter is duplicated again in `agent_stream`). Adding or updating a provider is an edit hunt.
- **`agent_run` is a 9-positional-arg multiplexer** with overlapping modes (`stream`/`raw`/silent) + a `merge_stderr` toggle + hidden validity rules (`raw` is codex-only; `stream` needs an events file). A caller can't tell what will happen from the call.
- **The launcher hard-codes ralph's filesystem path** (`…/ralph-loop/scripts/once.sh`), so a new loop can't plug in without editing the central launcher.
- **`ALMANAC_HOME` resolution is duplicated four ways** with subtle differences — one copy missing `pwd -P`, which is the exact symlink bug that broke `almanac ralph` this session.
- **The run-status schema is enumerated in every caller** (register/mark/update/hub each list the fields); adding a field means editing the writer and every reader, and the "all loops emit an identical key set" contract is only held by a test.
- **Almost none of this is unit-tested through its interface** — provider/agent logic is only reachable via full end-to-end loop runs.

The friction is poor **locality** (a change touches many files), weak **leverage** (no small interface concentrates provider/loop knowledge), and a large **shallow-at-the-top** surface that is hard to test in isolation.

## Solution

Deepen the engine around **two auto-discovered adapter seams** and carve the god-module into cohesive modules, each with a small interface that is its own test surface. This is a **behavior-preserving refactor**: the user-facing behavior of `almanac ralph`, `almanac harden`, and the hub is unchanged; the existing test suite is the safety net.

- A **provider adapter** seam: each backend (`codex`, `claude`) is a drop-in file answering one fixed question set. The seam is **deep on invocation** — the adapter yields the exec argv (including the sandbox→permission mapping) and its event-stream filter; nothing outside an adapter contains a `codex …`/`claude …` literal. Adding a provider is one new file.
- A **loop adapter** seam, symmetric: each loop (`ralph`, `harden`) is a drop-in file declaring a **launch** contract (config fields + how to exec its runner) and a **control** contract (its stop/steer signal files). The launcher consumes launch; the hub consumes control; no central `case "$type"`, no hard-coded paths.
- **Agent run becomes three intention-revealing shapes** — `agent_capture`, `agent_stream`, `agent_raw` — instead of one mode-parametric function. Each takes only what its shape needs; there are no invalid combinations to guard.
- A **run-status record** module owns the canonical field list, so the cross-loop run-status contract is enforced by construction, not by a test.
- **One standardized `ALMANAC_HOME` bootstrap** (prefer exported, else `pwd -P` at known depth) replaces the four drifting copies.
- **`loop-core.sh` is deleted** (not kept as a barrel); each caller sources only the modules it uses, which also removes the silent whole-engine dependency.

The payoff: "add a provider" or "add a loop" is a single drop-in file; provider/SDK churn lands in one place; each module is unit-testable behind a fake `command -v`; and a reader finds "how an agent runs" in `lib/agent.sh`, not buried in a 1619-line file.

## User Stories

1. As a maintainer, I want all knowledge about a provider in one adapter file, so that updating a model list or a permission mapping is a single edit.
2. As a contributor, I want to add a new provider by dropping in `lib/providers/<name>.sh` that implements the contract, so that nothing central needs editing.
3. As a maintainer, I want provider adapters auto-discovered from the files present, so that the provider list is never a second place to update.
4. As a maintainer, I want each provider adapter to answer a fixed question set (`available`, `active_env`, `models`, `efforts`, `display`, `argv`, `filter`), so that callers never branch on provider name.
5. As a maintainer, I want the adapter to own the exec argv and the event-stream filter (deep invocation), so that no `codex …`/`claude …` literal lives outside an adapter.
6. As a developer, I want `agent run` to be three named shapes (`agent_capture`, `agent_stream`, `agent_raw`), so that a call reads as intent and there are no invalid mode combinations.
7. As a developer, I want the event-stream filter defined once (in the adapter), so that a schema fix is one edit, not four.
8. As a maintainer, I want a single default-provider policy (active-env if available, else preference order), so that ralph's runtime detection and the launcher's menu agree.
9. As a contributor, I want to add a new loop by dropping in `lib/loops/<name>.sh` with launch + control contracts, so that the launcher and hub pick it up without edits.
10. As a maintainer, I want the launcher to exec a loop's runner via the loop adapter, so that no central code hard-codes a loop's filesystem path.
11. As a developer, I want the launcher to remain usable standalone (`almanac ralph --prd x` with no dashboard), with the hub embedding it for New-run, so that the scripted/non-TTY path never opens a menu.
12. As a maintainer, I want the hub's stop/steer to read each loop's signal files from its adapter's control contract, so that loop-specific control lives with the loop.
13. As a developer, I want one run-status record module that owns the field list, so that adding a field is one edit and the cross-loop contract can't drift.
14. As a developer, I want callers to set/get run-status fields by name, so that no caller enumerates the schema.
15. As a maintainer, I want one `ALMANAC_HOME` bootstrap snippet in every entry point, so that a missing `pwd -P` can't reintroduce the install-symlink bug.
16. As a maintainer, I want `loop-core.sh` deleted and replaced by focused modules, so that understanding one concern doesn't require reading ten others.
17. As a maintainer, I want each caller to source only the modules it uses, so that dependencies are explicit and the silent whole-engine import is gone.
18. As a developer, I want each module's interface to be its test surface, so that provider/agent/record/role logic is unit-testable behind fakes instead of only via end-to-end runs.
19. As a user, I want `almanac ralph`, `almanac harden`, and the hub to behave exactly as before, so that the refactor is invisible at the surface.
20. As a maintainer, I want the existing test suites to stay green throughout, so that behavior preservation is provable at each step.
21. As a maintainer, I want the refactor sequenced so each step is independently shippable, so that the engine is never left half-migrated for long.

## Implementation Decisions

**This is a behavior-preserving refactor.** No surface behavior changes; the existing suites (`test-ralph-smoke`, `test-hub`, `test-ralph-run-registry`, `test-loop-core`, `test-harden-cli`, `test-ralph-prompt`, `test-ralph-push`, `test-structure`, `test-skills`) must stay green at every step, and new unit tests are added per extracted module.

**Two adapter seams (the spine).**
- **Provider adapter** — auto-discovered at `lib/providers/<name>.sh`; the provider list is the files present. Contract: `available`, `active_env`, `models`, `efforts`, `display`, `argv`, `filter`. **Deep invocation**: `argv` yields the exec tokens (including the sandbox→permission mapping and `--json`-or-not by shape); `filter` yields the jq event-stream program. The one central remainder is **default-selection** policy (active-env provider if available, else preference order `claude` → `codex`).
- **Loop adapter** — auto-discovered at `lib/loops/<name>.sh`. Declares a **launch** contract (config fields + how to exec its runner) and a **control** contract (its stop/steer signal files). The launcher uses launch; the hub uses control. **launcher ⊂ hub**: the launcher is the create-flow (standalone *and* embedded in the hub), the hub adds run management.

**Agent run.** Replace the mode-parametric `agent_run` with three shapes — `agent_capture` (stdout → events file, silent), `agent_stream` (tee events + filtered live text to terminal), `agent_raw` (native passthrough, no filter/events). They consume the provider adapter's `argv` + `filter` and own only execution mechanics (exec, capture, `PIPESTATUS` exit threading, optional merge-stderr). `(provider, model, effort, sandbox)` stay positional — role config hands those four over together.

**Run-status record.** A module owns the canonical field list (`id, type, target, pid, status_file, started_at, status, finished_at, round, summary`). Callers `set`/`get` by name; set round-trips and preserves other fields; no caller enumerates the schema. This *is* the run-status contract.

**Home resolution.** One identical bootstrap in every entry point: prefer an exported `ALMANAC_HOME`, else self-resolve with `pwd -P` at the known depth.

**Module map (`lib/`).** `loop-core.sh` is deleted; its concerns move to: `core.sh` (CLI helpers + home resolve), `ui.sh` (gum-or-plain seam), `role.sh` (role → provider/model/effort), `agent.sh` (the three shapes + provider dispatch), `providers/<name>.sh`, `loops/<name>.sh`, `feedback.sh` (detection + runner), `run.sh` (registry + run-status record + control + worker health + hub read-views), `worker.sh` (background fan-out), `loop-launcher.sh` (the launcher), `harden-core.sh` (declares its real deps). Callers source only the modules they use; skill entry points (`once.sh`/`afk.sh`/`prompt.sh`) bootstrap `ALMANAC_HOME` then source their specific modules.

**Sequence (dependency-ordered).** #5 home bootstrap → #1 provider adapters → #2 agent shapes → #4 run-status record → #6 loop adapters → #3 carve the remaining concerns + delete `loop-core.sh`. Each extraction is its own behavior-preserving step.

**Conventions to uphold (from CLAUDE.md).** CLI/output helpers stay in `lib/core.sh`; skill-format validation stays in `lib/almanac-core.sh`. `cmd/*.sh` use `_die`/`_info`/etc., never raw `echo`. `tests/test-structure.sh` is updated as files move; doc-sync (`README`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`) tracks the new layout.

## Testing Decisions

- **What makes a good test:** assert external behavior through a module's interface, not its internals. The adapter seams make this possible behind fakes (a fake `command -v` / fake provider executable) with no real model calls — matching the discipline already used by `test-ralph-smoke`.
- **Unit-tested modules** (new, behind fakes): provider adapters (`available`/`active_env`/`models`/`efforts`/`display`/`argv`/`filter` + default-selection policy); the three agent shapes (capture/stream/raw, asserting fd routing + `PIPESTATUS` propagation); the run-status record (set/get by name, schema round-trip, identical key set across loops); role resolution (lens → role → consumer-wide → default); feedback detection (marker files → command list); loop adapters (launch + control contracts).
- **Integration coverage stays:** `test-ralph-smoke` (full `almanac ralph` chain) and `test-hub` continue to prove end-to-end behavior is unchanged — they are the behavior-preservation safety net for every step.
- **Prior art:** the existing `tests/test-*.sh` harness, especially `test-ralph-smoke.sh` (fake-provider end-to-end) and `test-loop-core.sh` (pure-function unit tests).

## Out of Scope

- **Behavior changes.** This refactor changes structure, not surface behavior. Any behavior change is a separate PRD.
- **New providers or loops** beyond today's `codex`/`claude` and `ralph`/`harden` — the seams *enable* them, but adding one is not part of this work.
- **The hub's visual/UX redesign** — the gum-vs-plain seam and look stay as they are.
- **A `loop-core.sh` compatibility barrel** — explicitly rejected; callers move to explicit dependencies.
- **Reworking the overseer, the convergence loop, or the run registry's storage format** — only their *location* changes, not their behavior.

## Further Notes

- **Behavior preservation is the acceptance bar.** Every step keeps all existing suites green; a step that can't is not done.
- **The two adapter seams are the durable win:** providers and loops become drop-in files, learned once. Everything else (agent shapes, record, home bootstrap, the split) supports that.
- **Dogfood option:** this PRD can be decomposed into vertical slices and built by the ralph loop on the very engine it refactors — a strong end-to-end exercise of the loop on itself.
- **Domain reference:** `CONTEXT.md` holds the canonical vocabulary (provider/loop adapter, deep invocation, launch/control contracts, the module map); keep it in sync as modules land.
