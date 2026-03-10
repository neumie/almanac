---
name: skill-creator
description: Use when creating new skills, modifying existing skills, or validating skill format against the Agent Skills Open Standard. Guides the full skill creation lifecycle from intent capture through writing and testing. Use this whenever the user wants to create, edit, or improve a skill.
metadata:
  upstream: anthropics/skills/skill-creator
  upstream-sha: 65b3a402dbd09b8e83f9d637c6b553875189085c
  adapted-date: "2026-03-09"
---

# Skill Creator

Create and improve skills following the Agent Skills Open Standard.

## Process

### 1. Capture Intent

Understand what the user wants the skill to do:
- What should this skill enable the agent to do?
- When should this skill trigger? (what user phrases/contexts)
- What's the expected output format?
- Does it need scripts, references, or assets?

If the conversation already contains a workflow the user wants to capture (e.g., "turn this into a skill"), extract the tools used, steps taken, and corrections made.

### 2. Write the SKILL.md

See [references/spec-summary.md](references/spec-summary.md) for the full spec reference.

**Required frontmatter:**
```yaml
---
name: lowercase-kebab-case
description: Use when [specific triggering condition]. [What the skill does].
---
```

**Key rules:**
- `name`: 1-64 chars, lowercase alphanumeric + hyphens, must match directory name
- `description`: 1-1024 chars, include both what and when to trigger
- Make descriptions slightly "pushy" — agents tend to under-trigger skills

**Body content:**
- Step-by-step instructions in imperative form
- Examples of inputs and outputs
- Common edge cases
- Keep under 500 lines; move details to `references/`

### 3. Structure for Progressive Disclosure

```
skill-name/
├── SKILL.md           # Required — triggers + core instructions
├── scripts/           # Optional — executable code
├── references/        # Optional — detailed docs, loaded on demand
└── assets/            # Optional — templates, data files
```

Three loading levels:
1. **Metadata** (~100 tokens): name + description, always loaded
2. **Instructions** (<5000 tokens): SKILL.md body, loaded on activation
3. **Resources** (as needed): files in scripts/, references/, assets/

### 4. Validate

Run validation:
```bash
bash tests/test-skills.sh
```

Check:
- Frontmatter parses correctly
- Name matches directory
- Description is descriptive and includes trigger conditions
- Body has clear, actionable instructions

### 5. Iterate

Test the skill by using it in a conversation. Observe:
- Does it trigger when expected?
- Are the instructions clear enough for the agent to follow?
- Does it produce the expected output?

Revise based on observations.

## Writing Tips

- Explain **why** things matter rather than just demanding compliance
- Use theory of mind — anticipate where the agent might go wrong
- Prefer the imperative form: "Extract the data" not "The data should be extracted"
- Include examples showing input → output patterns
- Keep it general enough to apply across contexts, specific enough to be actionable
