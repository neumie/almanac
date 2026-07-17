#!/usr/bin/env bash
# test-install.sh - provider install regressions

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

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message" ;;
  esac
}

new_tmpdir() {
  NEW_TMPDIR="$(mktemp -d)"
  TMPDIRS+=("$NEW_TMPDIR")
}

skill_count() {
  find "$ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md -print | wc -l | tr -d ' '
}

test_pi_install_links_every_skill() {
  local tmp home skills_dir expected actual output target
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  mkdir -p "$home"

  output="$(HOME="$home" "$ALMANAC" install pi 2>&1)"
  expected="$(skill_count)"
  actual="$(find "$skills_dir" -mindepth 1 -maxdepth 1 -type l -print | wc -l | tr -d ' ')"

  [ "$actual" -eq "$expected" ] || fail "Pi install must link every skill ($actual != $expected)"
  for target in "$skills_dir"/*; do
    [ -f "$target/SKILL.md" ] || fail "Pi skill link must resolve to SKILL.md: $target"
  done
  assert_contains "$output" "/skill:<name>" "Pi install must show Pi skill command syntax"
  assert_contains "$output" "/reload" "Pi install must explain how to reload skills"
  echo "  PASS: Pi install links every skill with Pi reload guidance"
}

test_pi_install_migrates_legacy_directory_link() {
  local tmp home skills_dir
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  mkdir -p "$(dirname "$skills_dir")"
  ln -s "$ROOT/skills" "$skills_dir"

  HOME="$home" "$ALMANAC" install pi >/dev/null

  [ -d "$skills_dir" ] && [ ! -L "$skills_dir" ] || \
    fail "Pi install must migrate legacy directory link to flat per-skill links"
  [ -L "$skills_dir/commit" ] || fail "Pi install must create flat skill links after migration"
  [ -f "$skills_dir/.almanac-install/owners/codex" ] || \
    fail "Pi install must preserve inferred ownership of legacy Codex links"
  [ -f "$skills_dir/.almanac-install/owners/pi" ] || \
    fail "Pi install must record Pi ownership"
  echo "  PASS: Pi install migrates legacy directory link"
}

test_shared_install_tracks_both_harnesses() {
  local tmp home skills_dir manifest_count expected
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  mkdir -p "$home/.codex"

  HOME="$home" "$ALMANAC" install codex >/dev/null
  HOME="$home" "$ALMANAC" install pi >/dev/null

  [ -f "$skills_dir/.almanac-install/owners/codex" ] || fail "Codex ownership marker missing"
  [ -f "$skills_dir/.almanac-install/owners/pi" ] || fail "Pi ownership marker missing"
  expected="$(skill_count)"
  manifest_count="$(wc -l < "$skills_dir/.almanac-install/manifest.tsv" | tr -d ' ')"
  [ "$manifest_count" -eq "$expected" ] || fail "shared manifest must track every installed skill"
  echo "  PASS: shared install tracks Codex and Pi ownership"
}

test_pi_install_refuses_foreign_collision() {
  local tmp home collision
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  collision="$home/.agents/skills/almanac/commit"
  mkdir -p "$collision"
  printf '%s\n' 'keep me' > "$collision/foreign.txt"

  if HOME="$home" "$ALMANAC" install pi >/dev/null 2>&1; then
    fail "Pi install must reject a foreign skill collision"
  fi
  [ -f "$collision/foreign.txt" ] || fail "Pi install must preserve foreign collision contents"
  echo "  PASS: Pi install refuses foreign skill collisions"
}

echo "=== Install Tests ==="
test_pi_install_links_every_skill
test_pi_install_migrates_legacy_directory_link
test_shared_install_tracks_both_harnesses
test_pi_install_refuses_foreign_collision
echo ""
echo "All install tests passed."
