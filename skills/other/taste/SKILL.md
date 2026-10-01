---
name: taste
description: Use when designing or redesigning landing pages, portfolios, marketing sites, or editorial frontends with intentional layout, typography, imagery, and motion instead of generic AI styling.
license: MIT
metadata:
  upstream: leonxlnx/taste-skill/skills/taste-skill
  upstream-sha: b72132fcd466da605623ffe96e370b3991fc5285
  adapted-date: "2026-10-01"
---

# Taste

Adapted from [Taste Skill](https://github.com/leonxlnx/taste-skill), the upstream v2 (experimental) frontend design skill. Build interfaces from the brief, not a default aesthetic. See [provenance](references/upstream.md) and the bundled [MIT notice](LICENSE).

## Scope and authority

Use for landing pages, portfolios, marketing sites, editorial pages, and their redesigns. This is not a dashboard, dense data-table, admin-panel, multi-step wizard, native-mobile, or realtime-collaboration design framework. For those requests, explain the mismatch and apply these rules only to an accompanying marketing surface.

The brief, existing brand, project instructions, accessibility, and approved implementation contract override aesthetic defaults in this skill and its references. Do not apply it as an unsolicited site-wide redesign.

- Preserve the existing framework, styling system, component library, package manager, and supported browsers. No mandatory React, Next.js, Tailwind, Motion, or GSAP migration.
- Check installed dependencies before importing. New packages, font licenses, paid assets, external services, or image-generation costs need approval when not already authorized. Never run reference install commands automatically.
- Use available project tooling; this skill does not authorize delegation or require a review pipeline.
- For a focused change, inspect and validate the affected surface only. Full-page audits and pre-flight checks apply to full builds or redesigns, not a padding or copy tweak.
- Preserve supplied facts, quotes, legal text, and brand names. Never invent customers, testimonials, scarcity, metrics, or product specifications. Mock data must be explicitly labeled as mock; realistic-looking numbers are not evidence.

## 1. Read the brief

Before code, inspect:

1. Page kind: SaaS/consumer/agency/event landing, developer/designer/studio portfolio, editorial, or redesign.
2. Audience: technical buyers, procurement, consumers, recruiters, readers.
3. Vibe words, reference URLs, screenshots, competitors, and existing assets.
4. Quiet constraints: accessibility, public sector, regulation, trust, performance, content rights.
5. Existing routes, brand tokens, component conventions, and the requested scope.

State one concise design read in the user's language:

> Reading this as: <page kind> for <audience>, with a <vibe> language, leaning toward <existing design system or aesthetic family>.

Ask a focused clarifying question only if plausible interpretations would materially diverge. Otherwise declare the interpretation and proceed.

Avoid automatic AI-purple gradients, centered heroes over dark mesh, three identical feature cards, glass on every surface, endless micro-animation, or the same font/palette for every brand.

## 2. Set the three dials

Use these exact names. Values are conversational overrides, not edits the user must make to this file. Clamp to 1-10.

- `DESIGN_VARIANCE`: 1 = symmetry and familiar structure; 10 = expressive asymmetry.
- `MOTION_INTENSITY`: 1 = static; 10 = cinematic choreography.
- `VISUAL_DENSITY`: 1 = gallery-like breathing room; 10 = tightly packed information.

Baseline is **8 / 6 / 4**, but the brief and scope decide. Explicitly state chosen values for a full-page build.

| Brief | VARIANCE | MOTION | DENSITY |
|---|---|---|---|
| Minimalist, calm, Linear-style | 5-6 | 3-4 | 2-3 |
| Mainstream SaaS landing | 7 | 6 | 4 |
| Premium consumer | 7-8 | 5-7 | 3-4 |
| Creative agency, experimental | 9-10 | 8-10 | 3-4 |
| Designer/studio portfolio | 8 | 7 | 3 |
| Developer portfolio | 6 | 5 | 4 |
| Editorial/blog | 6 | 4 | 3 |
| Public sector, trust-first, accessibility-critical | 3-4 | 2-3 | 4-5 |
| Redesign, preserve | match existing | match or +1 if justified | match existing |
| Redesign, overhaul | existing +2 | existing +2 if justified | match existing |

Higher variance does not excuse broken mobile layout. Higher motion does not excuse inaccessible or unfinished interactions. If motion cannot be delivered reliably within scope, lower the dial and ship a deliberate static composition.

## 3. Load the relevant references

For a full build or redesign, read [design engineering](references/design.md) and [anti-slop patterns](references/anti-slop.md) before implementation.

- Choosing a foundation or material treatment: [design systems](references/design-systems.md). Use official packages when approved and applicable; distinguish a system from an aesthetic. Web glass is not official Apple Liquid Glass.
- Adding animation: [motion and accessibility](references/motion.md). Includes sticky-stack, horizontal-pan, and reveal-stagger examples. Adapt examples to the project's stack, dimensions, dynamic content, mobile, and reduced-motion behavior; they are starting points, not drop-in guarantees.
- Discussing layout or dialing expression: [pattern vocabulary and dial definitions](references/patterns.md). Pattern names are vocabulary, not installed components.
- Finishing a full build: [pre-flight checklist](references/pre-flight.md). Apply relevant checks to the requested scope; mark inapplicable checks explicitly.

References retain upstream section numbers for traceability. The rules below resolve conflicting upstream defaults: brand fidelity beats palette/font bans; approved scope beats mandatory new imagery or dual-theme expansion; factual integrity beats plausible fake data; one animation owner per element beats a blanket ban on libraries coexisting.

## 4. Implement intentionally

### Composition, typography, and copy

- Establish one palette, accent treatment, radius scale, spacing rhythm, and theme strategy. Semantic success/warning/error colors remain allowed and must not lose meaning.
- Choose type from brand and audience. Do not default to Inter, a random serif, or beige-and-brass because the model associates them with “premium.” Retain those choices when the brief or existing identity supports them.
- Keep heroes focused: headline, short supporting copy, a primary CTA, and at most one secondary action. Plan type and imagery together so primary content fits at normal desktop sizes; never clip content to enforce a line count at zoom or on mobile.
- Use intentional grid rhythm and whitespace rather than equal-card repetition or decorative micro-labels on every section. Each cell needs real content.
- Keep one CTA label per intent; repeated placements with that same label are fine.
- Use concrete, grammatical copy. Avoid filler verbs, ornamental version stamps, fictional credits, decorative status dots, and fake product screenshots made of divs.
- For newly authored marketing copy, avoid em/en-dash flourishes; use clear sentences. Do not silently rewrite exact quotations, legal text, localization, or supplied copy to satisfy a punctuation preference.
- Use approved real assets or actual product/component previews. If assets are missing, clearly label placeholder slots and list what is needed. Do not present random stock photos or invented logos as real product imagery or customer proof.

### Engineering and interaction

- Follow the project's layout/container/breakpoint conventions. Prefer Grid over fragile percentage arithmetic; make each multi-column section's mobile collapse explicit.
- Use dynamic viewport units for full-height sections where supported, with project-appropriate fallbacks. Avoid fixed heights that hide content.
- In React/Next.js, keep interactive animation in client leaves; server components render static content. Keep providers on the correct side of the client boundary.
- Use local state for discrete UI state, not per-frame scroll/pointer positions. Use the project's motion values, CSS, or animation engine for continuous updates.
- Reuse the project's icon family. Do not add another library just to replace an existing one or hand-draw arbitrary icon paths.
- Implement relevant loading, empty, error, hover, focus, and active states. Use semantic labels above fields; placeholders never replace labels.
- Keep buttons readable and labels unbroken at ordinary desktop sizes. At narrow widths and zoom, allow accessible reflow rather than clipping.

### Motion, accessibility, and performance

- Every animation needs a reason: hierarchy, storytelling, feedback, or state transition. A high motion dial is not permission for endless decoration.
- Honor `prefers-reduced-motion` for **all** nonessential animation, even low-dial motion. Pinning, parallax, infinite loops, and magnetic physics must degrade to readable static content.
- Prefer transform/opacity; avoid frame-by-frame React state and naive scroll listeners. Clean up effects, observers, timelines, and triggers.
- CSS, Motion, or GSAP may coexist, but never let multiple engines control the same animated property on the same element.
- Preserve keyboard navigation, visible focus, semantic structure, alt text, and WCAG AA contrast. Test text and controls over photography, gradients, and both supported themes.
- Match the project's approved light/dark/auto mode. When both modes are in scope, use semantic tokens, respect system preference, and verify both. Do not invert unrelated sections accidentally.
- Reserve space for images, fonts, and embeds. Prioritize the hero asset and lazy-load heavier offscreen work. Aim for LCP <2.5s, INP <200ms, CLS <0.1; measurements, not intuition, establish those results.

## 5. Redesign protocol

First distinguish **preserve** from **overhaul**. If that choice is genuinely ambiguous, ask once before replacing the visual language.

For preserve: inspect current colors, type, logo, radii, navigation, conversion paths, content, accessibility, and SEO metadata. Retain recognizable assets and useful interaction patterns. Apply improvements in order, stopping when the brief is satisfied:

1. Typography.
2. Spacing and rhythm.
3. Palette consistency while preserving brand colors.
4. Motivated motion.
5. Hero/key-section recomposition.
6. Full block replacement only where necessary and approved.

For overhaul: new visuals may be in scope, but content and information architecture are still preserved unless explicitly approved otherwise.

Never silently change route slugs, anchor IDs, primary navigation labels, form field names/order, analytics events, logos/wordmarks, or legal/consent/cookie copy. Visual modernization is not a content rewrite or SEO migration.

## 6. Verify and report

For full builds, run the applicable [pre-flight checks](references/pre-flight.md). For small changes, use the relevant subset and inexpensive project checks.

Inspect the actual page at desktop and mobile widths, keyboard navigation, reduced motion, and supported themes using available tools. Run targeted lint/type/test checks where relevant. Measure Lighthouse/Core Web Vitals when the tooling and requested scope support it.

Report what was changed, the actual checks and their results, and remaining asset needs or blockers. If browser, measurement, or other tooling is unavailable, state **not run** rather than claiming visual or performance verification. Do not expand the task into unrelated redesign work to clear the checklist.
