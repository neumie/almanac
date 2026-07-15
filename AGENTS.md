# Almanac

## Skill Authoring

**Naming.** `noun-verb` (`pr-create`, `ci-fix`, `session-recap`). Never `verb-noun` — breaks alphabetical grouping by topic. Lowercase alphanumeric + hyphens, no `--`, no leading/trailing `-`. Name must match directory exactly.

**Categories.** Skills live nested at `skills/<category>/<name>/SKILL.md`. Current categories: `git/` (git/`gh` ops), `agents-md/` (CLAUDE.md/AGENTS.md tooling), `loop/` (PRD → issues → autonomous loop), `comms/` (client/team-facing comms — emails, release notes, etc.), `other/`. Add new categories freely — validator just walks the tree. Names must be unique across the whole tree (validator hard-fails on collisions). The category is purely organizational; install-time symlinks flatten everything to `~/.claude/skills/almanac/<name>` because Claude Code skill discovery is flat (only direct children of the skills dir are scanned).

**Format.** Description must start with `Use when` and state the trigger explicitly — agents under-trigger otherwise. Body under 500 lines; move detail to `references/`. Full frontmatter schema: `docs/CONTRIBUTING.md`.

**Description length.** Hard cap **220 chars** (validator enforces). State the trigger once — do **not** restate it as `Use this whenever the user says X, Y, Z, or wants to A`. Mechanism details (subagent counts, internal modes, scoring rubrics) belong in the SKILL.md body, not frontmatter. The aggregated skills listing is loaded into every Claude session — bloated descriptions burn tokens and risk getting truncated/dropped.

**Manual-only skills.** Set `disable-model-invocation: true` in frontmatter to strip a skill from the auto-listing entirely (saves ~200 chars/skill in the listing). The skill stays user-invocable via `/almanac:<name>` and orchestrators can still load it by path. Use sparingly — only for skills with no plausible natural-language trigger at all. Default is auto-invocable: any skill whose trigger phrase a user might say (`branch-name`, `ci-fix`, `commit`, `push`, `pr-create`, `commits-squash`, `complexity-assess`, `diagnose`, etc.) must auto-fire.

## Decision Framework: New Skill vs Extend

Before creating a new skill: (1) check if an existing skill covers the trigger, (2) if it overlaps an orchestrator (`ship`, `task-start`), extend the orchestrator instead of adding a sibling.

## Skill Deduplication

Orchestrators (`ship`, `task-start`) **must** reference standalone skills, never inline their logic. One source of truth per capability:

- **Branch naming** → `branch-name`
- **Committing** → `commit`
- **Pushing** → `push`
- **PR creation** → `pr-create`
- **Complexity scoring** → `complexity-assess`
- **Rebasing** → `rebase`

Delegate with "Follow the `<skill-name>` skill" — never duplicate. Declare hard deps in `metadata.dependencies`; validation fails if a listed dep doesn't exist.

## Code Organization

**Validation.** Always extend `almanac_validate_skill()` in `lib/almanac-core.sh` for new skill-format rules. Never inline ad-hoc checks in `tests/test-skills.sh` — leads to scattered validation. Always run `bash tests/test-skills.sh` after editing any skill; if it fails, fix the skill — never skip the test, weaken the validator, or commit with failures.

**Test split.** `tests/test-structure.sh` validates layout (skill dirs, required files, CLI scripts present); `tests/test-skills.sh` validates skill *contents* via `almanac_validate_skill()`. Extend the right one — layout rules go in structure, content/format rules go in skills.

**CLI helpers.** `cmd/*.sh` scripts must source `lib/core.sh` and use `_die`/`_info`/`_success`/`_warn`/`_error`/`_heading` — never `echo`/`echo -e` for output or roll new helpers. Full command contract: **CLI Commands** below.

**Portability: target bash 3.2.** macOS ships bash 3.2.57 as both `/bin/bash` and (usually) `/usr/bin/env bash`, so all shell here must run on it — no bash 4+ features (associative arrays, `${var,,}`, `mapfile`/`readarray`, `&>>`). Notably, a single `local a="$1" b="…$a…"` evaluates **every** RHS before binding, so `$a` resolves to the *caller's* `a`, not `$1` — split dependent `local` assignments onto separate lines (see `almanac_command_meta`, `lib/core.sh`).

**Where helpers go.** Skill-format helpers (frontmatter parsing, `almanac_validate_skill`, anything `tests/test-skills.sh` calls) in `lib/almanac-core.sh`; CLI/output helpers (`_die`/`_info`/`_heading`/colors, the arg-guard `_need_value`, the command registry `almanac_list_commands`/`almanac_command_meta`, anything `cmd/*.sh` or `install.sh` calls) in `lib/core.sh`. If unclear, ask whether non-skill code (CLI, install, sync) needs it — yes → `core.sh`; no → `almanac-core.sh`. Don't cross-contaminate.

## CLI Commands

The `almanac` CLI is **registry-driven**: a command is valid iff `cmd/<name>.sh` exists. `almanac_list_commands` (in `lib/core.sh`, globbing `cmd/*.sh` — mirrors `almanac_providers`) is the single source of truth for the command set; `bin/almanac` dispatch, `cmd/help.sh`, and `tests/test-cli.sh` all derive from it. **Adding a command is one new file in `cmd/` — never edit the dispatcher or hand-maintain a command list anywhere.** The dispatcher guards the name to `^[a-z][a-z-]*$` before touching the filesystem (path-traversal safe).

**Command file contract** (enforced by `tests/test-cli.sh` — it fails the build if a command skips any of this):
- Declares three header comment lines, read by help generation via `almanac_command_meta`: `# summary:` (one line for `almanac help`), `# usage:` (synopsis), `# group:` (`loops` | `providers` | `maintenance` | `other`).
- Sets `set -euo pipefail` and sources at least one `lib/` file (`core.sh` for the `_` helpers, or a `*-core.sh` that loads it).
- Handles `-h|--help` → prints usage to **stdout**, `exit 0`.
- Is **sourced** into `bin/almanac` (not exec'd): finish with `exit` (not `return`), and assume `$ALMANAC_HOME` is exported — `bin/almanac` owns the `ALMANAC_HOME` bootstrap, so don't re-add the snippet to a cmd file.

**`almanac help` is generated** — it walks `almanac_list_commands` and prints each command's `# summary:` under its `# group:` section. Never hand-edit a command list into it.

**Arg parsing.** Guard a required `--flag VALUE` option with `_need_value <flag> "$#"` (call it the moment the flag matches, before shifting). Parse errors are **terse** `_die` one-liners to stderr — no usage dump (that's what `--help` is for); the missing-required-arg case may add a `see 'almanac <cmd> --help'` pointer. Use `_heading` for section titles, never `echo -e "${_BOLD}…"`. `cmd/hub.sh` keeps its own per-flag messages (more specific than `_need_value`'s generic text) — acceptable, still terse. Heavy command logic lives in a `lib/<cmd>-core.sh` (see `hub-core.sh`); the `cmd/` file stays a parse+dispatch shim so the logic is unit-testable.

## Symlink Map

- **In-repo:** `providers/claude-code/skills` → `../../skills`. The plugin distribution path is no longer maintained (skills are now nested at `skills/<category>/<name>` and Claude Code's plugin loader expects flat). The symlink stays for backward-compat but the install CLI is the supported install path.
- **In-repo, agent instructions:** `AGENTS.md` is the canonical real file; `CLAUDE.md` is a symlink to it (`ln -s AGENTS.md CLAUDE.md`) — the convention the `agents-md-map` skill enforces. Adopted at the repo root and `lib/` (whose `AGENTS.md` points agents at the non-auto-loading `CONTEXT.md` domain model + loop-engine seam rules). Exception: `providers/_shared/AGENTS.md` is the distributable global-config payload above, not navigation guidance — it stays solo, never gets a `CLAUDE.md` sibling.
- **Install-time, per skill (slash command):** `~/.claude/commands/almanac/<name>.md` → each skill's `SKILL.md`. Single-file symlink — never resolve `scripts/` or `references/` from this path.
- **Install-time, per skill (resources):** `~/.claude/skills/almanac/<name>` → `$ALMANAC_HOME/skills/<category>/<name>` (directory symlink). One per skill, flattening the categorized layout. Always resolve runnable assets from here: `~/.claude/skills/almanac/<name>/scripts/...`.
- **Install-time, global config:** `providers/_shared/AGENTS.md` → `~/.claude/CLAUDE.md` (claude-code) and `~/.codex/AGENTS.md` (codex) — one canonical source shared across providers (wired in `cmd/install.sh`; the `session-start` hook keeps it fresh). Replaced only with `--global-config`. Edits affect every session globally — keep project-only rules in this repo's root `AGENTS.md`, not there. NOTE: `providers/_shared/AGENTS.md` is a distributable payload (the user's global config), **not** navigation guidance — it must never get a `CLAUDE.md` sibling.

Changes to install symlink layout go in `cmd/install.sh` — don't fork the logic into another script. Helpers `almanac_list_skills`, `almanac_find_skill`, `almanac_validate_unique_names` (in `lib/almanac-core.sh`) are the only sanctioned ways to walk the skills tree — never `for d in skills/*/`.

## Skill Resources (scripts/, references/)

**Always print absolute paths under `~/.claude/skills/almanac/<name>/scripts/...` in user-facing instructions. Never use `${CLAUDE_SKILL_DIR}/scripts/...`** — the commands path is a single-file symlink and won't resolve subdirs. Only the per-skill directory symlinks at `~/.claude/skills/almanac/<name>` resolve. No skill references `${CLAUDE_SKILL_DIR}` anymore — keep it that way.

## Doc Sync

When adding/removing/renaming a skill, you **must** update in the same commit:

- `README.md` — skills table, structure diagram, sync example
- `docs/ARCHITECTURE.md`
- `docs/CONTRIBUTING.md`

`test-structure.sh` only catches missing skill files — not stale prose. Adapted skills track upstream sources via `metadata.upstream-sha`; `almanac sync` checks for updates.

## Self-Maintenance

Existing code may predate a rule. Check this file first; don't pattern-match from `${CLAUDE_SKILL_DIR}` paths or direct `echo` in `cmd/*.sh` — both violate rules above. Discovered an undocumented gotcha? Add it here in the same commit.
