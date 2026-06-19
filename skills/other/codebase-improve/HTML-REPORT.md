# HTML Report Format

Render architecture reviews as one self-contained HTML file in the OS temp directory. Tailwind and Mermaid both come from CDNs. Mermaid handles graph-shaped diagrams reliably; hand-built divs and inline SVG handle mass diagrams, cross-sections, and collapse diagrams. Mix both.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture review - {{repo name}}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: #dc2626; }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, date, and compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. No intro paragraph. Go straight to candidates.

## Candidate Card

Diagrams carry the weight. Prose stays sparse and uses `LANGUAGE.md` terms.

Each candidate is one `<article>`:

- **Title**: short name for the deepening.
- **Badge row**: recommendation strength (`Strong`, `Worth exploring`, `Speculative`) plus dependency category when useful.
- **Files**: monospaced list.
- **Before / After diagram**: center of the card, two columns.
- **Problem**: one sentence.
- **Solution**: one sentence.
- **Wins**: bullets, six words or fewer when possible.
- **ADR callout**: one amber-tinted line if relevant.

No paragraphs of explanation. If a diagram needs a paragraph, redraw it.

## Diagram Patterns

### Mermaid Graph

Use Mermaid `flowchart`, `graph`, or sequence diagrams for dependency and call-flow shape.

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrderHandler] --> B[OrderValidator]
      B --> C[OrderRepo]
      C -.leak.-> D[PricingClient]
      classDef leak stroke:#dc2626,stroke-width:2px;
      class C,D leak
  </pre>
</div>
```

### Hand-Built Boxes And Arrows

Use positioned `<div>` modules plus inline SVG arrows when Mermaid layout fights the point. Good for showing one thick deep module with faded internals.

### Cross-Section

Stack horizontal bands to show layered shallowness. Before: many thin pass-through layers. After: one thick band labelled with the consolidated responsibility.

### Mass Diagram

Show interface size vs implementation size. Before: interface rectangle nearly matches implementation height. After: interface shrinks and implementation absorbs complexity.

### Call-Graph Collapse

Before: nested function-call tree. After: same tree collapsed into one module, with internal calls faded inside it.

## Style

- Editorial, not dashboard.
- Generous whitespace.
- One accent color plus red for leakage and amber for warnings.
- Diagrams around 320px tall so before/after fits side by side.
- `text-xs uppercase tracking-wider` for schematic module labels.
- Only Tailwind CDN and Mermaid ESM scripts. No app code.

## Top Recommendation

One larger card: candidate name, one sentence on why, anchor link to the candidate card.

## Tone

Use exactly: module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.

Avoid substitutes: component, service, unit, API, signature, boundary.

Good phrasing:

- "Order intake module is shallow: interface nearly matches implementation."
- "Pricing leaks across the seam."
- "Deepen: one interface, one place to test."
- "Two adapters justify the seam: HTTP in prod, in-memory in tests."

Wins bullets should name glossary gains: `locality: bugs concentrate in one module`, `leverage: one interface, N call sites`, `interface shrinks; implementation absorbs wrappers`.
