# CONTEXT.md Format

## Structure

```md
# {Context Name}

{One or two sentence description of what this context is and why it exists.}

## Language

**Order**:
{One or two sentence definition}
_Avoid_: Purchase, transaction

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request
```

## Rules

- Be opinionated. Pick the best term; list weaker synonyms under `_Avoid_`.
- Keep definitions tight. One or two sentences max.
- Define what the term is, not implementation behavior.
- Include only project-specific domain concepts. General programming concepts do not belong.
- Group terms under subheadings when natural clusters emerge.

## Single Vs Multi-Context Repos

Single context: one `CONTEXT.md` at repo root.

Multiple contexts: root `CONTEXT-MAP.md` lists contexts, locations, and relationships:

```md
# Context Map

## Contexts

- [Ordering](./src/ordering/CONTEXT.md): receives and tracks customer orders
- [Billing](./src/billing/CONTEXT.md): generates invoices and processes payments

## Relationships

- Ordering -> Fulfillment: Ordering emits `OrderPlaced`; Fulfillment consumes it.
- Fulfillment -> Billing: Fulfillment emits `ShipmentDispatched`; Billing invoices it.
```

Infer which structure applies:

- If `CONTEXT-MAP.md` exists, read it to find contexts.
- If only root `CONTEXT.md` exists, use single context.
- If neither exists, create root `CONTEXT.md` lazily when first term is resolved.

When multiple contexts exist, infer the relevant context from the topic. If unclear, ask.
