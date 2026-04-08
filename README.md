# Almanac

Personal agent toolkit — curated skills for LLM coding agents.

Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) and work across Claude Code, OpenCode, Cursor, Codex, and [25+ compatible agents](https://agentskills.io).

## What are skills?

Skills are portable instruction sets that teach coding agents *how* to do things — commit code, create PRs, run TDD, fix CI, and more. Each skill is a single Markdown file (`SKILL.md`) with YAML frontmatter. Agents discover and load them automatically.

Almanac bundles 17 skills organized around a typical development workflow:

```
task-start → complexity-assess → tdd / test-write → commit → push → pr-create → pr-watch → ci-fix
                                                         └── ship (does it all in one step) ──┘
```

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

## Skills

### Git workflow

| Skill | What it does |
|-------|-------------|
| **branch-name** | Generate descriptive branch names from branch contents |
| **commit** | Analyze changes, write conventional commit messages, commit immediately |
| **push** | Push branch to remote safely with tracking and divergence checks |
| **rebase** | Rebase onto base branch with conflict handling and squash support |

### Pull requests & CI

| Skill | What it does |
|-------|-------------|
| **pr-create** | Create GitHub PRs with auto-generated titles and descriptions |
| **pr-watch** | Watch PR CI checks, auto-fix failures, report when ready to merge |
| **ci-fix** | Fix failing GitHub Actions by reading logs and patching code |

### Development

| Skill | What it does |
|-------|-------------|
| **tdd** | Red-green-refactor TDD with vertical slices |
| **test-write** | Backfill behavior-focused regression tests on existing code |
| **canvas** | Interactive visual canvas for structured communication |
| **interface-design** | Craft-focused interface design for dashboards, admin panels, and SaaS apps |

### Planning & process

| Skill | What it does |
|-------|-------------|
| **task-start** | Assess complexity and route to the right execution depth (trivial/moderate/complex) |
| **complexity-assess** | Evaluate task complexity using a structured heuristic (scope, clarity, risk, novelty) |
| **interview-me** | Stress-test plans and designs through relentless questioning |
| **ubiquitous-language** | Extract and formalize domain terminology into a DDD-style glossary |
| **session-recap** | Summarize current branch work to pick up where you left off |

### Orchestration

| Skill | What it does |
|-------|-------------|
| **ship** | Name branch, commit, push, and create PR — all in one step |

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

Five skills are adapted from upstream repositories and track their origin:

| Skill | Upstream |
|-------|----------|
| canvas | [contember/agent-canvas](https://github.com/niclas-niclas/agent-canvas) |
| interface-design | [Dammyjay93/interface-design](https://github.com/Dammyjay93/interface-design) |
| interview-me | [mattpocock/skills](https://github.com/mattpocock/dotfiles) |
| tdd | [mattpocock/skills](https://github.com/mattpocock/dotfiles) |
| ubiquitous-language | [mattpocock/skills](https://github.com/mattpocock/dotfiles) |

Run `almanac sync` to check for updates:

```
$ almanac sync
✓ canvas: up to date
✓ interview-me: up to date
✓ tdd: up to date
⚠ ubiquitous-language: upstream changed (adapted 2026-03-19)
```

## Structure

```
almanac/
├── skills/              # Agent Skills Open Standard (SKILL.md per skill)
│   ├── branch-name/
│   ├── canvas/          # + references/ (flows, components)
│   ├── ci-fix/
│   ├── commit/
│   ├── complexity-assess/
│   ├── interface-design/ # + references/ (principles, critique, examples)
│   ├── interview-me/
│   ├── pr-create/
│   ├── pr-watch/
│   ├── push/
│   ├── rebase/
│   ├── session-recap/
│   ├── ship/
│   ├── task-start/      # + references/
│   ├── tdd/             # + references/
│   ├── test-write/
│   └── ubiquitous-language/
├── providers/           # Provider-specific adapters
│   ├── claude-code/     # Full plugin (hooks, skills symlink)
│   ├── opencode/
│   ├── cursor/
│   └── codex/
├── lib/                 # Shared shell utilities
├── cmd/                 # CLI commands
├── bin/                 # CLI entry point
├── tests/               # Structure + skill validation
└── docs/                # Architecture & contributing guides
```

## How it works

**Two-layer design.** The `skills/` directory is provider-agnostic — every agent reads the same `SKILL.md` files. The `providers/` directory holds adapters for agent-specific features like hooks and plugin manifests.

**Progressive disclosure.** Agents load skill metadata (~100 tokens) at startup for discovery, full instructions (<5,000 tokens) only on activation, and reference material on demand. This keeps context windows lean.

**Skill deduplication.** Orchestrator skills like `ship` delegate to standalone skills (`branch-name`, `commit`, `push`, `pr-create`) rather than inlining their logic. Each capability has exactly one source of truth.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Adding a skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter
2. Use `noun-verb` naming (e.g. `pr-create`, `ci-fix`) — lowercase, hyphens only
3. Description starts with "Use when..."
4. Run `bash tests/test-skills.sh` to validate

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.

## Testing

```bash
bash tests/test-structure.sh   # Verify all files and directories exist
bash tests/test-skills.sh      # Validate all skills against the spec
```

## License

MIT
