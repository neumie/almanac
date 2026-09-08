# UI Prototype

Generate several radically different UI variants on one route, switchable from a floating bottom bar. User flips between variants, picks one or combines parts, then the rest is deleted.

If the question is logic or state, use [logic.md](logic.md).

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

Default to three variants; use at most five unless the user requests a different count. Honor an explicit count such as ten. Write one line near prototype:

> Three variants of settings page, switchable via `?variant=`, on existing `/settings` route.

### 2. Generate Variants In Parallel — One Subagent Per Variant

The coordinator owns the question, research, shared data/props, minimal shell, switcher, and final integration. Establish that small common contract first, then launch **one implementation subagent per variant in parallel**. Do not give one worker all variants to build serially.

- Give each agent a distinct structural direction: layout, hierarchy, and primary affordance, not just different colors or copy. Share the same research, fixture data, component APIs, and constraints so comparisons stay fair.
- Keep assignments bounded: one variant module, its export contract, intended use, and tradeoff. Agents should not repeat the shared research, build their own shell, or start their own review/delegation chains.
- Isolate writers in separate worktrees or draft directories. If worktree isolation is unavailable or the checkout is dirty, have agents write draft artifacts in separate directories for one integrator to apply. Do not have parallel agents edit a shared checkout, registry, styles, or switcher.
- Use the harness's delegation workflow and available concurrency. Queue excess variants when capacity is limited; report the limit rather than silently reverting to one serial implementation worker. If delegation is unavailable or the user requests no subagents, state the constraint and use a single writer.
- Collect all variant outputs, then integrate with one writer. Run shared checks once after integration; visually verify each variant at the target viewport. Keep browser verification serial or use isolated browser sessions. Follow project review requirements without adding a prototype-specific test framework.

Respect the project's component library and styling system. Share data and basic primitives, not so much layout that the variants stop disagreeing.

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

- One worker implementing all variants serially when parallel delegation is available
- Parallel variant agents modifying the same checkout or shared shell
- Variants differing only in color/copy
- Sharing layout so much variants stop disagreeing
- Real mutations
- Promoting prototype code directly to production without rewriting production-quality code
