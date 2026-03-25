# Almanac

Personal agent toolkit. Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) — they work across all compatible agents.

## Structure

- `skills/` — each skill is a directory with `SKILL.md` (YAML frontmatter + markdown body); reference material lives in `skills/*/references/`
- `providers/` — provider-specific adapters (Claude Code has hooks; others have setup stubs)
- `lib/` — shared shell utilities (`core.sh` for CLI, `almanac-core.sh` for skill validation)
- `tests/` — `test-structure.sh` checks files exist, `test-skills.sh` validates skill format
- `cmd/` — CLI commands: install, uninstall, list, update, sync, help

## Skill Format (Agent Skills Open Standard)

```yaml
---
name: lowercase-kebab-case        # Required, max 64 chars, must match directory name
description: Use when [condition]  # Required, max 1024 chars
metadata:                          # Optional
  upstream: anthropics/skills/x    # For adapted skills — tracks source
  upstream-sha: abc123...          # Git blob SHA at time of adaptation
  adapted-date: "2026-03-09"
compatibility: Requires X          # Optional, max 500 chars
---
# Markdown instructions (keep under 500 lines)
```

Optional directories: `scripts/`, `references/`, `assets/`

## Naming Convention

Skill names use `noun-verb` order (e.g. `pr-create`, `ci-fix`, `branch-summary`) so related skills group together alphabetically and are easier to search by topic.

## Adding a Skill

1. Create `skills/<name>/SKILL.md` with frontmatter
2. Name must be lowercase alphanumeric + hyphens, no `--`, no leading/trailing `-`, using `noun-verb` order
3. Description should start with "Use when..." for clear trigger conditions
4. Run `bash tests/test-skills.sh` to validate

## Adapted Skills

Four skills track upstream sources: `canvas` (contember/agent-canvas), `interview-me`, `tdd`, and `ubiquitous-language` (mattpocock/skills). Check for updates with `almanac sync`.

## Testing

```bash
bash tests/test-structure.sh   # All files and directories
bash tests/test-skills.sh      # Validates all skills + negative tests
```

## Keeping Documentation in Sync

Skill metadata is referenced in multiple places: `README.md` (skills table, structure diagram, sync example), `CLAUDE.md` (adapted skills count), `docs/ARCHITECTURE.md`, and `docs/CONTRIBUTING.md`. When adding, removing, or renaming skills, update all of these. `test-structure.sh` dynamically discovers skills so it stays current automatically.

## CLI

```bash
almanac install claude-code    # Add session hook to ~/.claude/settings.json
almanac sync                   # Check adapted skills for upstream changes
almanac list                   # Show providers and install status
```
