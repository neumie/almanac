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

test_pi_uninstall_removes_only_almanac_links() {
  local tmp home skills_dir foreign_source almanac_link
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  foreign_source="$tmp/foreign-almanac-skill"
  mkdir -p "$home" "$foreign_source"
  printf '%s\n' '# Foreign skill' > "$foreign_source/SKILL.md"

  HOME="$home" "$ALMANAC" install pi >/dev/null
  almanac_link="$skills_dir/commit"
  [ -L "$almanac_link" ] || fail "fixture must install Pi skill links"
  ln -s "$foreign_source" "$skills_dir/foreign-skill"

  HOME="$home" "$ALMANAC" uninstall pi >/dev/null

  [ ! -e "$almanac_link" ] && [ ! -L "$almanac_link" ] || \
    fail "Pi uninstall must remove Almanac skill links"
  [ -L "$skills_dir/foreign-skill" ] || \
    fail "Pi uninstall must preserve non-Almanac skill links"
  echo "  PASS: Pi uninstall removes only manifest-owned links"
}

test_shared_uninstall_retains_other_harness() {
  local tmp home skills_dir link
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  link="$skills_dir/commit"
  mkdir -p "$home/.codex"

  HOME="$home" "$ALMANAC" install codex >/dev/null
  HOME="$home" "$ALMANAC" install pi >/dev/null
  HOME="$home" "$ALMANAC" uninstall pi >/dev/null

  [ -L "$link" ] || fail "Pi uninstall must retain links still owned by Codex"
  [ -f "$skills_dir/.almanac-install/owners/codex" ] || fail "Codex ownership marker must remain"
  [ ! -f "$skills_dir/.almanac-install/owners/pi" ] || fail "Pi ownership marker must be removed"

  HOME="$home" "$ALMANAC" uninstall codex >/dev/null
  [ ! -e "$link" ] && [ ! -L "$link" ] || \
    fail "last shared owner uninstall must remove managed links"
  echo "  PASS: shared uninstall retains links until last harness leaves"
}

test_pi_uninstall_uses_exact_manifest_target() {
  local tmp home skills_dir state_dir source target outside_source outside_link
  new_tmpdir
  tmp="$NEW_TMPDIR"
  home="$tmp/home"
  skills_dir="$home/.agents/skills/almanac"
  state_dir="$skills_dir/.almanac-install"
  source="$tmp/toolbox/skills/git/commit"
  target="$skills_dir/commit"
  outside_source="$tmp/outside-source"
  outside_link="$home/.agents/outside"
  mkdir -p "$state_dir/owners" "$source" "$outside_source"
  printf '%s\n' '# Test skill' > "$source/SKILL.md"
  ln -s "$source" "$target"
  ln -s "$outside_source" "$outside_link"
  printf 'commit\t%s\n' "$source" > "$state_dir/manifest.tsv"
  printf '../../outside\t%s\n' "$outside_source" >> "$state_dir/manifest.tsv"
  : > "$state_dir/owners/pi"

  HOME="$home" "$ALMANAC" uninstall pi >/dev/null

  [ ! -e "$target" ] && [ ! -L "$target" ] || \
    fail "Pi uninstall must remove an exact manifest target without relying on path substrings"
  [ -L "$outside_link" ] || fail "Pi uninstall must ignore path traversal in a malformed manifest"
  echo "  PASS: Pi uninstall uses exact manifest ownership"
}

echo "=== Uninstall Tests ==="
test_claude_uninstall_removes_current_skill_dir_symlinks
test_claude_uninstall_handles_quote_in_home
test_pi_uninstall_removes_only_almanac_links
test_shared_uninstall_retains_other_harness
test_pi_uninstall_uses_exact_manifest_target
echo ""
echo "All uninstall tests passed."
