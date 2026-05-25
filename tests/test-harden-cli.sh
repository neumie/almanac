#!/usr/bin/env bash
# test-harden-cli.sh - Harden CLI bootstrap behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC="$ROOT/bin/almanac"

TMPDIRS=()
NEW_TMPDIR=""

cleanup() {
  local dir
  [ "${#TMPDIRS[@]}" -eq 0 ] && return 0
  for dir in "${TMPDIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

test_creates_draft_rubric_for_target_and_goal() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/lib"
  touch "$tmp/lib/loop-core.sh"

  (cd "$tmp" && "$ALMANAC" harden lib/loop-core.sh --goal "prove feedback detection cannot regress" >/dev/null)

  rubric="$tmp/docs/plans/harden/lib-loop-core-sh/rubric.md"
  [ -f "$rubric" ] || fail "harden should create default rubric path"
  assert_file_contains "$rubric" "# Harden Rubric" "rubric should have title"
  assert_file_contains "$rubric" "Target: lib/loop-core.sh" "rubric should record target"
  assert_file_contains "$rubric" "prove feedback detection cannot regress" "rubric should record goal"
  assert_file_contains "$rubric" "## Acceptance" "rubric should include acceptance section"
  assert_file_contains "$rubric" "## Context" "rubric should include context section"
  echo "  PASS: creates draft rubric for target and goal"
}

test_requires_goal() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  if (cd "$tmp" && "$ALMANAC" harden lib/loop-core.sh >/dev/null 2>&1); then
    fail "harden should reject missing goal"
  fi
  echo "  PASS: requires goal"
}

test_refuses_to_overwrite_existing_rubric() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock behavior" >/dev/null)
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  printf '%s\n' "DO NOT OVERWRITE" >> "$rubric"

  if (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock behavior" >/dev/null 2>&1); then
    fail "harden should refuse existing rubric"
  fi
  assert_file_contains "$rubric" "DO NOT OVERWRITE" "existing rubric should not be overwritten"
  echo "  PASS: refuses to overwrite existing rubric"
}

echo "=== Harden CLI Tests ==="
test_creates_draft_rubric_for_target_and_goal
test_requires_goal
test_refuses_to_overwrite_existing_rubric
