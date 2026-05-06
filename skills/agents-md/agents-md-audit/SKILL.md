---
name: agents-md-audit
description: Use when auditing a CLAUDE.md or AGENTS.md file. Scores six metrics (0-100), cites issues, suggests fixes. Codebase scan first, falls back to file-only when no codebase available.
disable-model-invocation: true
---

# Audit Agent Instruction Files

Audit a CLAUDE.md or AGENTS.md file. Score it 0-100 across six metrics, cite specific issues, suggest improvements. Each run is a standalone snapshot — user makes changes, re-runs for updated score.

**Input:** Path to target file. Default: `./CLAUDE.md`

**Scope rule:** Content belongs where its domain lives. A subdirectory CLAUDE.md owns domain-specific instructions (hooks, registries, patterns used in that directory). If root also documents the same thing, recommend **removing it from root entirely** — not shortening, not summarizing, removing. Never suggest removing domain-specific content from a subdirectory file or deferring to root.

**Debt rule:** CLAUDE.md sets the rules. Existing violations don't invalidate rules. Never suggest weakening a rule, adding debt counts ("121 instances are legacy"), or qualifying with "except for existing code." However, DO suggest warning agents away from prominent bad examples they'll encounter: "Legacy pages like X predate registries — don't copy that pattern." That's a gotcha, not a debt acknowledgement.

## Phase 1: Context Scan

Run before scoring. Build a mental model of what the directory actually does.

1. **Directory scan** — `find` the directory tree. Note file types, structure, entry points, configs.
2. **Parent CLAUDE.md scan** — read all CLAUDE.md/AGENTS.md files in parent directories up to repo root. These establish context the audited file should complement, not duplicate.
3. **Dependency trace** — grep for imports/requires referencing paths outside the directory. Map shared utilities.
4. **Code signals** — non-obvious patterns, complex configs, multiple entry points. For subdirectory files, also scan for `// HACK`, `// TODO`, `// FIXME`. For root files, skip file-level comments.
5. **Deep module detection** — identify shared abstractions: registries, contexts, factories, facades. Candidates for mandatory-use rules.
6. **Mental model** — what does this directory do? What would trip someone up? What deep modules must agents use and extend?

**File-only fallback:** No codebase available → skip this phase, score on textual quality only, note in output.

## Phase 2: Score Against Rubrics

Use the context scan as ground truth. See `${CLAUDE_SKILL_DIR}/references/best-practices.md` for detailed writing guidance.

### Signal-to-Noise (25 pts)

| Range | Descriptor |
|---|---|
| 21-25 | Every line prevents a mistake or saves significant exploration time. No catalogs, no type docs, no restating what code already says. |
| 14-20 | Mostly high-value. A few lines derivable from code. |
| 7-13 | Mixed — useful rules buried among file listings or generic descriptions. |
| 0-6 | Dominated by discoverable content — directory trees, component lists, type definitions. |

Cross-references between CLAUDE.md files ("see also `pages/CLAUDE.md`") are noise — agents discover them by directory traversal. Each file stands on its own. Never suggest adding cross-references. Flag existing ones for removal.

### Prescriptiveness (20 pts)

| Range | Descriptor |
|---|---|
| 17-20 | Commands: "use X not Y", "never do Z." Concrete wrong/right examples. Copy-paste ready. Deep modules enforced imperatively. |
| 11-16 | Mostly prescriptive. Some descriptive passages. Deep modules mentioned but not enforced. |
| 5-10 | Descriptive tone dominates — explains how things work rather than what to do. |
| 0-4 | Reads like documentation/tutorial. |

### Danger Coverage (20 pts)

| Range | Descriptor |
|---|---|
| 17-20 | Documents gotchas and "compiles but breaks" scenarios. Deep modules enforced as mandatory with "always/never" — both using and extending them. Decision framework for new code. Surfaces unmentioned abstractions from scan. |
| 11-16 | Some gotchas. Some deep modules mentioned but not all enforced. No decision framework. |
| 5-10 | Few warnings. Flat catalogs ("we have X service") rather than enforced patterns. |
| 0-4 | No gotchas, no pitfalls, no architectural enforcement. |

Deep modules: check that agents are told to **use** existing abstractions AND **extend** them (add to the registry/config, don't create parallel mechanisms). "Prefer" is too weak — "always/never" is the bar.

Self-maintenance (root files only): does the file tell agents to update CLAUDE.md when they encounter undocumented gotchas or patterns? A root CLAUDE.md that doesn't ask to be maintained will go stale.

### Structure & Organization (15 pts)

| Range | Descriptor |
|---|---|
| 13-15 | Clear hierarchy. Root covers project-wide, subdirectory files add scope-specific info. Scannable headers. |
| 8-12 | Reasonable. Minor issues — sections too long, slight overlap. |
| 4-7 | Flat wall of text or illogical grouping. |
| 0-3 | No structure. |

Flag root sections scoped to a subdirectory for extraction. Apply the scope rule (above) when evaluating duplication between root and subdirectory files.

**Position check:** Is this CLAUDE.md at the right level? Content about a specific subdirectory should be pushed down. Project-wide rules in a nested file should be pulled up to root. Content describing code that no longer lives here means the file is orphaned or misplaced.

### Conciseness (10 pts)

| Range | Descriptor |
|---|---|
| 9-10 | Dense. Every sentence carries weight. Rules lead, explanations follow briefly. |
| 6-8 | Mostly tight. A few verbose passages. |
| 3-5 | Wordy. Explanations longer than the rules they support. |
| 0-2 | Bloated. Could cut 50%+ without losing information. |

### Freshness (10 pts)

| Range | Descriptor |
|---|---|
| 9-10 | Everything reflects current state. No aspirational content, no stale references. Documented paths/commands verified to exist. |
| 6-8 | Mostly current. Minor drift. |
| 3-5 | Several aspirational or stale entries. |
| 0-2 | Significantly out of date. |

## Phase 3: Output

~~~
## Audit: <path/to/file>

**Total: <N>/100** — <One-sentence verdict.>

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
- <Line N or file path>: <issue> — <concrete fix.>

Re-run to check updated score.
~~~

Cite line numbers for .md issues, file paths for codebase findings. Group by metric, skip metrics with no suggestions. Every suggestion must be actionable.
