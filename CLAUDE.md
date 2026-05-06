# Almanac

## Skill Authoring

**Naming.** `noun-verb` (`pr-create`, `ci-fix`, `session-recap`). Never `verb-noun` — breaks alphabetical grouping by topic. Lowercase alphanumeric + hyphens, no `--`, no leading/trailing `-`. Name must match directory exactly.

**Categories.** Skills live nested at `skills/<category>/<name>/SKILL.md`. Current categories: `git/` (git/`gh` ops), `agents-md/` (CLAUDE.md/AGENTS.md tooling), `loop/` (PRD → issues → autonomous ralph-loop), `comms/` (client/team-facing comms — emails, release notes, etc.), `other/`. Add new categories freely — validator just walks the tree. Names must be unique across the whole tree (validator hard-fails on collisions). The category is purely organizational; install-time symlinks flatten everything to `~/.claude/skills/almanac/<name>` because Claude Code skill discovery is flat (only direct children of the skills dir are scanned).

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

**CLI helpers.** `cmd/*.sh` scripts must source `lib/core.sh` and use `_die`/`_info`/`_success`/`_warn`/`_error` — never `echo` errors directly or roll new helpers. Existing offenders to NOT pattern-match from: `cmd/list.sh` and `cmd/sync.sh` both predate this rule and still use raw `echo`.

**Where helpers go.** Skill-format helpers (frontmatter parsing, `almanac_validate_skill`, anything `tests/test-skills.sh` calls) in `lib/almanac-core.sh`; CLI/output helpers (`_die`/`_info`/colors, anything `cmd/*.sh` or `install.sh` calls) in `lib/core.sh`. If unclear, ask whether non-skill code (CLI, install, sync) needs it — yes → `core.sh`; no → `almanac-core.sh`. Don't cross-contaminate.

## Symlink Map

- **In-repo:** `providers/claude-code/skills` → `../../skills`. The plugin distribution path is no longer maintained (skills are now nested at `skills/<category>/<name>` and Claude Code's plugin loader expects flat). The symlink stays for backward-compat but the install CLI is the supported install path.
- **Install-time, per skill (slash command):** `~/.claude/commands/almanac/<name>.md` → each skill's `SKILL.md`. Single-file symlink — never resolve `scripts/` or `references/` from this path.
- **Install-time, per skill (resources):** `~/.claude/skills/almanac/<name>` → `$ALMANAC_HOME/skills/<category>/<name>` (directory symlink). One per skill, flattening the categorized layout. Always resolve runnable assets from here: `~/.claude/skills/almanac/<name>/scripts/...`.
- **Install-time, global config:** `providers/claude-code/CLAUDE.md` → `~/.claude/CLAUDE.md` when user passes `--global-config`. Edits affect every Claude Code session globally — keep project-only rules in this file, not there.

Changes to install symlink layout go in `cmd/install.sh` — don't fork the logic into another script. Helpers `almanac_list_skills`, `almanac_find_skill`, `almanac_validate_unique_names` (in `lib/almanac-core.sh`) are the only sanctioned ways to walk the skills tree — never `for d in skills/*/`.

## Skill Resources (scripts/, references/)

**Always print absolute paths under `~/.claude/skills/almanac/<name>/scripts/...` in user-facing instructions. Never use `${CLAUDE_SKILL_DIR}/scripts/...`** — the commands path is a single-file symlink and won't resolve subdirs. Only the per-skill directory symlinks at `~/.claude/skills/almanac/<name>` resolve.

Existing offenders to NOT pattern-match from: `codebase-improve`, `diagnose`, `tdd`, `task-start`, `grill-me`, `agents-md-audit`, `ralph-loop` — all still reference `${CLAUDE_SKILL_DIR}/...`.

## Doc Sync

When adding/removing/renaming a skill, you **must** update in the same commit:

- `README.md` — skills table, structure diagram, sync example
- `docs/ARCHITECTURE.md`
- `docs/CONTRIBUTING.md`

`test-structure.sh` only catches missing skill files — not stale prose. Adapted skills track upstream sources via `metadata.upstream-sha`; `almanac sync` checks for updates.

## Self-Maintenance

Existing code may predate a rule. Check this file first; don't pattern-match from `${CLAUDE_SKILL_DIR}` paths or direct `echo` in `cmd/*.sh` — both violate rules above. Discovered an undocumented gotcha? Add it here in the same commit.
