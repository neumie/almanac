# Almanac

Personal agent toolkit. Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) — they work across all compatible agents.

## Naming

Always name skills `noun-verb` (`pr-create`, `ci-fix`, `session-recap`). Never `verb-noun` — breaks alphabetical grouping by topic. Lowercase alphanumeric + hyphens only, no `--`, no leading/trailing `-`. Name must match the directory name exactly.

## Skill Format

Description must start with `Use when` and state the trigger condition explicitly — agents under-trigger otherwise. Keep the body under 500 lines; move detail to `references/`. Full frontmatter schema: `docs/CONTRIBUTING.md`.

## Skill Deduplication

Orchestrator skills (`ship`, `task-start`) **must** reference standalone skills, never inline their logic. One source of truth per capability:

- **Branch naming** → `branch-name`
- **Committing** → `commit`
- **Pushing** → `push`
- **PR creation** → `pr-create`
- **Complexity scoring** → `complexity-assess`

When adding a new orchestrator or composite skill, delegate with "Follow the `<skill-name>` skill" — never duplicate. Declare hard dependencies in `metadata.dependencies`; validation fails if a listed dependency doesn't exist.

## Decision Framework: New Skill vs Extend

Before creating a new skill: (1) check if an existing skill already covers the trigger, (2) if it overlaps an orchestrator (`ship`, `task-start`), extend the orchestrator instead of adding a sibling.

## Validation as Deep Module

Always extend `almanac_validate_skill()` in `lib/almanac-core.sh` for new skill-format rules. Never inline ad-hoc checks in `tests/test-skills.sh` — leads to scattered validation. Always run `bash tests/test-skills.sh` after editing any skill; if it fails, fix the skill — never skip the test, weaken the validator, or commit with failures.

## Symlink Architecture

`providers/claude-code/skills` is a symlink to `../../skills`. Editing files under `providers/claude-code/skills/` edits the canonical files in `skills/`. Always edit at the canonical `skills/` path — never through the symlink.

## Global Config Scope

`providers/claude-code/CLAUDE.md` (caveman mode) gets symlinked to `~/.claude/CLAUDE.md` when users run `almanac install claude-code --global-config`. Edits there affect every Claude Code session globally — not just this repo. Never put project-specific rules there; project-only guidance belongs in this file.

## Doc Sync

When adding/removing/renaming a skill, you **must** update in the same commit:

- `README.md` — skills table, structure diagram, sync example
- `docs/ARCHITECTURE.md`
- `docs/CONTRIBUTING.md`

`test-structure.sh` only catches missing skill files — it does not catch stale prose. Adapted skills track upstream sources via `metadata.upstream-sha`; `almanac sync` checks for updates.

## Self-Maintenance

Discovered an undocumented gotcha or non-obvious pattern while working in this repo? Add it here in the same commit.
