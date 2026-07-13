# Almanac

Personal agent toolkit — curated skills for LLM coding agents.

Skills follow the [Agent Skills Open Standard](https://agentskills.io/specification) and work across Claude Code, OpenCode, Cursor, Codex, and [25+ compatible agents](https://agentskills.io).

## What are skills?

Skills are portable instruction sets that teach coding agents *how* to do things — commit code, create PRs, run TDD, fix CI, and more. Each skill is a single Markdown file (`SKILL.md`) with YAML frontmatter. Agents discover and load them automatically.

Run any skill as a slash command in your agent (e.g. `/commit`, `/ship`, `/ralph-loop`, `/converge-loop`).

Skills are organized by category in the repo (`skills/git/`, `skills/productivity/`, `skills/other/`, …) and flattened at install time so Claude Code's flat skill discovery finds them.

### Skill highlights

| Skill | Use |
|-------|-----|
| `ralph-loop` | Build a spec slice queue task-by-task, with each iteration committed. |
| `converge-loop` | Repeat one custom exec command toward a mutable `goal.md` until an overseer says done. |
| `spec-create` | Synthesize a conversation or idea into `docs/plans/<name>/spec.md` for the loops to consume. |
| `to-tickets` | Split a spec into blocked tracer-bullet tickets for GitHub or `docs/plans/`. |
| `implement` | Implement one agent-ready ticket through TDD, review, queue update, and commit. |
| `code-review` | Review changes since a fixed point on two parallel axes — repo standards and spec conformance. |
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

`almanac help` lists every command and `almanac <command> --help` shows its flags. Dispatch and help are registry-driven (one file per command under `cmd/`), so the listing never drifts from what's installed.

- **Loops** — `ralph`, `harden`, `converge`, and `hub` (the interactive front door: list / watch / launch loops)
- **Providers** — `install`, `uninstall`, `list`
- **Maintenance** — `update`, `sync`, `doctor`

```bash
almanac                                     # loop hub on a TTY, else this help
almanac harden <target>                     # fan out reviewers; --loop to converge, --watch to supervise
almanac harden <target> --help              # full flag list (--goal/--approve/--fix/--loop/…)
almanac converge --goal "…" --prompt "…"    # generic convergence loop (--exec for a shell command)
almanac hub --new <ralph|harden|converge>   # launch a run (add --dry-run to preview)
almanac install claude-code                 # install skills for an agent
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
    implement/
      SKILL.md
    ralph-loop/
      SKILL.md
    spec-create/
      SKILL.md
    to-tickets/
      SKILL.md
  other/
    code-review/
      SKILL.md
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

Thirteen skills are adapted from upstream repositories:

| Skill | Upstream |
|-------|----------|
| code-review | [mattpocock/skills](https://github.com/mattpocock/skills) |
| codebase-design | [mattpocock/skills](https://github.com/mattpocock/skills) |
| codebase-improve | [mattpocock/skills](https://github.com/mattpocock/skills) |
| diagnose | [mattpocock/skills](https://github.com/mattpocock/skills) |
| domain-model | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-me | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grill-with-docs | [mattpocock/skills](https://github.com/mattpocock/skills) |
| grilling | [mattpocock/skills](https://github.com/mattpocock/skills) |
| implement | [mattpocock/skills](https://github.com/mattpocock/skills) |
| prototype-build | [mattpocock/skills](https://github.com/mattpocock/skills) |
| spec-create | [mattpocock/skills](https://github.com/mattpocock/skills) |
| tdd | [mattpocock/skills](https://github.com/mattpocock/skills) |
| to-tickets | [mattpocock/skills](https://github.com/mattpocock/skills) |

Run `almanac sync` to check for updates.

## Adding a skill

1. Create `skills/<category>/<name>/SKILL.md` with YAML frontmatter
2. Use `noun-verb` naming (e.g. `pr-create`, `ci-fix`) — lowercase, hyphens only
3. Description starts with "Use when..."
4. Run `bash tests/test-skills.sh` to validate

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.

## License

MIT
