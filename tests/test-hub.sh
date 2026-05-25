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

# Criterion 4: `almanac hub --steer <id> <directive>` queues a steer directive for
# a running loop by writing the run type's steer file under the caller's repo (the
# loop's working dir) — the next round consumes it. Non-interactive seam the gum
# menu's steer action also drives.
test_hub_steer_queues_directive() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "$$" "steer-cli" "2026-05-25T12:00:00Z" >/dev/null

  out="$(cd "$tmp" && "$ALMANAC_BIN" hub --steer steer-cli "stop adding perf tests" </dev/null 2>&1)"
  [ -f "$tmp/.ralph-steer" ] || fail "hub --steer must write the run's steer file"
  case "$(cat "$tmp/.ralph-steer")" in
    *"stop adding perf tests"*) ;;
    *) fail "steer file must carry the directive" ;;
  esac
  echo "  PASS: hub --steer queues a directive"
}

# Criterion 4: `almanac hub --stop <id>` signals a running loop to stop by writing
# the run type's stop file under the caller's repo. Uses a dead pid so the
# best-effort TERM never touches the test process.
test_hub_stop_signals_run() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "2147483647" "stop-cli" "2026-05-25T12:00:00Z" >/dev/null

  out="$(cd "$tmp" && "$ALMANAC_BIN" hub --stop stop-cli </dev/null 2>&1)"
  [ -f "$tmp/.ralph-stop" ] || fail "hub --stop must write the run's stop file"
  echo "  PASS: hub --stop signals a run"
}

# Criterion 4: `almanac hub --watch <id>`, off a TTY, renders the run's detail
# once (the one-shot path) rather than blocking on a follow redraw.
test_hub_watch_renders_run_detail() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "watch-cli" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "watch-cli" "4" "lenses=security open-blocking=1"

  out="$(cd "$tmp" && ALMANAC_NO_GUM=1 "$ALMANAC_BIN" hub --watch watch-cli </dev/null 2>&1)"
  assert_contains "$out" "watch-cli" "hub --watch renders the run id"
  assert_contains "$out" "open-blocking=1" "hub --watch renders the live summary"
  echo "  PASS: hub --watch renders run detail"
}

# Criterion 3: `almanac hub --new ralph … --dry-run` composes (without launching)
# the ralph launcher invocation from the menu's config flags. The gum New-run menu
# drives the same seam; --dry-run is the non-interactive, scripts-safe preview.
test_hub_new_dry_run_composes_ralph_launch() {
  local out
  out="$("$ALMANAC_BIN" hub --new ralph --prd auth-system --mode afk --iterations 4 --provider codex --dry-run </dev/null 2>&1)"
  assert_contains "$out" "ralph" "hub --new ralph dry-run shows the ralph launch"
  assert_contains "$out" "--prd auth-system" "dry-run shows --prd"
  assert_contains "$out" "--mode afk" "dry-run shows --mode"
  assert_contains "$out" "--iterations 4" "dry-run shows --iterations"
  assert_contains "$out" "--provider codex" "dry-run shows --provider"
  echo "  PASS: hub --new ralph dry-run composes the launch"
}

# Criterion 3: `almanac hub --new harden … --dry-run` composes the harden
# convergence-loop launch — its --rounds flag plus the HARDEN_* env its reviewer
# config rides on.
test_hub_new_dry_run_composes_harden_launch() {
  local out
  out="$("$ALMANAC_BIN" hub --new harden --target src/app.js --rounds 2 --lenses security,perf --provider codex --dry-run </dev/null 2>&1)"
  assert_contains "$out" "harden src/app.js --loop" "harden dry-run shows the loop launch"
  assert_contains "$out" "--rounds 2" "harden dry-run shows --rounds"
  assert_contains "$out" "HARDEN_LENSES=security,perf" "harden dry-run shows the lenses env"
  assert_contains "$out" "HARDEN_PROVIDER=codex" "harden dry-run shows the provider env"
  echo "  PASS: hub --new harden dry-run composes the launch"
}

# Criterion 3: a new run missing its required config (harden target) is rejected
# with a non-zero exit rather than launching a malformed run.
test_hub_new_missing_required_errors() {
  local rc=0
  "$ALMANAC_BIN" hub --new harden --rounds 2 --dry-run </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "hub --new harden without a target must exit non-zero"
  echo "  PASS: hub --new without required config errors"
}

echo "=== Hub Tests ==="
test_bare_almanac_non_tty_prints_help
test_hub_command_renders_registry_overview
test_hub_steer_queues_directive
test_hub_stop_signals_run
test_hub_watch_renders_run_detail
test_hub_new_dry_run_composes_ralph_launch
test_hub_new_dry_run_composes_harden_launch
test_hub_new_missing_required_errors
echo ""
echo "All hub tests passed."
