#!/usr/bin/env bash
# test-converge.sh - Converge CLI skeleton behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC="$ROOT/bin/almanac"

source "$ROOT/lib/converge-core.sh"

TMPDIRS=()
NEW_TMPDIR=""

cleanup() {
  local dir
  [ "${#TMPDIRS[@]}" -eq 0 ] && return 0
  for dir in "${TMPDIRS[@]}"; do
    chmod -R u+w "$dir" >/dev/null 2>&1 || true
    rm -rf "$dir"
  done
}
trap cleanup EXIT

fail() {
  echo "  FAIL: $1" >&2
  exit 1
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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

new_tmpdir() {
  NEW_TMPDIR="$(mktemp -d)"
  TMPDIRS+=("$NEW_TMPDIR")
}

run_converge() {
  local tmp="$1"
  shift
  (cd "$tmp" && "$ALMANAC" converge "$@")
}

test_cli_requires_goal_and_exec() {
  local tmp output rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  output="$(run_converge "$tmp" --exec "true" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing --goal should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing --goal should show usage hint"
  assert_contains "$output" "Missing required --goal" "missing --goal should name the missing arg"

  output="$(run_converge "$tmp" --goal "say hello" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing --exec should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing --exec should show usage hint"
  assert_contains "$output" "Missing required --exec" "missing --exec should name the missing arg"

  echo "  PASS: converge CLI requires --goal and --exec"
}

test_plan_dir_scaffold_and_exec_smoke() {
  local tmp marker plan reports
  new_tmpdir
  tmp="$NEW_TMPDIR"
  marker="$tmp/marker"

  run_converge "$tmp" --goal "Say Hello!" --exec "touch '$marker'" >/dev/null

  plan="$tmp/docs/plans/converge/say-hello"
  reports="$plan/agent-reports.log"

  [ -f "$plan/goal.md" ] || fail "goal.md should be scaffolded"
  [ -f "$reports" ] || fail "agent-reports.log should be scaffolded"
  [ -f "$plan/goal.history.log" ] || fail "goal.history.log should be scaffolded"
  [ -f "$marker" ] || fail "exec command should run through bash"
  assert_file_contains "$plan/goal.md" "Say Hello!" "goal.md should contain the goal text"
  [ ! -s "$plan/goal.history.log" ] || fail "goal.history.log should start empty"
  assert_file_contains "$reports" "===== tick=1 ts=" "agent report should include tick 1 header"
  assert_file_contains "$reports" " exit=0 =====" "agent report should record exec exit code"
  assert_eq "1" "$(grep -c '^===== tick=1 ts=.* exit=0 =====$' "$reports")" \
    "one report header should be appended for one round"

  echo "  PASS: converge scaffolds plan files and runs exec once"
}

test_registry_records_converge_run_done() {
  local tmp row run_id status_file status_blob
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Registry Goal" --exec "true" >/dev/null

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  [ -n "$row" ] || fail "converge run should be indexed"
  assert_eq "converge" "$(printf '%s' "$row" | cut -f2)" "registry type should be converge"
  assert_eq "registry-goal" "$(printf '%s' "$row" | cut -f3)" "registry target should be the goal slug"
  assert_eq "done" "$(printf '%s' "$row" | cut -f7)" "clean run should be marked done"

  run_id="$(printf '%s' "$row" | cut -f1)"
  status_file="$tmp/.almanac/runs/$run_id/status.tsv"
  [ -f "$status_file" ] || fail "status.tsv should exist"
  status_blob="$(cat "$status_file")"
  assert_contains "$status_blob" $'type\tconverge' "status record should carry type"
  assert_contains "$status_blob" $'target\tregistry-goal' "status record should carry target slug"
  assert_contains "$status_blob" $'status\tdone' "status record should be done"
  assert_contains "$status_blob" $'rounds\t1' "--rounds default should be stored as 1 in slice 01"

  echo "  PASS: converge registers and marks run done"
}

test_run_aborts_cleanly_when_plan_dir_unwritable() {
  local tmp output rc row status
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/docs/plans/converge"
  chmod 500 "$tmp/docs/plans/converge"

  # Regression parity with harden commit 1467073: a mid-loop _die after run
  # registration must mark the run aborted without trap-time set -u crashes.
  output="$(run_converge "$tmp" --goal "Blocked Plan" --exec "true" 2>&1)" && rc=0 || rc=$?
  chmod 700 "$tmp/docs/plans/converge"

  [ "$rc" -ne 0 ] || fail "unwritable plan dir should exit non-zero"
  case "$output" in
    *"unbound variable"*) fail "EXIT trap must not crash on unbound variable (got: $output)" ;;
  esac
  assert_contains "$output" "Could not create converge plan dir" \
    "underlying _die message should reach the user"

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  [ -n "$row" ] || fail "run should register before scaffold _die"
  status="$(printf '%s' "$row" | cut -f7)"
  assert_eq "aborted" "$status" "mid-loop _die should mark run aborted"

  echo "  PASS: converge abort trap marks run aborted without set -u crash"
}

test_cli_requires_goal_and_exec
test_plan_dir_scaffold_and_exec_smoke
test_registry_records_converge_run_done
test_run_aborts_cleanly_when_plan_dir_unwritable

echo "All converge tests passed."
