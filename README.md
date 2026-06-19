# Almanac

Personal agent toolkit — curated skills for LLM coding agents.

Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) and work across Claude Code, OpenCode, Cursor, Codex, and [25+ compatible agents](https://agentskills.io).

## What are skills?

Skills are portable instruction sets that teach coding agents *how* to do things — commit code, create PRs, run TDD, fix CI, and more. Each skill is a single Markdown file (`SKILL.md`) with YAML frontmatter. Agents discover and load them automatically.

Run any skill as a slash command in your agent (e.g. `/commit`, `/ship`, `/ralph-loop`, `/harden-loop`, `/converge-loop`).

Skills are organized by category in the repo (`skills/git/`, `skills/productivity/`, `skills/other/`, …) and flattened at install time so Claude Code's flat skill discovery finds them.

### Skill highlights

| Skill | Use |
|-------|-----|
| `ralph-loop` | Build a PRD slice queue task-by-task, with each iteration committed. |
| `harden-loop` | Harden one target through reviewers, ratification, fixer, and feedback gates. |
| `converge-loop` | Repeat one custom exec command toward a mutable `goal.md` until an overseer says done. |
| `codebase-design` | Shared vocabulary for deep modules, interfaces, seams, adapters, and testability. |
| `domain-model` | Maintain `CONTEXT.md` domain language and ADRs while design decisions crystallize. |
| `prototype-build` | Build throwaway logic or UI prototypes to answer design questions before production code. |

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

`almanac install codex` links skills into `~/.agents/skills/almanac/<name>`, so skills can be invoked as `$ship`, `$commit`, etc. or browsed from `/skills` after restarting Codex.

Or manually symlink:

```bash
ln -s ~/.almanac/skills ~/.config/opencode/skills/almanac   # OpenCode
ln -s ~/.almanac/skills ~/.cursor/skills/almanac             # Cursor
ln -s ~/.almanac/skills ~/.agents/skills/almanac             # Codex
```

</details>

### Global config

The installer symlinks a versioned global instruction file into each provider, all pointing at the same canonical source (`providers/_shared/AGENTS.md`):

- `claude-code` → `~/.claude/CLAUDE.md`
- `codex` → `~/.codex/AGENTS.md`

```bash
almanac install claude-code                  # skips if you have a custom CLAUDE.md
almanac install claude-code --global-config  # replaces with almanac's version
almanac install codex                        # same, for ~/.codex/AGENTS.md
```

## CLI

```
almanac                      Open the interactive loop hub (in a TTY); else print help
almanac hub                  Open the interactive loop hub (launch / list / watch loops)
almanac hub --new <type>     Launch a new ralph|harden|converge run (add --dry-run to preview)
almanac install <provider>   Install for a provider
almanac uninstall <provider> Remove from a provider
almanac list                 List available providers and install status
almanac ralph                Launch the interactive Ralph loop CLI
almanac harden <target>      Fan out read-only reviewers (one per lens) and aggregate findings
                             (lens set via HARDEN_LENSES; default: correctness security perf edge-cases contracts)
                             <target> is free-form: a path, a PR ref ("PR 47"), or a description —
                             reviewers locate the code themselves (no filesystem check)
almanac harden <target> --goal "<goal>"
                             Draft a harden-loop rubric for a target
almanac harden <target> --approve
                             Approve an edited harden-loop rubric
almanac harden <target> --fix
                             Run one sequential fixer over open blocking findings + feedback loops
almanac harden <target> --loop [--rounds N]
                             Run the convergence loop until converged or budget hit
                             (HITL checkpoint each round: ship / continue / steer)
                             (git target: each round commits its changes — set
                             HARDEN_AUTOCOMMIT=0 to leave fixes uncommitted)
almanac harden <target> --watch
                             Redraw the live supervision dashboard for the latest run
almanac harden <target> --watch-worker <lens>
                             Stream one reviewer's live event log
almanac converge --goal "<goal>" --prompt "<text>" [--rounds N]
                             Run a generic convergence loop with one agent prompt per round
almanac converge --goal "<goal>" --exec "<cmd>" [--rounds N]
                             Run a generic convergence loop with one custom exec per round
almanac converge <slug>      Print a converge run status summary
almanac converge <slug> --watch
                             Redraw the live converge dashboard
almanac converge <slug> --stop
                             Request a graceful stop at the next round boundary
almanac update               Update almanac (git pull + re-install)
almanac sync                 Check adapted skills for upstream changes
almanac doctor               Report optional-dependency status (gum, gh, jq)
almanac help                 Show help
```

### Loop examples

```bash
almanac ralph
almanac harden lib/role.sh --loop --rounds 3
almanac converge \
  --goal "Improve the codebase until no major architecture friction remains" \
  --exec "claude -p '/almanac:codebase-improve'" \
  --rounds 5
```

### Repository structure

```text
bin/almanac
cmd/
  converge.sh
  harden.sh
  ralph.sh
lib/
  converge-core.sh
  harden-core.sh
  loop-launcher.sh
  loops/
    converge.sh
    harden.sh
    ralph.sh
skills/
  loop/
    converge-loop/
      SKILL.md
    harden-loop/
      SKILL.md
    ralph-loop/
      SKILL.md
  other/
    codebase-design/
      SKILL.md
      references/
    domain-model/
      SKILL.md
      references/
    prototype-build/
      SKILL.md
      references/
```

### Upstream sync

Eleven skills are adapted from upstream repositories:

| Skill | Upstream |
|-------|----------|
| codebase-design | [mattpocock/skills](https://github.com/mattpocock/skills) |
| codebase-improve | [mattpocock/skills](https://github.com/mattpocock/skills) |
| diagnose | [mattpocock/skills](https://github.com/mattpocock/skills) |
| domain-model | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-me | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-with-docs | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grilling | [mattpocock/skills](https://github.com/mattpocock/skills) |
| issues-create | [mattpocock/skills](https://github.com/mattpocock/skills) |
| prototype-build | [mattpocock/skills](https://github.com/mattpocock/skills) |
| prd-create | [mattpocock/skills](https://github.com/mattpocock/skills) |
| tdd | [mattpocock/skills](https://github.com/mattpocock/skills) |

Run `almanac sync` to check for updates.

## Adding a skill

1. Create `skills/<category>/<name>/SKILL.md` with YAML frontmatter
2. Use `noun-verb` naming (e.g. `pr-create`, `ci-fix`) — lowercase, hyphens only
3. Description starts with "Use when..."
4. Run `bash tests/test-skills.sh` to validate

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.

## License

MIT
