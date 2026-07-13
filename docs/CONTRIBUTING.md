# Contributing

## Adding a Skill

1. Pick a category — `git/` (git/`gh` ops), `agents-md/` (CLAUDE.md/AGENTS.md tooling), `loop/` (spec/tickets/implementation/loops — spec-create, to-tickets, implement, ralph-loop, harden-loop, converge-loop), `comms/` (client/team-facing comms), `productivity/`, or `other/`. Add a new category freely if none fit. Create `skills/<category>/<name>/SKILL.md`:

```yaml
---
name: your-skill-name
description: Use when [specific trigger condition]. [What it does].
---

# Your Skill

Step-by-step instructions for the agent...
```

2. **Name rules** (Agent Skills Open Standard):
   - 1-64 characters, lowercase alphanumeric + hyphens
   - No leading/trailing hyphens, no consecutive hyphens (`--`)
   - Must match the directory name exactly
   - Must be unique across the whole tree — `skills/git/foo/` and `skills/other/foo/` collide (validator hard-fails)

3. **Description**: must start with `Use when` (validator-enforced; a leading YAML quote is allowed) and state the trigger explicitly — agents tend to under-trigger. Hard cap 220 chars (validator-enforced) to keep the aggregated listing compact.

4. **Optional frontmatter**: `license`, `compatibility` (max 500 chars), `metadata` (key-value map), `allowed-tools`, `disable-model-invocation` (bool — strips skill from auto-listing; user-invocable via `/almanac:<name>`; orchestrators can still load it via path)

5. **Optional directories**: `scripts/` (executable code), `references/` (docs loaded on demand), `assets/` (templates, data)

6. **Keep SKILL.md under 500 lines.** Move detailed reference material to `references/`.

7. **Loop consumers**: if a loop uses shared role config, document its consumer prefix and role env vars in its skill docs and architecture notes. Follow the shared pattern: `<CONSUMER>_<ROLE>_{PROVIDER,MODEL,EFFORT}` first, then `<CONSUMER>_{PROVIDER,MODEL,EFFORT}`, then defaults. Example: converge uses `CONVERGE_AGENT_*` and `CONVERGE_OVERSEER_*`.

8. **Validate**: `bash tests/test-skills.sh`

When renaming a skill, update dependent `metadata.dependencies` entries plus README and architecture references in the same change.

## Adding a CLI Command

The `almanac` CLI is registry-driven — a command is valid iff `cmd/<name>.sh` exists. There is **no command list to edit**: `bin/almanac` dispatch, `almanac help`, and `tests/test-cli.sh` all derive from `almanac_list_commands` (globs `cmd/*.sh`). To add `almanac foo`:

1. Create `cmd/foo.sh` with the self-describing header (read by `almanac help`):

```bash
#!/usr/bin/env bash
# foo.sh — one-line description.
# summary: What `almanac help` shows for it
# usage: almanac foo <arg> [--flag]
# group: loops | providers | maintenance | other

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"

case "${1:-}" in
  -h|--help) printf '%s\n' "Usage: almanac foo <arg> [--flag]"; exit 0 ;;
esac
# … guard required values with `_need_value --flag "$#"`; _die terse on errors …
```

2. **Contract** (enforced by `bash tests/test-cli.sh`): the three `# summary:`/`# usage:`/`# group:` headers, `set -euo pipefail`, a `lib/` source, and a `-h|--help` arm that prints to stdout and exits 0. Commands are *sourced* into `bin/almanac` (not exec'd) — finish with `exit`, not `return`; `$ALMANAC_HOME` is already exported.
3. Put heavy logic in `lib/foo-core.sh` (mirror `hub-core.sh`) so the `cmd/` file stays a thin, testable parse+dispatch shim.
4. Add `cmd/foo.sh` to `tests/test-structure.sh` and run `bash tests/test-cli.sh && bash tests/test-structure.sh`.

## Adapting an Upstream Skill

When adapting from upstream sources (e.g. [mattpocock/skills](https://github.com/mattpocock/skills), [contember/agent-canvas](https://github.com/contember/agent-canvas)):

1. Add upstream tracking metadata. The value is `owner/repo/path`; `sync` appends `/SKILL.md`. Note `mattpocock/skills` nests skills under a `skills/<category>/` dir, so the path repeats `skills/`:
```yaml
metadata:
  upstream: mattpocock/skills/skills/<category>/<skill-name>
  upstream-sha: <SHA from gh api repos/mattpocock/skills/contents/skills/<category>/<skill-name>/SKILL.md --jq '.sha'>
  adapted-date: "YYYY-MM-DD"
```

2. Adapt the content — don't just copy. Trim Anthropic-specific tooling, align with Almanac conventions.

3. Run `almanac sync` to verify tracking works.

## Adding Reference Material

Add reference docs as markdown files in `skills/<category>/<name>/references/`. These are loaded on demand when the skill needs them. Keep them focused and actionable.

## Testing

```bash
bash tests/test-structure.sh   # All files and directories exist
bash tests/test-skills.sh      # All skills valid + negative test cases
```
