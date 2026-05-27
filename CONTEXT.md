# Almanac — Domain Model

Shared vocabulary for the loop engine. These nouns name the seams; use them exactly.

## Core nouns

- **Loop** — an autonomous agent run pattern that consumes the shared engine. Three today: **ralph** (works a PRD/issue queue task-by-task), **harden** (review→ratify→fix convergence loop over a target), and **converge** (overseer-judged convergence loop over a free-form goal). Adding a loop = adding an adapter, not editing the core.
- **Runner** — the per-loop script that actually executes iterations: ralph's `once.sh` (one) / `afk.sh` (autonomous N); harden's convergence loop.
- **Provider** — an agent backend the runner invokes: `codex` or `claude`. The facts about a provider (availability, default-selection signals, model list, effort list, display name, how to invoke it, how a sandbox maps to its permission flag, its event-stream filter) are a single concern.
- **Agent run** — one invocation of a provider on a prompt, producing a result + an event stream. The provider adapter supplies the argv + filter; the run owns only execution mechanics, expressed as three intention-revealing shapes (not one mode-parametric function): **`agent_capture`** (stdout → events file, silent), **`agent_stream`** (tee events + filtered live text to the terminal), **`agent_raw`** (native passthrough, no filter/events). Each takes only what its shape needs, so there are no invalid mode combinations to guard.
- **Run** — a launched loop, tracked in the **run registry** under `.almanac/runs/` (id, type, target, pid, status, round, summary). A run-status **record** module owns the canonical field list — the **run-status contract**, identical across loops, enforced *by construction*: callers `set`/`get` fields by name and never enumerate the schema. The same shape covers **worker-status** (per-reviewer/fixer record under `.almanac/runs/<id>/workers/<wid>/status.tsv`): one generic TSV record engine (`almanac_loop_tsv_record_set`) iterates a per-schema field list, so adding a worker field is a one-line addition to `almanac_loop_worker_record_fields` — no callsite churn, no 16-positional-arg writer to keep in sync.
- **Slug** — the file-safe handle a loop's artifacts are keyed on (run id suffix, plan dir, registry index column). Built by ONE function (`almanac_loop_slug`); both ralph and harden+converge use it directly with no per-loop wrapper. Latent bug it forecloses: registration and lookup using divergent fallbacks (e.g. `harden-target-…` written but `harden-run-…` searched).
- **Launcher** — the unified interactive config front-end (`almanac_loop_launch`): one loop-agnostic place that gathers a loop's config and execs its runner.
- **Hub** — bare `almanac`: the front door that lists/watches/stops/steers runs from the registry.
- **Overseer** — ralph's parallel process: pushes commits, waits on CI, reviews drift, emits steer directives.

## Provider adapters

A **provider adapter** is the concrete satisfier of the provider seam — one per backend, behind a common contract (a **real seam**: two adapters today, codex + claude). Each adapter answers the same fixed question set; nothing central branches on provider name.

The seam is **deep on invocation**: the adapter owns *what to run* (it yields the exec argv — including the sandbox→permission mapping — and its event-stream filter); the generic agent run owns *how to run it* (exec, capture, stream, thread the exit code). No `codex …`/`claude …` literals live outside an adapter.

Adapters are **auto-discovered** at `lib/providers/<name>.sh`; the provider list is simply the files present (drop one in, nothing central changes). Each implements the contract: `available`, `active_env`, `models`, `efforts`, `display`, `argv`, `filter`. The single central remainder is **default selection** policy: the active-env provider if available, else the first available in preference order (`claude` → `codex`).

## Loop adapters

Mirroring provider adapters: a **loop adapter** is the concrete satisfier of the loop seam, **auto-discovered** at `lib/loops/<name>.sh` (the loop list IS the files present). The discovery + name-normalising dispatch live in `lib/loops.sh` (`almanac_loop_adapter_call <name> <verb>` — the one place a loop type becomes a function call). Each adapter declares four contracts:
- **launch** — three verbs: `launch` (the full interactive config UI + env-export + exec; one entry point dispatched by the launcher), `launch_usage` (the `--help` text), and `exec_argv` (build the runner exec tokens into `_ALMANAC_LOOP_ARGV`, called by the adapter's own launch verb). Every per-loop bit that used to live in the launcher — flag parsing, prompts, summary lines, env keys, runner path — lives here, so adding a 4th loop is a single new file in `lib/loops/`. Latent bug it forecloses: the launcher growing a 4th `case "$type" in` branch and forgetting to update one of them (today the launcher has no branches on loop type at all).
- **new-run composition** — three verbs: `new_run_argv` (emit the hub's launcher argv, one token per line, from key=val pairs; returns 2 on a missing required field), `new_run_env` (emit `KEY=VALUE` env lines for fields that ride on environment — empty for ralph by construction), and `new_run_usage` (one-line missing-config hint for hub errors). Consumed by `almanac_loop_new_run_argv` / `_env` in `lib/run.sh` and `cmd/hub.sh`'s error rendering, all as thin dispatchers (no `case "$type"`). Latent bug it forecloses: the new-run composer or error message growing a 4th branch (env prefixes, flag shapes, missing-field hints) out of sync with the adapter — today there is no central branch to drift.
- **resume composition** — two verbs: `status_to_opts <status_file>` (invert the adapter's own status schema into the key=val pairs `new_run_argv` / `new_run_env` consume; ralph derives `prd` from target dirname and `mode=once|afk` from whether iterations was recorded) and `launch_backed` (optional; defined only by loops that go through the launcher, signalling that hub `--resume` may safely append `--yes` — direct-runner loops like harden/converge omit it and never get the suffix). Consumed by `cmd/hub.sh`'s `almanac_hub_resume_or_clone`, which is now fully loop-agnostic (no `case "$run_type"` enumerating per-loop status fields, no `[ "$run_type" != "harden" ]` enumerations). Latent bug it forecloses: the hub falling out of sync with a loop's status schema when a new field is added — today the hub never enumerates the schema.
- **control** — `signal_file <stop|steer>`: its between-round signal files, e.g. `.ralph-stop` / `.harden-steer` (consumed by the **hub**)

The **launcher** (create one run; standalone `almanac ralph …` *and* embedded in the hub's New-run) dispatches the launch verb through the adapter seam — no central code branches on loop type. It still owns the field collectors (`_almanac_launch_need_provider`/`_choice`/`_positive_int`) and the summary panel because every adapter uses them identically, but the per-loop UX lives in the adapter. The **hub** (manage the fleet — list/watch/stop/steer) uses the control contract. **launcher ⊂ hub**: the launcher exists below the hub so the scripted/non-TTY path (`almanac ralph --prd x`) never opens a dashboard. Dispatch lives once in the adapter; each caller uses only the facet it needs.

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
| `lib/loops.sh` | loop-adapter discovery + dispatch |
| `lib/loops/<name>.sh` | loop adapters (auto-discovered) |
| `lib/feedback.sh` | feedback detection + runner |
| `lib/run.sh` | run registry + run-status record + generic TSV record engine + control (stop/steer/watch) + worker health + hub read-views |
| `lib/worker.sh` | worker orchestration (background fan-out) + worker-status record schema (uses run.sh's engine) |
| `lib/loop-launcher.sh` | the launcher |
| `lib/harden-core.sh` | harden loop (declares its real deps) |
| `lib/converge-core.sh` | converge loop (declares its real deps) |
