---
title: SKILL.md + docs sync (README, ARCHITECTURE, CONTRIBUTING)
status: open
type: AFK
blocked-by: [06-hub-integration-and-watch-controls]
user-stories: [17]
---

## What to build

Author the user-facing `skills/loop/converge-loop/SKILL.md` describing the loop, its CLI surface, the overseer contract, and worked examples. Update repo-level docs (README, ARCHITECTURE, CONTRIBUTING) per the doc-sync rule in `CLAUDE.md`. This is the **last** slice intentionally — by now the implementation, tests, and CLI surface are stable, so the docs can be written once against the final shape.

## Acceptance criteria

- [ ] `skills/loop/converge-loop/SKILL.md` created with frontmatter:
  - [ ] `name: converge-loop`
  - [ ] `description:` starts with "Use when" (per `CLAUDE.md` skill-format rule), names the trigger explicitly, under 220 chars
  - [ ] `disable-model-invocation: true` (matches harden-loop / ralph-loop — these are user-invoked loops, not auto-fired skills)
  - [ ] `metadata.source` notes that this is a new pattern (no upstream SHA to sync)
- [ ] SKILL.md body covers:
  - [ ] The convergence-loop concept (single exec per round, overseer judges, goal mutates)
  - [ ] Full CLI surface with worked examples (the `/almanac:codebase-improve` until convergence example is the canonical demo)
  - [ ] State layout (`docs/plans/converge/<slug>/` file tree with one-line descriptions)
  - [ ] Overseer 4-field contract (VERDICT/REASON/STEER/GOAL_UPDATE) with examples
  - [ ] Role config table (`CONVERGE_AGENT_*` / `CONVERGE_OVERSEER_*` env)
  - [ ] When to use this vs ralph (PRD-driven) vs harden (lens-fanout)
  - [ ] gum-degrade note (reuse harden's wording)
  - [ ] Body under 500 lines (per CLAUDE.md); move overflow detail to `references/`
- [ ] `README.md` updated:
  - [ ] Skills table includes converge-loop row
  - [ ] Structure diagram references the new files (`cmd/converge.sh`, `lib/converge-core.sh`, `lib/loops/converge.sh`, `skills/loop/converge-loop/`)
  - [ ] If there's a "sync example" or quickstart, add a converge example alongside the ralph/harden ones
- [ ] `docs/ARCHITECTURE.md` updated:
  - [ ] Converge listed alongside ralph and harden as a loop consumer of the shared engine
  - [ ] The new modules slot into the module-map table (`lib/converge-core.sh`, `lib/loops/converge.sh`)
- [ ] `docs/CONTRIBUTING.md` updated:
  - [ ] Any contributor-facing rules touched (e.g. if `lib/role.sh` gained a `converge` consumer in slice 03, document that contributors should mirror it when adding their own consumers)
- [ ] `tests/test-structure.sh` passes (validates skill dir + required files)
- [ ] `tests/test-skills.sh` passes (validates frontmatter format, description length, the "Use when" prefix rule)
- [ ] Full test suite stays green: every `tests/test-*.sh` exits 0.
- [ ] `bash tests/test-structure.sh` confirms 30 skills found (one more than before).

## Notes

- This slice has **no implementation code** — it's pure docs. The implementation surface is locked by slice 06.
- The doc-sync rule (`CLAUDE.md` → Doc Sync section) is enforced socially, not by tests. Read it first; the four files it lists (README, ARCHITECTURE, CONTRIBUTING, plus the skills table) MUST be touched in the same commit.
- The SKILL.md must NOT print `${CLAUDE_SKILL_DIR}/scripts/...` paths in user-facing instructions — use absolute `~/.claude/skills/almanac/converge-loop/scripts/...` (per CLAUDE.md skill-resources rule). If converge-loop ends up needing no scripts directory (likely — the CLI is `bin/almanac`-mediated), skip the scripts section entirely.
- Mirror harden-loop's SKILL.md structure for consistency; resist the urge to invent a new layout for a sibling loop.
- The `description:` field is what shows in the global skills listing loaded into every Claude session — keep it tight, stating the trigger once. Avoid restating "use when X, Y, or Z" — pick the strongest single trigger.
