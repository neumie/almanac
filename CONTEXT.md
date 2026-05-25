# Almanac — Domain Model

Shared vocabulary for the loop engine. These nouns name the seams; use them exactly.

## Core nouns

- **Loop** — an autonomous agent run pattern that consumes the shared engine. Two today: **ralph** (works a PRD/issue queue task-by-task) and **harden** (review→ratify→fix convergence loop over a target). Adding a loop = adding an adapter, not editing the core.
- **Runner** — the per-loop script that actually executes iterations: ralph's `once.sh` (one) / `afk.sh` (autonomous N); harden's convergence loop.
- **Provider** — an agent backend the runner invokes: `codex` or `claude`. The facts about a provider (availability, default-selection signals, model list, effort list, display name, how to invoke it, how a sandbox maps to its permission flag, its event-stream filter) are a single concern.
- **Agent run** — one invocation of a provider on a prompt, producing a result + an event stream. The provider adapter supplies the argv + filter; the run owns only execution mechanics, expressed as three intention-revealing shapes (not one mode-parametric function): **`agent_capture`** (stdout → events file, silent), **`agent_stream`** (tee events + filtered live text to the terminal), **`agent_raw`** (native passthrough, no filter/events). Each takes only what its shape needs, so there are no invalid mode combinations to guard.
- **Run** — a launched loop, tracked in the **run registry** under `.almanac/runs/` (id, type, target, pid, status, round, summary). A run-status **record** module owns the canonical field list — the **run-status contract**, identical across loops, enforced *by construction*: callers `set`/`get` fields by name and never enumerate the schema.
- **Launcher** — the unified interactive config front-end (`almanac_loop_launch`): one loop-agnostic place that gathers a loop's config and execs its runner.
- **Hub** — bare `almanac`: the front door that lists/watches/stops/steers runs from the registry.
- **Overseer** — ralph's parallel process: pushes commits, waits on CI, reviews drift, emits steer directives.

## Provider adapters

A **provider adapter** is the concrete satisfier of the provider seam — one per backend, behind a common contract (a **real seam**: two adapters today, codex + claude). Each adapter answers the same fixed question set; nothing central branches on provider name.

The seam is **deep on invocation**: the adapter owns *what to run* (it yields the exec argv — including the sandbox→permission mapping — and its event-stream filter); the generic agent run owns *how to run it* (exec, capture, stream, thread the exit code). No `codex …`/`claude …` literals live outside an adapter.

Adapters are **auto-discovered** at `lib/providers/<name>.sh`; the provider list is simply the files present (drop one in, nothing central changes). Each implements the contract: `available`, `active_env`, `models`, `efforts`, `display`, `argv`, `filter`. The single central remainder is **default selection** policy: the active-env provider if available, else the first available in preference order (`claude` → `codex`).

## Loop adapters

Mirroring provider adapters: a **loop adapter** is the concrete satisfier of the loop seam, **auto-discovered** at `lib/loops/<name>.sh`. Each declares two contracts:
- **launch** — its config fields + how to exec its runner (consumed by the **launcher**)
- **control** — its stop/steer signal files, e.g. `.ralph-stop` / `.harden-steer` (consumed by the **hub**)

The **launcher** (create one run; standalone `almanac ralph …` *and* embedded in the hub's New-run) uses the launch contract; the **hub** (manage the fleet — list/watch/stop/steer) uses the control contract. **launcher ⊂ hub**: the launcher exists below the hub so the scripted/non-TTY path (`almanac ralph --prd x`) never opens a dashboard. Dispatch lives once in the adapter; each caller uses only the facet it needs.

## Home resolution

Every entry point resolves `ALMANAC_HOME` with one identical bootstrap: prefer an exported value, else self-resolve with `pwd -P` (symlink-safe) at the known depth. Not a deep module (bootstrap can't source a lib to find the lib) — a standardized snippet, so the inconsistency that broke `almanac ralph` (a copy missing `-P`) can't recur.

## Roles & lenses

- **Role** — a configurable slot that resolves to (provider, model, effort): ralph's `agent`; harden's `conductor` / `reviewer` / `fixer`. Resolution layers lens → role → consumer-wide → default.
- **Lens** — a harden reviewer perspective (correctness, security, perf, edge/tests, contracts). Reviewers fan out one per lens and may mix providers.

## Seams (gum-or-plain)

- **UI seam** — `almanac_loop_ui_*` (choose/input/confirm/render): gum when a controlling terminal is present, plain numbered fallback otherwise. Lives in `lib/ui.sh`.

## Module map (`lib/`)

The engine is split into cohesive modules — each file's interface is its test surface; `loop-core.sh` (the old 1619-line god-module) is **deleted**, not kept as a barrel. **Callers source only the modules they use** (explicit dependencies — no implicit "source the whole engine"). Skill entry points (`once.sh`/`afk.sh`/`prompt.sh`) bootstrap `ALMANAC_HOME`, then source their specific modules.

| file | owns |
|------|------|
| `lib/core.sh` | CLI helpers (`_die`/`_info`/…) + `ALMANAC_HOME` resolve |
| `lib/ui.sh` | gum-or-plain UI seam |
| `lib/role.sh` | role → (provider, model, effort) resolution |
| `lib/agent.sh` | `agent_capture`/`agent_stream`/`agent_raw` + provider dispatch |
| `lib/providers/<name>.sh` | provider adapters (auto-discovered) |
| `lib/loops/<name>.sh` | loop adapters (auto-discovered) |
| `lib/feedback.sh` | feedback detection + runner |
| `lib/run.sh` | run registry + run-status record + control (stop/steer/watch) + worker health + hub read-views |
| `lib/worker.sh` | worker orchestration (background fan-out) |
| `lib/loop-launcher.sh` | the launcher |
| `lib/harden-core.sh` | harden loop (declares its real deps) |
