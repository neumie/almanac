# Architecture

Two-layer design: provider-agnostic core + provider-specific adapters.

## Layer 1: Core (provider-agnostic)

### `skills/`
The open standard. Each skill is a directory with a `SKILL.md` file following the [Agent Skills Open Standard](https://agentskills.io/specification). Skills are natively discovered by Claude Code, OpenCode, Cursor, Codex, and 25+ compatible agents.

Skills use progressive disclosure:
1. **Metadata** (~100 tokens) — name + description, loaded at startup
2. **Instructions** (<5000 tokens) — SKILL.md body, loaded on activation
3. **Resources** (on demand) — scripts/, references/, assets/

Some skills are adapted from [anthropics/skills](https://github.com/anthropics/skills) and track their upstream via `metadata.upstream-sha` in frontmatter. Run `almanac sync` to check for updates.

### `prompts/`
Reusable prompt templates. Plain markdown. Not auto-discovered — referenced manually or by skills. Contains role definitions, checklists, and task templates.

### `patterns/`
Reference documentation and architectural patterns. Plain markdown. Contains agent workflow patterns, debugging methodology, safety guardrails.

## Layer 2: Adapters (provider-specific)

### `providers/claude-code/`
Full local plugin:
- `.claude-plugin/plugin.json` — plugin manifest
- `skills/` — symlink to shared `../../skills`
- `hooks/hooks.json` — lifecycle hooks (SessionStart, Stop)
- `agents/`, `commands/` — extensible directories

### `providers/{opencode,cursor,codex}/`
Setup stubs with symlink instructions for each provider's skill discovery path.

## CLI (`bin/almanac`)

Dispatcher pattern: `bin/almanac` resolves `ALMANAC_HOME`, sources `lib/core.sh`, routes to `cmd/<command>.sh`. Commands: install, uninstall, list, update, sync, help.

## Validation (`lib/almanac-core.sh`)

`almanac_validate_skill()` checks against the Agent Skills Open Standard:
- Name format (regex, length, no consecutive hyphens, matches directory)
- Description presence and length
- Frontmatter size
- Optional field constraints (compatibility length)
- Line count recommendation

## Key Principle

Skills are shared across all providers. Everything else (hooks, commands, agents) is provider-local. Adding a skill makes it available everywhere. Provider-specific features stay isolated.
