#!/usr/bin/env bash
# test-structure.sh — Validates that all required directories and files exist

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/almanac-core.sh"
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

# Core directories
check "skills/"
check "providers/"
check "lib/"
check "tests/"
check "docs/"
check "cmd/"
check "bin/"

# CLI
check "bin/almanac"
check "cmd/install.sh"
check "cmd/uninstall.sh"
check "cmd/update.sh"
check "cmd/list.sh"
check "cmd/ralph.sh"
check "cmd/harden.sh"
check "cmd/hub.sh"
check "cmd/doctor.sh"
check "cmd/help.sh"
check "cmd/sync.sh"
check "install.sh"
check "skills/loop/ralph-loop/scripts/prompt.sh"
check "skills/loop/ralph-loop/scripts/ralph-run-registry.sh"

# Lib
check "lib/core.sh"
check "lib/almanac-core.sh"
check "lib/ui.sh"
check "lib/loop-core.sh"
check "lib/loop-launcher.sh"
check "lib/harden-core.sh"

# Claude Code adapter
check "providers/claude-code/.claude-plugin/plugin.json"
check "providers/claude-code/hooks/session-start"

# Provider stubs
check "providers/opencode/README.md"
check "providers/cursor/README.md"
check "providers/codex/README.md"

# Tests
check "tests/test-structure.sh"
check "tests/test-skills.sh"
check "tests/test-ui.sh"
check "tests/test-loop-core.sh"
check "tests/test-home-resolve.sh"
check "tests/test-ralph-prompt.sh"
check "tests/test-ralph-run-registry.sh"
check "tests/test-ralph-smoke.sh"
check "tests/test-harden-cli.sh"
check "tests/test-hub.sh"

# Docs
check "docs/ARCHITECTURE.md"
check "docs/CONTRIBUTING.md"

# Root files
check "CLAUDE.md"
check "README.md"
check "LICENSE"
check ".gitignore"

# Skills — dynamically check that every skill dir has a SKILL.md.
# Tree layout: skills/<category>/<name>/SKILL.md
echo ""
echo "=== Skill Tests ==="
skill_count=0
while IFS= read -r skill_dir; do
  [ -d "$skill_dir" ] || continue
  rel="${skill_dir#$ROOT/}"
  rel="${rel%/}"
  check "$rel/SKILL.md"
  skill_count=$((skill_count + 1))
done < <(almanac_list_skills)

if [ "$skill_count" -eq 0 ]; then
  echo "  FAIL: no skills found"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed ($skill_count skills found)"

[ "$FAIL" -eq 0 ] || exit 1
