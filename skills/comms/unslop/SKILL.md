---
name: unslop
description: Use when prose sounds AI-generated or robotic and needs an audit, minimal cleanup, fact-preserving rewrite, or reconstruction in a taught human voice.
license: MIT
compatibility: Requires Python 3.10 or newer; runtime scripts use only the standard library.
metadata:
  author: claytonkim
  version: "2.3.0"
  upstream: theclaymethod/unslop
  upstream-sha: 97c9efd65e44fefb3c3beb9d5839ac1d215c5834
  adapted-date: "2026-08-19"
---

# Unslop

Humanize prose without flattening its facts, register, or voice. Audit first. Rewrite only when the user asks for a rewrite.

For every audit or rewrite, read [references/core-contract.md](references/core-contract.md). It is the authoritative behavior contract.

## Resource root

Before running a bundled script, set `UNSLOP_DIR` to this skill's installed directory and keep the caller's working directory unchanged:

```bash
# Pi and Codex
UNSLOP_DIR="$HOME/.agents/skills/almanac/unslop"

# Claude Code
UNSLOP_DIR="$HOME/.claude/skills/almanac/unslop"
```

Use the root for every bundled command, for example:

```bash
python3 "$UNSLOP_DIR/scripts/banned_phrase_scan.py" <<< "$INPUT"
```

Never resolve resources through the single-file commands symlink.

## Routing

When the user invokes or clearly requests a flow, read its command file before acting. A bare request to “unslop,” humanize, or fix AI-sounding text defaults to `rewrite`.

| Flow | Purpose | File |
| ------ | --------- | ------ |
| `rewrite` | Diagnose, minimally reconstruct confirmed defects, then validate. | [references/commands/rewrite.md](references/commands/rewrite.md) |
| `cleanup` | Audit only or produce reviewable suggestions without silently applying them. | [references/commands/cleanup.md](references/commands/cleanup.md) |
| `teach` | Harvest approved writing samples and build a reusable voice card. | [references/commands/teach.md](references/commands/teach.md) |
| `mimic` | Draft or rewrite in a taught voice, then clear every removal gate. | [references/commands/mimic.md](references/commands/mimic.md) |

Route “audit,” “review,” “just flag it,” or “do not change anything” to cleanup's report-only flow. Route “write like me,” “match my voice,” or “does this sound like me?” to mimic. Route “learn my voice” or offered writing samples to teach.

## Options

| Option | Meaning | Default |
| -------- | --------- | --------- |
| `--preset` | Bundled voice delta: `crisp`, `warm`, `expert`, or `story`. | `crisp` |
| `--strict` | Require at least 32/40 on the rubric and report validation. | false |
| `--report` | Flag patterns without changing the text. | false |
| Input | Text supplied inline, by file path, or on stdin. | required |

Read exactly one preset before writing:

| Preset | File | Best for |
| -------- | ------ | ---------- |
| `crisp` | [presets/crisp-human.md](presets/crisp-human.md) | Technical writing and documentation. |
| `warm` | [presets/warm-human.md](presets/warm-human.md) | Emails and conversational posts. |
| `expert` | [presets/expert-human.md](presets/expert-human.md) | Articles and authoritative analysis. |
| `story` | [presets/story-lean.md](presets/story-lean.md) | Case studies and personal narratives. |

Presets change delivery only. They cannot authorize a finding or override preservation rules.

## Voice data

Teach and mimic store project-local voice artifacts under `.unslop/voice/<name>/`. Do not commit samples or profiles unless the user explicitly requests it; respect the project's ignore and privacy rules.

## Output

For a quick rewrite, return only the cleaned text. For report-only cleanup, return:

```markdown
## Issues Found

- [Quoted span, category, severity, and contextual reason]

## Assessment

- [Clear problems]
- [Register-dependent judgment calls or protected matches]
```

For strict mode or requested analysis, return:

```markdown
## Transformed Text

[The humanized version]

## Validation

- Constraints: [X]/[Y] preserved
- AI patterns: [N] remaining (was [M])
- Structure: [pass/fail]
- Readability: Grade [X], sentence variance [Y]
- Change: [X]% from original
- Score: [X]/40
```

## Supporting references

- [references/fact-preservation.md](references/fact-preservation.md) — preservation rules and edge cases.
- [references/taboo-phrases.md](references/taboo-phrases.md) — authoritative phrase and structure catalog.
- [references/rewrite-examples.md](references/rewrite-examples.md) and [references/edit-library.md](references/edit-library.md) — before/after patterns.
- [references/rubric.md](references/rubric.md) — strict scoring.
- [references/harvest.md](references/harvest.md), [references/mimic.md](references/mimic.md), and [references/calibrate.md](references/calibrate.md) — voice tooling internals.

This Almanac adaptation vendors runtime flows only. Pattern maintenance, benchmark evaluation, and upstream contributions remain in [theclaymethod/unslop](https://github.com/theclaymethod/unslop).
