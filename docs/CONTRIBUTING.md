# Contributing

## Adding a Skill

1. Pick a category — `git/` (git/`gh` ops), `agents-md/` (CLAUDE.md/AGENTS.md tooling), `loop/` (PRD/issues/autonomous loops — ralph-loop, harden-loop), `comms/` (client/team-facing comms), or `other/`. Add a new category freely if none fit. Create `skills/<category>/<name>/SKILL.md`:

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

7. **Validate**: `bash tests/test-skills.sh`

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

Add reference docs as markdown files in `skills/<name>/references/`. These are loaded on demand when the skill needs them. Keep them focused and actionable.

## Testing

```bash
bash tests/test-structure.sh   # All files and directories exist
bash tests/test-skills.sh      # All skills valid + negative test cases
```
