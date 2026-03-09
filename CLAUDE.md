# Almanac — Project Conventions

## What is this

Provider-agnostic agent toolkit. Skills are the open standard (work across all providers). Provider adapters wire them in.

## Structure

- `skills/` — open standard, each skill has `SKILL.md` with YAML frontmatter
- `prompts/` — reusable prompt templates (plain markdown)
- `patterns/` — reference docs and agent patterns (plain markdown)
- `providers/` — provider-specific adapters
- `lib/` — shared shell utilities
- `tests/` — validation scripts

## Skill Format

```yaml
---
name: lowercase-kebab-case
description: Use when [condition]
---
# Markdown body
```

- Name: lowercase letters, numbers, hyphens only
- Description: always starts with "Use when..."
- Frontmatter: max 1024 chars

## Testing

```bash
bash tests/test-structure.sh
bash tests/test-skills.sh
```
