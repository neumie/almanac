# Architecture

Two-layer design: provider-agnostic core + provider-specific adapters.

## Layer 1: Core (provider-agnostic)

### `skills/`
The open standard. Each skill is a directory with a `SKILL.md` file following the [Agent Skills Open Standard](https://agentskills.io/specification). Skills are natively discovered by Claude Code, OpenCode, Cursor, Codex, and 25+ compatible agents.

Skills are organized by category — `git/`, `agents-md/`, `loop/`, `comms/`, `other/` — for filesystem hygiene. The category is purely organizational; install-time symlinks flatten everything to `~/.claude/skills/almanac/<name>` because Claude Code's skill discovery only scans direct children of the skills root. Names must be unique across the whole tree (validator enforces).

Skills use progressive disclosure:
1. **Metadata** (~100 tokens) — name + description, loaded at startup
2. **Instructions** (<5000 tokens) — SKILL.md body, loaded on activation
3. **Resources** (on demand) — scripts/, references/, assets/

Some skills are adapted from upstream sources ([mattpocock/skills](https://github.com/mattpocock/skills), [contember/agent-canvas](https://github.com/contember/agent-canvas)) and track their upstream via `metadata.upstream-sha` in frontmatter. Run `almanac sync` to check for updates.

Reference material (templates, patterns, guardrails) lives in `skills/*/references/` directories, loaded on demand by the skills that use them.

## Layer 2: Adapters (provider-specific)

### `providers/claude-code/`
Full local plugin:
- `.claude-plugin/plugin.json` — plugin manifest
- `skills/` — symlink to shared `../../skills`
- `hooks/hooks.json` — lifecycle hooks (SessionStart, Stop)
- `agents/` — extensible directory

### `providers/{opencode,cursor,codex}/`
Setup stubs with symlink instructions for each provider's skill discovery path. Codex also has a first-class installer that links skill directories into `~/.agents/skills/almanac/<name>` for `$skill` invocation and `/skills` browsing.

## CLI (`bin/almanac`)

Dispatcher pattern: `bin/almanac` resolves `ALMANAC_HOME`, sources `lib/core.sh`, routes to `cmd/<command>.sh`. Commands: install, uninstall, list, update, sync, ralph, harden, help.

`cmd/harden.sh` is the first harden-loop CLI surface. It uses `lib/harden-core.sh` to draft a target-specific `rubric.md` under `docs/plans/harden/<target-slug>/` in the caller repo, refusing to overwrite an existing contract. Drafts start with `Status: draft`; after the developer edits the contract, `almanac harden <target> --approve` marks it `Status: approved` and appends an approval timestamp. The rubric is the **bar**: `almanac_harden_rubric_acceptance` reads the `## Acceptance` criteria back, and `almanac_harden_reviewer_prompt` embeds them so reviewers judge against the contract rather than an implicit standard. The bar grows only by ratified defects — `almanac_harden_rubric_append_criterion` appends a new `- [ ]` criterion under `## Acceptance` append-only (monotonic, visible as a diff) and idempotent (an identical criterion is never re-added). Run with no flags, `almanac harden <target>` fans out one read-only reviewer per configured lens (`almanac_harden_fanout`), passing each reviewer the rubric path so the contract is consumed when present. The lens set comes from `almanac_harden_lenses` — the five PRD lenses (`correctness security perf edge-cases contracts`) by default, overridable at runtime via `HARDEN_LENSES` (comma- or whitespace-separated, no enforced cap). Each lens spawns a background worker through the shared worker orchestration with a `read-only` sandbox, resolving its provider/model/effort via the shared role config (`HARDEN_REVIEWER[_<LENS>]_{PROVIDER,MODEL,EFFORT}`) so lenses can mix providers. Reviewers run concurrently and never write to the target; once all finish, the parent aggregates each reviewer's findings into the ledger **sequentially** (so there are no concurrent ledger writers), deduped via `almanac_harden_ledger_record`, and prints each lens's findings (jq parse with an awk fallback). Worker pids are captured via a file rather than command substitution so the backgrounded workers stay children of the launching shell and remain waitable; a failed reviewer is reported and skipped without sinking the round. A missing target fails via `_die` before anything spawns.

The **findings ledger** persists adjudicated findings append-only to `findings.md` beside the rubric. The canonical finding schema is `lens, severity, location, claim, demonstration`; the ledger adds `id`, `status` (`open` | `fixed` | `rejected-subjective` | `wontfix-per-context`), `round`, and an `adjudication` note. `almanac_harden_parse_findings` normalizes a reviewer's JSON-Lines result into ledger-entry rows (new findings are `open`), dropping malformed lines cleanly. `id` is a `cksum` fingerprint of `(lens, location, claim)` — demonstration is excluded so a reworded repro is not a new finding — and `almanac_harden_ledger_record` dedupes against it, so a finding already adjudicated in a prior round is never re-added. `almanac_harden_ledger_open_blocking` reads the ledger back and returns only `status: open` findings, since fixed and rejected findings never gate the loop.

The **ratification engine** decides blocking vs. note by *executing* a finding's demonstration, never by trusting a reviewer's assertion. `almanac_harden_ratify` runs the demonstration through a seam (`almanac_harden_demo_reproduces`, default conservative non-reproducing; overridden by a conductor agent-runner call in the convergence-loop slice and by tests) and records the outcome in the ledger, printing one verdict: a new/open finding that reproduces → `blocking` (`status: open`); one that does not → `note` (`status: rejected-subjective`); an already-adjudicated finding (`fixed` / `rejected-subjective` / `wontfix-per-context`) that *newly* reproduces → `reopened` (back to `status: open`); one that still does not reproduce → `dropped` (left untouched, never re-litigated). Status transitions go through `almanac_harden_ledger_set_status` (rewrites status + adjudication in place); `almanac_harden_ledger_status` reads a finding's current status so new findings are told from already-adjudicated ones. When `almanac_harden_ratify` is given a rubric path, a finding that reproduces (`blocking` or `reopened`) also appends a falsifiable criterion to the rubric's `## Acceptance` via `almanac_harden_rubric_append_criterion`, so the bar grows monotonically with every ratified defect; notes and drops never touch the rubric, so opinions cannot raise it.

## Shared Loop Engine (`lib/loop-core.sh`)

`lib/loop-core.sh` owns loop behavior shared by Ralph and harden-loop. Feedback detection maps project marker files to commands and renders prompt-ready markdown. Role config resolution layers lens-specific, role-specific, consumer-wide, then default provider/model/effort values, so harden reviewer lenses can mix providers while Ralph keeps its `RALPH_PROVIDER` / `RALPH_MODEL` / `RALPH_EFFORT` style. The shared agent runner invokes Codex or Claude through one public function that accepts provider/model/effort/sandbox, a prompt file, a result file, and an optional events-log path: it streams raw provider events to that JSONL log (allocating one when the path is omitted), echoes the log path back so callers can locate the stream, writes the provider's final result to the result file, and propagates a non-zero provider exit as a failure rather than swallowing it. Worker orchestration starts provider runs in the background through that runner and records per-worker `status.tsv`, `events.jsonl`, `result.txt`, and `stderr.log` files under the run directory. The run registry records launched loops under `.almanac/runs/` in the caller repo: `index.tsv` stores id/type/target/pid/status-file/start/status, and each run gets a `status.tsv` blob that can be marked `done` or `failed` when the process exits. `ralph-loop` launchers source `ralph-run-registry.sh`; `once.sh` and `afk.sh` register the PRD run before starting providers and mark it at process exit. `.almanac/` is ignored because registry state is runtime-only.

## Validation (`lib/almanac-core.sh`)

`almanac_validate_skill()` checks against the Agent Skills Open Standard:
- Name format (regex, length, no consecutive hyphens, matches directory)
- Description presence + length (≤220 chars to keep auto-listing compact)
- Frontmatter size
- Optional field constraints (compatibility length)
- Line count recommendation
- `metadata.dependencies` resolved by name across the whole tree (categories are transparent to deps)

`almanac_validate_unique_names()` runs once per test pass — fails if two skills under different categories share a name.

`almanac_list_skills()` and `almanac_find_skill()` are the canonical tree walkers — every CLI/test that enumerates skills uses them. Layout assumption: `skills/<category>/<name>/SKILL.md` (depth 3 from `$ALMANAC_HOME`).

## Key Principle

Skills are shared across all providers. Everything else (hooks, commands, agents) is provider-local. Adding a skill makes it available everywhere. Provider-specific features stay isolated.
