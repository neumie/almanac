# Vertical Slice Development

Build one thin end-to-end path first. Then broaden.

## The Pattern

Instead of building all of layer 1, then all of layer 2, then all of layer 3 — build one complete path through all layers first.

```
Horizontal (anti-pattern):        Vertical (preferred):
┌──────────────────────┐          ┌──┐
│    All UI components │          │UI│
├──────────────────────┤          ├──┤
│    All API endpoints │          │AP│
├──────────────────────┤          ├──┤
│    All DB queries    │          │DB│
└──────────────────────┘          └──┘
                                  Then add more slices →
```

## Why It Works

- **Fast feedback**: You have something testable after the first slice
- **Reduced risk**: Integration issues surface immediately, not at the end
- **Natural checkpoints**: Each slice is a committable, reviewable unit
- **Better estimates**: After one slice, you know the real complexity

## How to Apply

### In Feature Development

1. Pick the simplest happy-path scenario
2. Implement it end-to-end (UI → API → DB → response → UI)
3. Test it works
4. Pick the next scenario, implement end-to-end
5. Repeat until done

**Example — User registration:**
- Slice 1: Register with email + password (happy path only)
- Slice 2: Validation errors (missing fields, bad email format)
- Slice 3: Duplicate email handling
- Slice 4: Email verification

### In TDD

One test, one implementation, one verification at a time:
```
Write test for scenario 1 → Implement → Green → Refactor
Write test for scenario 2 → Implement → Green → Refactor
...
```

Never write all tests first, then all implementation.

### In Migration Work

Migrate one entity/endpoint/flow at a time, not all entities, then all endpoints.

## Anti-Pattern: Horizontal Slicing

Signs you're slicing horizontally:
- "Let me set up all the database tables first"
- "I'll write all the API endpoints, then the frontend"
- "First let me create all the types and interfaces"
- Nothing works end-to-end until everything is done

The risk: you discover integration problems last, when they're hardest to fix.

## When Horizontal Is OK

- Setting up project scaffolding (build config, CI, linting)
- Database migrations (schema changes often need to be atomic)
- Shared infrastructure that multiple slices will need

Even then, keep it minimal — just enough for the first slice.
