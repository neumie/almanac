#!/usr/bin/env bash
# test-uninstall.sh - uninstall cleanup regressions

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
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

new_tmpdir() {
  NEW_TMPDIR="$(mktemp -d)"
  TMPDIRS+=("$NEW_TMPDIR")
}

test_claude_uninstall_removes_current_skill_dir_symlinks() {
  local tmp home skill_dir skill_name source_skill
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  mkdir -p "$home/.claude/skills/almanac" "$home/.claude/commands/almanac"

  source_skill="$(find "$ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md -print | head -n1)"
  [ -n "$source_skill" ] || fail "fixture needs at least one skill"
  source_skill="$(dirname "$source_skill")"
  skill_name="$(basename "$source_skill")"
  skill_dir="$home/.claude/skills/almanac/$skill_name"
  ln -s "$source_skill" "$skill_dir"

  HOME="$home" "$ALMANAC" uninstall claude-code >/dev/null

  [ ! -e "$skill_dir" ] && [ ! -L "$skill_dir" ] || \
    fail "Claude uninstall must remove current per-skill directory symlinks"
  echo "  PASS: Claude uninstall removes current skill-dir symlinks"
}

test_claude_uninstall_handles_quote_in_home() {
  local tmp home registry
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home'quote"
  registry="$home/.claude/plugins/installed_plugins.json"
  mkdir -p "$(dirname "$registry")"
  printf '%s\n' '{"plugins":{"almanac@local":{"path":"x"},"other":{}}}' > "$registry"

  HOME="$home" "$ALMANAC" uninstall claude-code >/dev/null

  assert_file_contains "$registry" '"other"' "uninstall should preserve unrelated plugin entries"
  case "$(cat "$registry")" in
    *"almanac@local"*) fail "uninstall should remove almanac@local with quote-bearing HOME" ;;
    *) ;;
  esac
  echo "  PASS: Claude uninstall handles quote-bearing HOME"
}

echo "=== Uninstall Tests ==="
test_claude_uninstall_removes_current_skill_dir_symlinks
test_claude_uninstall_handles_quote_in_home
echo ""
echo "All uninstall tests passed."
