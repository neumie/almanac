# Agent Skills Open Standard — Quick Reference

Source: agentskills.io/specification

## SKILL.md Format

```yaml
---
name: skill-name          # Required, max 64 chars
description: What it does  # Required, max 1024 chars
license: MIT               # Optional
compatibility: Requires X  # Optional, max 500 chars
metadata:                  # Optional, arbitrary key-value
  author: example-org
  version: "1.0"
allowed-tools: Bash Read   # Optional, experimental
---

Markdown instructions here.
```

## Name Rules

- 1-64 characters
- Lowercase letters, numbers, hyphens only (`a-z`, `0-9`, `-`)
- Must not start or end with `-`
- Must not contain consecutive hyphens (`--`)
- Must match the parent directory name

## Directory Structure

```
skill-name/
├── SKILL.md          # Required
├── scripts/          # Optional — executable code
├── references/       # Optional — docs loaded on demand
└── assets/           # Optional — templates, images, data
```

## Progressive Disclosure

| Level | Content | Size | When loaded |
|-------|---------|------|-------------|
| Metadata | name + description | ~100 tokens | Always (startup) |
| Instructions | SKILL.md body | <5000 tokens | On activation |
| Resources | scripts/, references/, assets/ | As needed | On demand |

Keep SKILL.md under 500 lines.

## Validation

```bash
# Almanac validation
bash tests/test-skills.sh

# Official reference library
skills-ref validate ./my-skill
```
