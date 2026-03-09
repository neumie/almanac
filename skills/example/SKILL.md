---
name: example
description: Use when you need a reference for the Agent Skills Open Standard format. Demonstrates required and optional frontmatter fields, directory structure, and progressive disclosure.
metadata:
  author: neumie
  version: "1.0"
compatibility: Works with all Agent Skills compatible agents
---

# Example Skill

Reference skill demonstrating the Agent Skills Open Standard (agentskills.io/specification).

## Frontmatter Fields

**Required:**
- `name` — max 64 chars, lowercase alphanumeric + hyphens, must match directory name
- `description` — max 1024 chars, describes what the skill does and when to use it

**Optional:**
- `license` — license name or reference to bundled LICENSE file
- `compatibility` — max 500 chars, environment requirements
- `metadata` — arbitrary key-value map (author, version, upstream tracking, etc.)
- `allowed-tools` — space-delimited pre-approved tools (experimental)

## Directory Structure

```
skill-name/
├── SKILL.md           # Required — frontmatter + instructions
├── scripts/           # Optional — executable code agents can run
├── references/        # Optional — additional docs loaded on demand
└── assets/            # Optional — templates, images, data files
```

## Progressive Disclosure

1. **Metadata** (~100 tokens) — `name` and `description` loaded at startup for all skills
2. **Instructions** (<5000 tokens) — full SKILL.md body loaded when skill activates
3. **Resources** (as needed) — files in scripts/, references/, assets/ loaded on demand

Keep SKILL.md under 500 lines. Move detailed reference material to separate files.
