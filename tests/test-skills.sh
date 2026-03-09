#!/usr/bin/env bash
# test-skills.sh — Validates that all skills have valid SKILL.md with frontmatter

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/almanac-core.sh"

PASS=0
FAIL=0

echo "=== Skill Format Tests ==="

for skill_dir in "$ROOT"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")

  if almanac_validate_skill "$skill_dir"; then
    echo "  PASS: $skill_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $skill_name"
    FAIL=$((FAIL + 1))
  fi
done

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
  echo "  No skills found"
  exit 1
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
