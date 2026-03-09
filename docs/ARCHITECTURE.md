# Architecture

Almanac uses a two-layer architecture: a provider-agnostic core and provider-specific adapters.

## Layer 1: Core (provider-agnostic)

### `skills/`
The only true open standard. Each skill is a directory containing a `SKILL.md` file with YAML frontmatter (`name` + `description`) and markdown instructions. Skills are natively discovered by Claude Code, OpenCode, Cursor, and Codex.

### `prompts/`
Reusable prompt templates. Plain markdown. Not auto-discovered — used manually or referenced by skills.

### `patterns/`
Reference documentation, architectural patterns, and agent interaction guidelines. Plain markdown.

## Layer 2: Adapters (provider-specific)

Each provider gets its own directory under `providers/` with the wiring needed to connect the core to that tool's plugin/discovery system.

### `providers/claude-code/`
Full plugin adapter: `plugin.json` manifest that points `skills` to `../../skills/` (the shared core), plus provider-local agents, commands, and hooks.

### `providers/{opencode,cursor,codex}/`
Setup stubs with instructions for symlinking skills into each provider's discovery path.

## Key Principle

Skills are shared. Everything else is provider-local. This means adding a new skill automatically makes it available across all providers, while provider-specific features (agents, commands, hooks) stay isolated.
