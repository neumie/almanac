#!/usr/bin/env bash
# test-structure.sh — Validates that all required directories and files exist

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() {
  if [ -e "$ROOT/$1" ]; then
    echo "  PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Structure Tests ==="

# Directories
check "skills/"
check "providers/claude-code/"
check "providers/claude-code/agents/"
check "providers/claude-code/commands/"
check "providers/claude-code/hooks/"
check "providers/opencode/"
check "providers/cursor/"
check "providers/codex/"
check "lib/"
check "tests/"
check "docs/"

# Skills
check "skills/catalog/SKILL.md"
check "skills/tdd/SKILL.md"
check "skills/debugging/SKILL.md"
check "skills/code-review/SKILL.md"
check "skills/planning/SKILL.md"
check "skills/frontend-design/SKILL.md"
check "skills/mcp-builder/SKILL.md"
check "skills/mcp-builder/references/"
check "skills/webapp-testing/SKILL.md"
check "skills/webapp-testing/scripts/"
check "skills/skill-creator/SKILL.md"
check "skills/skill-creator/references/"
check "skills/skill-creator/references/progressive-disclosure.md"
check "skills/git-workflow/SKILL.md"
check "skills/git-workflow/references/"
check "skills/git-workflow/references/commit-format.md"
check "skills/git-workflow/references/safety-guardrails.md"
check "skills/refactoring/SKILL.md"
check "skills/planning/references/"
check "skills/planning/references/task-template.md"
check "skills/planning/references/architect-role.md"
check "skills/planning/references/vertical-slice.md"
check "skills/debugging/references/"
check "skills/debugging/references/session-template.md"
check "skills/frontend-perf/SKILL.md"
check "skills/frontend-perf/references/"
check "skills/frontend-perf/references/lighthouse-guide.md"
check "skills/frontend-perf/references/bundle-analysis-guide.md"
check "skills/backend-perf/SKILL.md"
check "skills/backend-perf/references/"
check "skills/backend-perf/references/database-analysis-guide.md"
check "skills/backend-perf/references/caching-patterns.md"

# CLI
check "bin/almanac"
check "cmd/install.sh"
check "cmd/uninstall.sh"
check "cmd/update.sh"
check "cmd/list.sh"
check "cmd/help.sh"
check "cmd/sync.sh"
check "install.sh"

# Claude Code adapter
check "providers/claude-code/.claude-plugin/plugin.json"
check "providers/claude-code/agents/.gitkeep"
check "providers/claude-code/commands/review.md"
check "providers/claude-code/commands/plan.md"
check "providers/claude-code/commands/commit.md"
check "providers/claude-code/hooks/session-start"

# Provider stubs
check "providers/opencode/README.md"
check "providers/cursor/README.md"
check "providers/codex/README.md"

# Lib
check "lib/core.sh"
check "lib/almanac-core.sh"

# Tests
check "tests/test-structure.sh"
check "tests/test-skills.sh"

# Docs
check "docs/ARCHITECTURE.md"
check "docs/CONTRIBUTING.md"

# Root files
check "CLAUDE.md"
check "README.md"
check "LICENSE"
check ".gitignore"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
