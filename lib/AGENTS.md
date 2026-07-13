# lib/ — Loop engine

The domain model lives in **`../CONTEXT.md`** (does not auto-load) — it names every seam (provider/loop adapter, run-status contract, slug, plan container, launcher, hub, module map). Read it first. Helper placement, validation, the test split: root `CLAUDE.md`. This file lists **only** the rules an agent breaks even after reading both — each is a silent failure, not a loud one.

## Adapters: file in, never a `case`

Provider = `lib/providers/<name>.sh`, loop = `lib/loops/<name>.sh` — glob-discovered, no registry (CONTEXT.md). The rule agents break: a `case`/`if` branching on provider or loop name **anywhere outside an adapter**. The one sanctioned name literal is the `for p in claude codex` preference list in `almanac_provider_default` (`agent.sh:108`) — a new provider is discoverable and dispatchable but won't enter phase-2 default selection until edited there. Nothing tests any of this.

**Function name IS the contract:** `almanac_{provider,loop}_<key>_<verb>`, `<key>` = lowercased filename (providers after the `claude-code → claude` alias in `almanac_provider_key`, `agent.sh:26-33`). Dispatchers (`almanac_provider_call` `agent.sh:74`; `almanac_loop_adapter_call` `loops.sh:67`) build the name and probe with `declare -F`; a misnamed or missing verb silently returns **rc=2**, never errors.

**argv returns by side effect, not echo/return:** provider `argv` assigns the global `_ALMANAC_AGENT_ARGV`; loop `exec_argv` assigns `_ALMANAC_LOOP_ARGV`. An adapter that echoes or returns the argv appears to do nothing.

**Optional hooks are presence-detected via `declare -F`** (`extract`, `supports_raw`, `launch_backed`, `signal_dir`) — define one only when you diverge from the default. Defining a hook you don't need silently changes behavior (e.g. `launch_backed` on a direct-runner loop makes hub `--resume` append `--yes`). CONTEXT.md says which loop defines which.

**`launch` is the one verb that bypasses `almanac_loop_adapter_call`** — `almanac_loop_launch` (`loop-launcher.sh:190`) calls the fn directly because launch legitimately exits non-zero (user cancel), which would collide with adapter_call's rc=2. Still no `case` on type.

**Implement all three `new_run_*` verbs even when one is a no-op** (loop's `new_run_env` is `return 0`) so the `run.sh` dispatcher never branches; `status_to_opts` must round-trip through `new_run_argv`/`_env` or resume desyncs. (Helper roster: read the `run.sh`/`loops.sh` headers, not this file.)

## Sourcing: by symbol, no god-barrel

`loop-core.sh` is **deleted** — never source it. Callers source only the modules they use. New entry points copy the existing `ALMANAC_HOME` bootstrap **verbatim** — prefer the exported value, else `pwd -P` (symlink-safe) at the known depth; dropping `-P` breaks symlinked installs (the bug that broke `almanac loop`). Then source `core.sh` first (it defines `_almanac_source_sibling`), and pull each other module via `_almanac_source_sibling <file.sh> <a-symbol-it-defines>` (pattern at `worker.sh:22-23`) so a load-order or rename break surfaces. **`run.sh` stays `core.sh`-free** so it's standalone-testable (`tests/test-run.sh` sources it directly) — don't add a transitive `core.sh` dep through a new sibling. `worker.sh` does source `core.sh`.

## Run-status record

**Persist a new field by adding it to `almanac_loop_record_fields` (`run.sh:42-48`) first** — the single source of truth, in write order. Worker fields go in `almanac_loop_worker_record_fields` (`worker.sh:29-34`). The TSV engine (`almanac_loop_tsv_record_set`, `run.sh:142`) returns 2 for any non-canonical field; `record_set`/`set_run_config` propagate it, and the converge-core callsite swallows it with `... || true` (`converge-core.sh:1268-1270`) — so naming a field only at a callsite is a silent no-op.

**Never write a record positionally.** All writes go through `almanac_loop_record_set` / `almanac_loop_worker_record_set` as `field=val` pairs (the engine iterates the schema). Reintroducing a positional/N-arg writer re-creates the desync the generic engine deleted.

**`index.tsv` = the first 7 columns of the schema** (`almanac_loop_index_columns`, `run.sh:57-59`: `id type target pid status_file started_at status`). Four readers hard-bind those 7 by position (`run.sh:613,839,871,942`) — change `almanac_loop_index_columns` and you must fix all four. Append new run fields **after** the `index_columns` call, never interleave.

**One slug fn, one id composer — register and look up through the same path.** Run ids come from `almanac_loop_run_id` (`run.sh:238`), which slugs via `almanac_loop_slug`; `almanac_loop_register_run` (`run.sh:310`) and every resolve/lookup caller must derive the id the same way. A per-loop id/slug wrapper or a lookup with its own fallback produces divergent register-vs-search keys — runs the hub can list-but-never-find (or never list). `almanac_loop_plan_dir` (`run.sh:226`) does **not** slug; it's a pure joiner — pre-slug the key as `run_id` does.

Known stale comment: the converge-core `plan_dir=...` status write (`converge-core.sh:1268`) is dead because `plan_dir` isn't canonical; real recovery is a filesystem scan (`almanac_converge_resolve_plan_dir_name`, `converge-core.sh:142`). Adding `plan_dir` to `record_fields` would fix it.
