#!/usr/bin/env bash
# test-ui.sh - gum-or-plain UI seam tests (lib/ui.sh)
#
# Sources lib/ui.sh DIRECTLY (not through loop-core) so the seam's interface is
# its own test surface. Every assertion forces the plain path via ALMANAC_NO_GUM=1
# so it runs the same off any terminal, with no real gum calls.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/ui.sh"

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message" ;;
  esac
}

test_ui_render_degrades_without_gum() {
  local out rc
  out="$(printf '%s\n' "reviewer-security stalled" | ALMANAC_NO_GUM=1 almanac_loop_ui_render)"
  assert_contains "$out" "reviewer-security stalled" "ui render must pass content through plainly when gum is suppressed"

  rc=0
  ALMANAC_NO_GUM=1 almanac_loop_ui_has_gum || rc=$?
  [ "$rc" -ne 0 ] || fail "has_gum must report absent when ALMANAC_NO_GUM is set"
  echo "  PASS: ui render degrades without gum"
}

test_ui_fit_keeps_rows_on_one_line() {
  local out
  out="$(printf 'short row\n' | almanac_loop_ui_fit 20)"
  assert_eq "short row" "$out" "fit leaves a line within the width unchanged"

  out="$(printf 'twenty-char-line-xx\n' | almanac_loop_ui_fit 20)"
  assert_eq "twenty-char-line-xx" "$out" "fit leaves an at-width line unchanged"

  # A line wider than max is clipped to one line and flagged with an ellipsis,
  # so a long row can never wrap and shift the columns / box border.
  out="$(printf 'this row is definitely much longer than twenty columns\n' | almanac_loop_ui_fit 20)"
  assert_contains "$out" "…" "fit marks a clipped row with an ellipsis"
  case "$out" in
    "this row is "*) ;;
    *) fail "fit preserves the clipped row's prefix" ;;
  esac
  [ "${#out}" -lt 54 ] || fail "fit actually shortened the long row"
  echo "  PASS: ui fit keeps rows on one line"
}

test_ui_cols_returns_sane_width() {
  local cols
  cols="$(almanac_loop_ui_cols)"
  case "$cols" in
    ''|*[!0-9]*) fail "cols must be numeric (got '$cols')" ;;
  esac
  [ "$cols" -ge 24 ] || fail "cols must respect the floor (got $cols)"
  echo "  PASS: ui cols returns a sane width"
}

test_ui_status_glyph_maps_states() {
  assert_eq "●" "$(almanac_loop_ui_status_glyph running)" "running maps to its glyph"
  assert_eq "✔" "$(almanac_loop_ui_status_glyph done)" "done maps to its glyph"
  assert_eq "◌" "$(almanac_loop_ui_status_glyph stale)" "stale maps to its glyph"
  assert_eq "•" "$(almanac_loop_ui_status_glyph whatever)" "an unknown state falls back to the bullet"
  echo "  PASS: ui status glyph maps states"
}

test_ui_menu_render_numbers_options() {
  local out
  out="$(almanac_loop_ui_menu_render "+ New run" "watch" "quit")"
  assert_contains "$out" "1) + New run" "menu render numbers the first option"
  assert_contains "$out" "2) watch" "menu render numbers the second option"
  assert_contains "$out" "3) quit" "menu render numbers the third option"
  echo "  PASS: ui menu render numbers options"
}

test_ui_menu_pick_maps_and_rejects() {
  local rc
  assert_eq "watch" "$(almanac_loop_ui_menu_pick 2 "+ New run" "watch" "quit")" "pick maps a number to its option"
  assert_eq "+ New run" "$(almanac_loop_ui_menu_pick 1 "+ New run" "watch" "quit")" "pick maps the first option"

  rc=0; almanac_loop_ui_menu_pick "" "a" "b" >/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "pick must reject a blank selection"
  rc=0; almanac_loop_ui_menu_pick "x" "a" "b" >/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "pick must reject a non-numeric selection"
  rc=0; almanac_loop_ui_menu_pick "9" "a" "b" >/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "pick must reject an out-of-range selection"
  echo "  PASS: ui menu pick maps and rejects"
}

test_ui_choose_degrades_to_numbered_menu() {
  local out err rc
  # Without gum, choose prints a numbered menu (to stderr) and reads a number from
  # stdin, echoing the chosen option (and only that) on stdout.
  out="$(printf '2\n' | ALMANAC_NO_GUM=1 almanac_loop_ui_choose "Pick one" "alpha" "beta" "gamma" 2>/dev/null)"
  assert_eq "beta" "$out" "plain choose maps the typed number to the option"

  err="$(printf '2\n' | ALMANAC_NO_GUM=1 almanac_loop_ui_choose "Pick one" "alpha" "beta" 2>&1 >/dev/null)"
  assert_contains "$err" "1) alpha" "plain choose renders the numbered menu on stderr"
  assert_contains "$err" "Pick one" "plain choose renders the header on stderr"

  rc=0
  printf 'bogus\n' | ALMANAC_NO_GUM=1 almanac_loop_ui_choose "Pick one" "alpha" "beta" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "plain choose must return nonzero on bad input (cancel-equivalent)"
  echo "  PASS: ui choose degrades to a numbered menu"
}

test_ui_input_degrades_to_read() {
  local out
  out="$(printf 'src/app.js\n' | ALMANAC_NO_GUM=1 almanac_loop_ui_input "Target" 2>/dev/null)"
  assert_eq "src/app.js" "$out" "plain input returns the typed value"

  # Empty input falls back to the default.
  out="$(printf '\n' | ALMANAC_NO_GUM=1 almanac_loop_ui_input "Iterations" "10" 2>/dev/null)"
  assert_eq "10" "$out" "plain input falls back to the default on empty input"
  echo "  PASS: ui input degrades to read"
}

test_ui_confirm_degrades_to_read() {
  local rc
  rc=0; printf 'y\n'  | ALMANAC_NO_GUM=1 almanac_loop_ui_confirm "Go?" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "plain confirm must return 0 (yes) for 'y'"
  rc=0; printf 'n\n'  | ALMANAC_NO_GUM=1 almanac_loop_ui_confirm "Go?" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "plain confirm must return 1 (no) for 'n'"
  rc=0; printf '\n'   | ALMANAC_NO_GUM=1 almanac_loop_ui_confirm "Go?" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "plain confirm must default to yes on empty input (gum affirmative default)"
  echo "  PASS: ui confirm degrades to read"
}

echo "=== UI Seam Tests ==="
test_ui_render_degrades_without_gum
test_ui_fit_keeps_rows_on_one_line
test_ui_cols_returns_sane_width
test_ui_status_glyph_maps_states
test_ui_menu_render_numbers_options
test_ui_menu_pick_maps_and_rejects
test_ui_choose_degrades_to_numbered_menu
test_ui_input_degrades_to_read
test_ui_confirm_degrades_to_read

echo "All UI seam tests passed."
