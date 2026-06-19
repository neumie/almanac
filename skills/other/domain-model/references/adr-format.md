# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.

Create `docs/adr/` lazily, only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: context, decision, rationale.}
```

That can be the whole ADR. Value comes from recording that a decision was made and why, not filling sections.

## Optional Sections

Use these only when they add value:

- **Status** frontmatter: `proposed`, `accepted`, `deprecated`, `superseded by ADR-NNNN`
- **Considered Options**: rejected alternatives worth remembering
- **Consequences**: non-obvious downstream effects

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When To Offer An ADR

All three must be true:

1. **Hard to reverse**
2. **Surprising without context**
3. **Result of a real trade-off**

Skip easy, obvious, or no-choice decisions.

Good ADR topics:

- Architectural shape
- Integration patterns between contexts
- Technology choices with real lock-in
- Ownership and scope decisions
- Deliberate deviations from obvious defaults
- Constraints invisible in code
- Non-obvious rejected alternatives
