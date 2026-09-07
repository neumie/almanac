---
name: codebase-improve
description: Use when finding architectural friction in a codebase. Surfaces shallow modules, proposes refactors for testability/AI-navigability, grills the design. Uses CONTEXT.md + ADRs.
metadata:
  dependencies:
    - codebase-design
    - domain-model
    - grilling
  upstream: mattpocock/skills/skills/engineering/improve-codebase-architecture
  upstream-sha: a578dd0a34ad0a8886abe7e7642b100106ba86d6
  adapted-date: "2026-09-07"
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

Follow the `codebase-design` skill for design vocabulary and principles. Follow the `domain-model` skill when maintaining `CONTEXT.md` or ADRs.

## Process

### 1. Explore

Scope the scan before exploring. Deepening pays off when future changes land in that area, so avoid speculative whole-repo review:

- If the user names a module, subsystem, or pain point, focus there.
- Otherwise inspect a useful stretch of `git log --oneline` for recurring files and areas. Start with those hot spots; widen only when history is scattered.

Read `CONTEXT.md` if present and use its vocabulary throughout. Read relevant ADRs under `docs/adr/` before exploring.

Then use a read-only exploration sub-agent to walk the scoped codebase when available; otherwise explore directly. Don't follow rigid heuristics; note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the repo. Resolve the temp dir from `$TMPDIR`, falling back to `/tmp` (or `%TEMP%` on Windows), and write to `<tmpdir>/architecture-review-<timestamp>.html` so each run gets a fresh file. Open it for the user — `xdg-open <path>` on Linux, `open <path>` on macOS, `start <path>` on Windows — and tell them the absolute path.

The report uses Tailwind via CDN for layout and Mermaid via CDN for diagrams where a graph, flow, or sequence reliably communicates the structure. Mix Mermaid with hand-crafted CSS/SVG visuals: use Mermaid when relationships are graph-shaped, and hand-built divs/SVG for mass diagrams, cross-sections, and collapse diagrams. Each candidate gets a before/after visualization.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram patterns, and styling guidance.

For each candidate, render a card with:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture is causing friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and also in how tests would improve
- **Before / After diagram** — side-by-side, custom-drawn, illustrating the shallowness and the deepening
- **Recommendation strength** — one of `Strong`, `Worth exploring`, `Speculative`, rendered as a badge

End the report with a Top recommendation section: which candidate you'd tackle first and why.

**Use CONTEXT.md vocabulary for the domain, and `codebase-design` vocabulary for architecture.**

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly (e.g. _"contradicts ADR-0007 — but worth reopening because…"_).

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, follow the `grilling` skill to resolve constraints, dependencies, the shape of the deepened module, what sits behind the seam, and which tests survive.

Follow the `domain-model` skill as naming and design decisions crystallize; it owns glossary updates and ADR eligibility. For a rejected candidate, offer an ADR only when the reason is load-bearing for future explorers, not merely "not worth it right now."

To explore alternative interfaces, follow the `codebase-design` skill and its design-it-twice reference.
