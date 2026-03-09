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

# === Negative validation tests (must reject invalid skills) ===
echo ""
echo "=== Validation Negative Tests ==="

NEG_PASS=0
NEG_FAIL=0

neg_test() {
  local test_name="$1"
  local dir_name="$2"
  local content="$3"

  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/$dir_name"
  echo "$content" > "$tmpdir/$dir_name/SKILL.md"

  if almanac_validate_skill "$tmpdir/$dir_name" 2>/dev/null; then
    echo "  FAIL: $test_name (should have been rejected)"
    NEG_FAIL=$((NEG_FAIL + 1))
  else
    echo "  PASS: $test_name (correctly rejected)"
    NEG_PASS=$((NEG_PASS + 1))
  fi
  rm -rf "$tmpdir"
}

neg_test "uppercase name" "Bad-Name" "---
name: Bad-Name
description: Use when testing
---"

neg_test "consecutive hyphens" "bad--name" "---
name: bad--name
description: Use when testing
---"

neg_test "name-directory mismatch" "wrong-dir" "---
name: different-name
description: Use when testing
---"

neg_test "leading hyphen" "-leading" "---
name: -leading
description: Use when testing
---"

neg_test "missing description" "no-desc" "---
name: no-desc
---"

neg_test "missing name" "no-name" "---
description: Use when testing
---"

echo ""
echo "Negative results: $NEG_PASS passed, $NEG_FAIL failed"

[ "$NEG_FAIL" -eq 0 ] || exit 1
