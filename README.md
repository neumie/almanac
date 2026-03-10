# Almanac

Personal agent toolkit — curated skills for LLM coding agents.

Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) and work across Claude Code, OpenCode, Cursor, Codex, and 25+ compatible agents.

## Install

```bash
# One-time setup
bash install.sh

# Then pick your provider
almanac install claude-code
```

Other providers:
```bash
# OpenCode
ln -s ~/.almanac/skills ~/.config/opencode/skills/almanac

# Cursor
ln -s ~/.almanac/skills ~/.cursor/skills/almanac

# Codex
ln -s ~/.almanac/skills ~/.agents/skills/almanac
```

## Skills

| Skill | What it does |
|-------|-------------|
| **tdd** | Red-green-refactor cycle, vertical slice approach, behavior-focused testing |
| **debugging** | Hypothesis-driven root cause analysis and regression prevention |
| **code-review** | Structured review: correctness, security, performance, maintainability |
| **planning** | Architecture decisions, task breakdown, trade-off analysis |
| **frontend-design** | Distinctive production-grade web interfaces, anti-generic-AI aesthetics |
| **mcp-builder** | Build MCP servers with proper tool design in TypeScript or Python |
| **webapp-testing** | Test web apps with Playwright — visual inspection, e2e validation |
| **skill-creator** | Create and validate skills against the Agent Skills Open Standard |
| **git-workflow** | Clean commits, branching strategy, safe history management |
| **refactoring** | Safe code restructuring: identify smells, apply patterns, preserve behavior |
| **catalog** | Lists all skills, helps choose workflows, explains how to combine skills |

## CLI

```
almanac install <provider>   Install for a provider
almanac uninstall <provider> Remove from a provider
almanac list                 List available providers
almanac update               Update almanac (git pull)
almanac sync                 Check adapted skills for upstream changes
almanac help                 Show help
```

### Upstream Sync

Four skills are adapted from [anthropics/skills](https://github.com/anthropics/skills) and track their upstream source. Run `almanac sync` to check for updates:

```
$ almanac sync
✓ frontend-design: up to date
✓ mcp-builder: up to date
⚠ skill-creator: upstream changed (adapted 2026-03-09)
```

## Structure

```
almanac/
├── skills/              # Agent Skills Open Standard (SKILL.md)
│   ├── tdd/
│   ├── debugging/       # + references/
│   ├── code-review/
│   ├── planning/        # + references/
│   ├── frontend-design/
│   ├── mcp-builder/     # + references/
│   ├── webapp-testing/  # + scripts/
│   ├── skill-creator/   # + references/
│   ├── git-workflow/    # + references/
│   ├── refactoring/
│   └── catalog/
├── providers/           # Provider-specific adapters
│   ├── claude-code/     # Full plugin (hooks, skills symlink)
│   ├── opencode/
│   ├── cursor/
│   └── codex/
├── lib/                 # Shared shell utilities
├── tests/               # Structure + skill validation
├── cmd/                 # CLI commands
├── bin/                 # CLI entry point
└── docs/                # Architecture & contributing
```

## Testing

```bash
bash tests/test-structure.sh   # Verify all files exist
bash tests/test-skills.sh      # Validate skills against spec
```

## License

MIT
