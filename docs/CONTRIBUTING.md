# Contributing

## Adding a Skill

1. Create a directory under `skills/` with your skill name (lowercase-kebab-case)
2. Add a `SKILL.md` file with YAML frontmatter:

```yaml
---
name: your-skill-name
description: Use when [triggering condition]
---

# Your Skill

Instructions for the agent...
```

**Requirements:**
- `name`: lowercase-kebab-case, letters/numbers/hyphens only
- `description`: starts with "Use when..."
- Frontmatter must be under 1024 characters
- Run `bash tests/test-skills.sh` to validate

## Adding a Prompt

Add a markdown file to `prompts/`. No required format.

## Adding a Pattern

Add a markdown file to `patterns/`. No required format.

## Adding Provider-Specific Content

Provider-specific content (agents, commands, hooks) goes under `providers/<provider-name>/`. See the Claude Code adapter in `providers/claude-code/` for a reference implementation.

## Testing

```bash
bash tests/test-structure.sh   # Validate repo structure
bash tests/test-skills.sh      # Validate skill format
```
