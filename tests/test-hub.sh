#!/usr/bin/env bash
# test-hub.sh — almanac interactive hub (TTY-gated front door) CLI tests
#
# Drives the real `bin/almanac` chain (dispatch -> cmd/hub.sh -> loop-core hub
# render) the way a user / script invokes it. The interactive menus are TTY-only
# and not exercised here; these pin the read-only, scripts-safe contract:
#   - bare `almanac`, non-interactive, prints help and never opens the hub
#   - `almanac hub` renders the registry overview (running + recent) plainly

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC_BIN="$ROOT/bin/almanac"
source "$ROOT/lib/loop-core.sh"

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
  case "$1" in
    *"$2"*) ;;
    *) fail "$3" ;;
  esac
}

new_tmpdir() {
  NEW_TMPDIR="$(mktemp -d)"
  TMPDIRS+=("$NEW_TMPDIR")
}

# Criterion 1: bare `almanac`, non-interactive (piped/captured stdio), prints
# help — it must NOT open the hub — so scripts that call bare almanac keep
# working and never block on a menu.
test_bare_almanac_non_tty_prints_help() {
  local out
  out="$("$ALMANAC_BIN" </dev/null 2>&1)"
  assert_contains "$out" "Usage: almanac" "bare almanac off a TTY must print help"
  # The hub overview prints "Running"/"Recent" section headers; help never does,
  # so their absence proves the hub did not open.
  case "$out" in
    *"Recent"*) fail "bare almanac off a TTY must not open the hub" ;;
  esac
  echo "  PASS: bare almanac off a TTY prints help"
}

# Criteria 2 + 5: `almanac hub` renders the run overview from the registry under
# the caller's repo — running loops with live status, and recent finished loops —
# degrading to plain output off a TTY / without gum.
test_hub_command_renders_registry_overview() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "hub-live" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "hub-live" "3" "reviewers: security,perf"
  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "$$" "hub-done" "2026-05-25T11:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "hub-done" "done" "2026-05-25T11:30:00Z"

  out="$(cd "$tmp" && ALMANAC_NO_GUM=1 "$ALMANAC_BIN" hub </dev/null 2>&1)"
  assert_contains "$out" "Running" "hub shows a running section"
  assert_contains "$out" "hub-live" "hub lists the running loop from the registry"
  assert_contains "$out" "round 3" "hub shows the running loop's live status"
  assert_contains "$out" "Recent" "hub shows a recent section"
  assert_contains "$out" "hub-done" "hub lists the recent finished loop"
  echo "  PASS: hub command renders registry overview"
}

echo "=== Hub Tests ==="
test_bare_almanac_non_tty_prints_help
test_hub_command_renders_registry_overview
echo ""
echo "All hub tests passed."
