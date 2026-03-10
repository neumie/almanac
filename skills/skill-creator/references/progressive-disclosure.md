# Progressive Disclosure Pattern

Load only what's needed, when it's needed. Minimize context usage.

## Three Levels

| Level | Content | Size Target | When Loaded |
|-------|---------|-------------|-------------|
| **Metadata** | name + description | ~100 tokens | Always (startup) |
| **Instructions** | SKILL.md body | <5000 tokens | On skill activation |
| **Resources** | scripts/, references/, assets/ | Unlimited | On demand |

## When to Split

**Keep in SKILL.md** when:
- The agent needs it every time the skill activates
- It's under 500 lines total
- It's the core workflow or decision tree

**Move to references/** when:
- It's domain-specific detail (one of several variants)
- It's a lookup table or specification
- The agent only needs it for certain sub-tasks
- It's over 300 lines on its own

**Move to scripts/** when:
- It's executable code the agent runs
- It's deterministic (same input → same output)
- It replaces something the agent would otherwise generate on the fly

## Design for Lazy Loading

Reference files from SKILL.md with clear guidance on when to read them:

```markdown
For TypeScript projects, see [references/typescript-guide.md](references/typescript-guide.md).
For Python projects, see [references/python-guide.md](references/python-guide.md).
```

The agent reads only the relevant file, keeping context lean.

## Anti-Patterns

- **Monolithic SKILL.md**: Everything in one file. Context gets saturated, agent performance degrades.
- **Eager loading**: Reading all reference files upfront "just in case."
- **Deep chains**: File A references file B which references file C. Keep it one level deep from SKILL.md.
