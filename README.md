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
| **branch-name** | Generate descriptive branch names from branch contents |
| **canvas** | Interactive visual canvas for structured communication (adapted from contember/agent-canvas) |
| **ci-fix** | Fix failing GitHub Actions by reading logs and patching code |
| **commit** | Analyze changes, write conventional commit messages, commit immediately |
| **interview-me** | Stress-test plans and designs through relentless questioning (adapted from mattpocock/skills) |
| **pr-create** | Create GitHub PRs with auto-generated titles and descriptions |
| **push** | Push branch to remote safely with tracking and divergence checks |
| **rebase** | Rebase onto base branch with conflict handling |
| **ship** | Name branch, commit, push, and create PR in one step |
| **ubiquitous-language** | Extract and formalize domain terminology into a DDD-style glossary (adapted from mattpocock/skills) |

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

Three skills are adapted from upstream sources and track their origin. Run `almanac sync` to check for updates:

```
$ almanac sync
✓ canvas: up to date
✓ interview-me: up to date
⚠ ubiquitous-language: upstream changed (adapted 2026-03-19)
```

## Structure

```
almanac/
├── skills/              # Agent Skills Open Standard (SKILL.md)
│   ├── branch-name/
│   ├── canvas/          # + flows.md, components.md
│   ├── ci-fix/
│   ├── commit/
│   ├── interview-me/
│   ├── pr-create/
│   ├── push/
│   ├── rebase/
│   ├── ship/
│   └── ubiquitous-language/
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
