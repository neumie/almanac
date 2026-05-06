---
name: agents-md-map
description: Use when mapping where CLAUDE.md or AGENTS.md files should exist. Scans for non-obvious complexity, evaluates existing files, identifies gaps. Run before agents-md-audit on each flagged file.
disable-model-invocation: true
---

# Map Agent Instruction Files

Scan the entire project to determine where CLAUDE.md/AGENTS.md files should exist. Evaluate existing ones, find gaps, flag misplaced files. Based on actual code analysis — not guessing.

**Input:** Project root path. Default: `.`

**File convention:** Each location should have AGENTS.md as the actual file and CLAUDE.md as a symlink to it (`ln -s AGENTS.md CLAUDE.md`). AGENTS.md is the standard-agnostic name; the symlink ensures Claude Code discovers it. Flag locations that only have one or the other.

## Phase 1: Deep Scan

Walk the directory tree from root. Skip `.gitignore`d paths, `node_modules`, `.git`, build output, vendored deps, test fixtures.

For each directory with code, analyze:

1. **Deep modules** — shared abstractions: registries, factories, contexts, facades, repositories. Strongest signal — agents create shallow alternatives if not told to use them.
2. **Gotcha density** — `// HACK`, `// TODO`, `// WORKAROUND`, unusual conventions, patterns where the obvious approach fails.
3. **Cross-boundary dependencies** — imports/exports connecting this directory to others in non-obvious ways.
4. **Scope boundaries** — does this directory have its own domain distinct from parent? Different patterns, rules, abstractions?
5. **Existing CLAUDE.md/AGENTS.md** — read them, note what they cover.

## Phase 2: Evaluate

For each directory, produce a verdict.

**Strong signals (one is enough):**
- Deep modules that agents must use and extend
- "Compiles but breaks" gotchas
- Non-standard workflows
- Cross-boundary integration patterns

**Weak signals (need 2+ together):**
- Multiple entry points or complex config
- High HACK/TODO density
- Framework patterns differing from the obvious approach
- External dependency gotchas

**Anti-signals (argue against):**
- Directory has < 3 files
- All files follow obvious, consistent patterns
- Everything documented in code comments or README
- Leaf directory with no shared abstractions

Root always needs a CLAUDE.md. Subdirectories judged by these criteria.

**Verdicts:**
- **Needs CLAUDE.md** — enough non-obvious complexity that agents would make mistakes without guidance
- **Has, keep** — file exists and is justified
- **Has, delete** — content is discoverable, redundant, or directory too simple
- **Has, move** — file at wrong level (content belongs deeper or higher)

Every verdict must cite specific signals found in the code.

## Phase 3: Output

```
## Agent Instructions Map

**Project:** <repo name>
**Scanned:** <N> directories, <M> with code

### Existing files

| Path | Verdict | Reason |
|------|---------|--------|
| ./CLAUDE.md | ✅ keep | <reason citing signals> |
| ./lib/utils/CLAUDE.md | ❌ delete | <reason citing anti-signals> |
| ./src/auth/CLAUDE.md | ➡️ move to ./src/ | <reason citing scope mismatch> |

### Missing files

| Path | Why needed | Key content to document |
|------|-----------|------------------------|
| <path> | <signal found — what agents will get wrong> | <what to document> |

### No action needed

<N> directories scanned, no CLAUDE.md needed — patterns obvious or discoverable.

Run `agents-md-audit` on each file to score quality and get improvement suggestions.
```

After printing the map, if any locations are missing the AGENTS.md + CLAUDE.md symlink pair, list them and ask: "Want me to fix the symlink setup for these locations?" If yes, create the missing symlinks (`ln -s AGENTS.md CLAUDE.md`) or rename CLAUDE.md to AGENTS.md and create the symlink.
