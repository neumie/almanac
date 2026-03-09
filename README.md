# Almanac

Provider-agnostic agent toolkit — skills, prompts, and patterns for LLM coding agents.

## Quick Start

### Claude Code
```bash
# Install as a plugin
claude plugin add /path/to/almanac/providers/claude-code
```

### OpenCode
```bash
ln -s /path/to/almanac/skills ~/.config/opencode/skills/almanac
```

### Cursor
```bash
ln -s /path/to/almanac/skills ~/.cursor/skills/almanac
```

### Codex
```bash
ln -s /path/to/almanac/skills ~/.agents/skills/almanac
```

## Structure

```
almanac/
├── skills/          # Open standard — works on all providers
├── prompts/         # Prompt templates (plain markdown)
├── patterns/        # Agent patterns & reference docs
├── providers/       # Provider-specific adapters
│   ├── claude-code/ # Full plugin (agents, commands, hooks)
│   ├── opencode/    # Setup instructions
│   ├── cursor/      # Setup instructions
│   └── codex/       # Setup instructions
├── lib/             # Shared utilities
├── tests/           # Validation scripts
└── docs/            # Architecture & contributing guides
```

## Key Insight

Skills (`SKILL.md` with YAML frontmatter) are the only true open standard — they work across Claude Code, OpenCode, Cursor, and Codex via native discovery. Everything else (agents, commands, hooks) is provider-specific and lives under `providers/`.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Contributing](docs/CONTRIBUTING.md)

## License

MIT
