---
name: agents-md-audit
description: Use when auditing a CLAUDE.md or AGENTS.md file for quality. Scores the file on six metrics (0-100 total), cites specific issues, and suggests improvements. Runs a codebase context scan first, falls back to file-only when no codebase is available.
---

# Audit Agent Instruction Files

Audit a CLAUDE.md or AGENTS.md file. Score it 0-100 across six metrics, cite specific issues, suggest improvements. Each run is a standalone snapshot — user makes changes, re-runs for updated score.

**Input:** Path to target file. Default: `./CLAUDE.md`

## Phase 1: Context Scan

Run before scoring. Build a mental model of what the directory actually does.

1. **Directory scan** — `find` the directory tree where the .md lives. Note file types, structure, entry points, configs.
2. **Dependency trace** — grep for imports/requires/includes that reference paths outside the directory. Map shared utilities, cross-package dependencies.
3. **Code signals** — scan for non-obvious patterns (complex configs, unusual file conventions, multiple entry points). For subdirectory CLAUDE.md files, also scan for `// HACK`, `// TODO`, `// FIXME`, `// WORKAROUND` in that directory's code. For root CLAUDE.md files, skip file-level code comments — they don't belong at project-wide scope.
4. **Deep module detection** — identify patterns that look like shared abstractions: registries, contexts, factories, facades. These are candidates for mandatory-use rules in the CLAUDE.md.
5. **Build mental model** — what does this directory do? What would trip someone up? What external dependencies would surprise someone? What deep modules exist that agents must use?

**File-only fallback:** If no codebase is available (e.g., user pastes content), skip this phase. Score only on textual quality. Note in output that codebase-aware checks were skipped.

## Phase 2: Score Against Rubrics

Score each metric using the rubrics below. Use the context scan as ground truth.

### Signal-to-Noise (25 pts)

Does every line earn its place by preventing a mistake or saving significant exploration time?

| Range | Descriptor |
|---|---|
| 21-25 | Every line prevents a mistake or saves significant exploration time. No catalogs, no type docs, no restating what code already says. |
| 14-20 | Mostly high-value content. A few lines that an agent could derive from code, but nothing egregious. |
| 7-13 | Mixed — useful rules buried among file listings, hook catalogs, or generic descriptions. |
| 0-6 | Dominated by discoverable content — directory trees, component lists, type definitions. |

Penalize: file/directory listings, export catalogs, type definitions, things documented in code comments, generic best practices ("use TypeScript", "follow SOLID").

### Prescriptiveness (20 pts)

Are instructions commands, not descriptions?

| Range | Descriptor |
|---|---|
| 17-20 | Instructions are commands: "use X not Y", "never do Z", "always check W first." Concrete wrong/right examples for gotchas. Commands copy-paste ready. Deep modules enforced with imperative language ("Always use the column registry. Never create inline columns."). |
| 11-16 | Mostly prescriptive. Some descriptive passages that could be rewritten as rules. Deep modules mentioned but not strongly enforced. |
| 5-10 | Descriptive tone dominates — explains how things work rather than what to do. |
| 0-4 | Reads like documentation/tutorial, not instructions. |

Penalize: "X provides Y functionality" instead of "Always use X for Y." Weak enforcement of existing abstractions ("prefer" instead of "always/never"). Prose explanations instead of runnable code blocks.

### Danger Coverage (20 pts)

Does it document the things that actually prevent mistakes?

| Range | Descriptor |
|---|---|
| 17-20 | Documents gotchas, pitfalls, "compiles but breaks" scenarios. Existing deep modules (registries, contexts, shared utilities) documented as mandatory with "always/never" language. Includes decision framework for new code: check existing modules first, consider reuse potential, design interface before implementation. In codebase mode: surfaces unmentioned shared abstractions found in the scan. |
| 11-16 | Some gotchas documented. Some deep modules mentioned but not all enforced. No decision framework for new code. |
| 5-10 | Few warnings. Architecture described as flat catalogs ("we have X service") rather than enforced patterns. |
| 0-4 | No gotchas, no pitfalls, no architectural enforcement. |

**Deep modules enforcement** — the most important part of danger coverage:

- Are existing deep modules documented as mandatory? Not "we have a column registry" but "Always use the column registry. Never create inline DataGridColumn components." The codebase scan identifies shared abstractions; the audit checks whether the file directs agents to use them.
- Does it tell agents to **extend** deep modules, not just use them? A global config, registry, or context should be the place agents add new entries when they have a similar use case — not create a parallel mechanism. Example: "If you need new shared metadata, add it to GlobalConfig. Don't create a separate query."
- Is enforcement language strong enough? "Prefer using..." is weak — agents rationalize around it. "Always use... never..." is strong.
- Is there a decision framework for new code? Before creating a new utility, check if an existing module covers the use case. If creating new: will this have multiple callers? If yes, design the interface first. If no, a simple solution is fine.

**Architecture depth:** When the file describes architecture, does it convey depth — small interface hiding complex implementation, real seams? Or just list components flat? Does the reader understand what's hidden behind each module's interface and why they must use it?

### Structure & Organization (15 pts)

Is the file well-organized and scannable?

| Range | Descriptor |
|---|---|
| 13-15 | Clear hierarchy. Root file covers project-wide concerns. Subdirectory files (if any) add new scope-specific info without duplicating root. Sections scannable with headers. |
| 8-12 | Reasonable structure. Minor issues — some sections too long, slight overlap between root and subdirectory files. |
| 4-7 | Flat wall of text, or sections that don't group logically. Hard to scan. |
| 0-3 | No structure. Stream of consciousness. |

Check: header hierarchy, line count (<400 for root), logical grouping. **Flag sections scoped to a specific subdirectory for extraction** — the root file should stay project-wide. Suggest concrete subdirectory CLAUDE.md files with target paths.

### Conciseness (10 pts)

Is every sentence carrying weight?

| Range | Descriptor |
|---|---|
| 9-10 | Dense. Every sentence carries weight. Rules lead, explanations follow briefly. No filler. |
| 6-8 | Mostly tight. A few verbose passages that could be compressed. |
| 3-5 | Wordy. Explanations longer than the rules they support. Redundant phrasing. |
| 0-2 | Bloated. Could be cut by 50%+ without losing information. |

### Freshness (10 pts)

Does it reflect the current state of the codebase?

| Range | Descriptor |
|---|---|
| 9-10 | Everything reflects current state. No aspirational content, no TODOs, no stale references. In codebase mode: documented commands/files verified to exist. |
| 6-8 | Mostly current. Minor signs of drift — a reference that might be outdated. |
| 3-5 | Several aspirational or potentially stale entries. "We plan to..." or references to things that may have changed. |
| 0-2 | Significantly out of date. Documents how things should work, not how they do. |

Codebase-aware checks: verify referenced file paths exist, verify documented commands are in package.json/Makefile, flag stale references.

## Phase 3: Output

Print the scorecard and suggestions. Use this exact format:

~~~
## Audit: <path/to/file>

**Total: <N>/100** — <One-sentence verdict summarizing strengths and key gaps.>

| Metric              | Score |
|---------------------|-------|
| Signal-to-noise     | __/25 |
| Prescriptiveness    | __/20 |
| Danger coverage     | __/20 |
| Structure           | __/15 |
| Conciseness         | __/10 |
| Freshness           | __/10 |

## Suggestions

### <Metric name>
- <Line reference or file path>: <specific issue> — <concrete fix.>

Re-run to check updated score.
~~~

**Suggestion rules:**
- Cite line numbers when referencing the .md file
- Cite file paths when referencing codebase findings
- Group by metric, skip metrics with no suggestions
- Each suggestion must be actionable — say what to do, not just what's wrong
- For structure suggestions that recommend extraction, name the target subdirectory path

## Best Practices Reference

For detailed guidance on what belongs in a CLAUDE.md, what doesn't, writing style rules, and anti-patterns, see `${CLAUDE_SKILL_DIR}/references/best-practices.md`.
