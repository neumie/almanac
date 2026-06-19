# UI Prototype

Generate several radically different UI variants on one route, switchable from a floating bottom bar. User flips between variants, picks one or combines parts, then the rest is deleted.

If the question is logic or state, use `references/logic.md`.

## Good Fit

- "What should this page look like?"
- "Show a few dashboard options before committing."
- "Try a different settings layout."

## Two Shapes

### Existing Page Preferred

Use an existing route when possible. Keep existing data fetching, params, auth, and density. Swap only the rendered subtree by `?variant=`.

### New Throwaway Page

Use only when no existing page can host the idea. Follow existing routing conventions and mark route/file as prototype.

## Process

### 1. State Question And Pick Variant Count

Default to three variants. Cap at five. Write one line near prototype:

> Three variants of settings page, switchable via `?variant=`, on existing `/settings` route.

### 2. Generate Radically Different Variants

Each variant should differ structurally: layout, hierarchy, primary affordance. Not just color or copy.

Respect project component library and styling system.

### 3. Wire Variants

Use URL search param:

```tsx
const variant = searchParams.get("variant") ?? "A";
return (
  <>
    {variant === "A" && <VariantA {...data} />}
    {variant === "B" && <VariantB {...data} />}
    {variant === "C" && <VariantC {...data} />}
    <PrototypeSwitcher variants={["A", "B", "C"]} current={variant} />
  </>
);
```

For existing pages, keep existing data fetching above switcher. For throwaway pages, mount same switcher under prototype route.

### 4. Floating Switcher

Build one reusable switcher:

- Left arrow cycles previous variant.
- Label shows current variant and optional variant name.
- Right arrow cycles next variant.
- Clicks update URL search param.
- Left/right keyboard arrows cycle variants, except while input, textarea, or contenteditable is focused.
- Visually distinct from page.
- Hidden in production builds.

### 5. Capture And Clean Up

Once a variant wins, write down which one and why. Delete losing variants and switcher, or promote winner and remove throwaway route.

## Anti-Patterns

- Variants differing only in color/copy
- Sharing layout so much variants stop disagreeing
- Real mutations
- Promoting prototype code directly to production without rewriting production-quality code
