# Almanac

Personal agent toolkit — curated skills for LLM coding agents.

Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) and work across Claude Code, OpenCode, Cursor, Codex, and [25+ compatible agents](https://agentskills.io).

## What are skills?

Skills are portable instruction sets that teach coding agents *how* to do things — commit code, create PRs, run TDD, fix CI, and more. Each skill is a single Markdown file (`SKILL.md`) with YAML frontmatter. Agents discover and load them automatically.

Run any skill as a slash command in your agent (e.g. `/commit`, `/ship`, `/ralph-loop`).

## Install

```bash
# One-time setup — clones to ~/.almanac and adds to PATH
bash install.sh

# Pick your agent
almanac install claude-code
```

<details>
<summary>Other agents</summary>

```bash
almanac install opencode
almanac install cursor
almanac install codex
```

Or manually symlink:

```bash
ln -s ~/.almanac/skills ~/.config/opencode/skills/almanac   # OpenCode
ln -s ~/.almanac/skills ~/.cursor/skills/almanac             # Cursor
ln -s ~/.almanac/skills ~/.agents/skills/almanac             # Codex
```

</details>

### Global config

The installer can symlink a versioned `~/.claude/CLAUDE.md` for global Claude Code settings:

```bash
almanac install claude-code                  # skips if you have a custom CLAUDE.md
almanac install claude-code --global-config  # replaces with almanac's version
```

## CLI

```
almanac install <provider>   Install for a provider
almanac uninstall <provider> Remove from a provider
almanac list                 List available providers and install status
almanac update               Update almanac (git pull + re-install)
almanac sync                 Check adapted skills for upstream changes
almanac help                 Show help
```

### Upstream sync

Eight skills are adapted from upstream repositories:

| Skill | Upstream |
|-------|----------|
| codebase-improve | [mattpocock/skills](https://github.com/mattpocock/skills) |
| diagnose | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-me | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-plan | [mattpocock/skills](https://github.com/mattpocock/skills) |
| issues-create | [mattpocock/skills](https://github.com/mattpocock/skills) |
| prd-create | [mattpocock/skills](https://github.com/mattpocock/skills) |
| tdd | [mattpocock/skills](https://github.com/mattpocock/skills) |
| interface-design | [Dammyjay93/interface-design](https://github.com/Dammyjay93/interface-design) |

Run `almanac sync` to check for updates.

## Adding a skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter
2. Use `noun-verb` naming (e.g. `pr-create`, `ci-fix`) — lowercase, hyphens only
3. Description starts with "Use when..."
4. Run `bash tests/test-skills.sh` to validate

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.

## License

MIT
