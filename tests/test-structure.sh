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
check "skills/example/"
check "prompts/"
check "patterns/"
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

# Core files
check "skills/example/SKILL.md"
check "prompts/README.md"
check "patterns/README.md"

# Claude Code adapter
check "providers/claude-code/plugin.json"
check "providers/claude-code/marketplace.json"
check "providers/claude-code/agents/.gitkeep"
check "providers/claude-code/commands/.gitkeep"
check "providers/claude-code/hooks/hooks.json"
check "providers/claude-code/hooks/run-hook.cmd"
check "providers/claude-code/hooks/session-start"

# Provider stubs
check "providers/opencode/README.md"
check "providers/cursor/README.md"
check "providers/codex/README.md"

# Lib
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
