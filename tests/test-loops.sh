#!/usr/bin/env bash
# test-loops.sh - loop-adapter seam tests (lib/loops.sh + lib/loops/*)
#
# Sources lib/loops.sh DIRECTLY (not through loop-core / the launcher) so the
# seam's interface is its own test surface. The adapters are pure config (exec
# argv composition + signal-file mapping), so nothing here calls a real runner —
# exec_argv is asserted against a fake $ALMANAC_HOME, never executed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/loops.sh"

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

test_discovery_lists_present_adapters() {
  local list
  list="$(almanac_loop_adapter_list)"
  case "$list" in *ralph*) ;; *) fail "loop list should include the ralph adapter file" ;; esac
  case "$list" in *harden*) ;; *) fail "loop list should include the harden adapter file" ;; esac

  almanac_loop_adapter_known ralph  || fail "ralph must be a known loop"
  almanac_loop_adapter_known harden || fail "harden must be a known loop"
  almanac_loop_adapter_known RALPH  || fail "known must normalise case (RALPH -> ralph)"
  if almanac_loop_adapter_known bogus; then fail "an undiscovered name must not be known"; fi
  echo "  PASS: discovery lists present adapters"
}

test_dispatch_rejects_unknown_verb() {
  local rc=0
  almanac_loop_adapter_call ralph no_such_verb >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc" "dispatch should return 2 for a verb the adapter does not implement"
  echo "  PASS: dispatch rejects an unimplemented verb"
}

test_signal_file_control_contract() {
  assert_eq ".ralph-stop"   "$(almanac_loop_adapter_call ralph signal_file stop)"   "ralph stop file basename"
  assert_eq ".ralph-steer"  "$(almanac_loop_adapter_call ralph signal_file steer)"  "ralph steer file basename"
  assert_eq ".harden-stop"  "$(almanac_loop_adapter_call harden signal_file stop)"  "harden stop file basename"
  assert_eq ".harden-steer" "$(almanac_loop_adapter_call harden signal_file steer)" "harden steer file basename"

  local rc=0
  almanac_loop_adapter_call ralph signal_file bogus >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "an unknown signal kind should be rejected"
  echo "  PASS: signal_file control contract"
}

test_ralph_exec_argv_launch_contract() {
  local ALMANAC_HOME="/fake/home"

  almanac_loop_adapter_call ralph exec_argv once "demo-prd"
  assert_eq "bash /fake/home/skills/loop/ralph-loop/scripts/once.sh demo-prd" \
    "${_ALMANAC_LOOP_ARGV[*]}" "ralph once exec argv"

  almanac_loop_adapter_call ralph exec_argv afk "demo-prd" "7"
  assert_eq "bash /fake/home/skills/loop/ralph-loop/scripts/afk.sh demo-prd 7" \
    "${_ALMANAC_LOOP_ARGV[*]}" "ralph afk exec argv"

  local rc=0
  almanac_loop_adapter_call ralph exec_argv bogus "demo-prd" >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc" "an unknown ralph mode should be rejected"
  echo "  PASS: ralph exec_argv launch contract"
}

test_harden_exec_argv_launch_contract() {
  local ALMANAC_HOME="/fake/home"

  almanac_loop_adapter_call harden exec_argv "src/foo.sh"
  assert_eq "bash /fake/home/bin/almanac harden src/foo.sh --loop" \
    "${_ALMANAC_LOOP_ARGV[*]}" "harden exec argv (no rounds)"

  almanac_loop_adapter_call harden exec_argv "src/foo.sh" "3"
  assert_eq "bash /fake/home/bin/almanac harden src/foo.sh --loop --rounds 3" \
    "${_ALMANAC_LOOP_ARGV[*]}" "harden exec argv (with rounds)"
  echo "  PASS: harden exec_argv launch contract"
}

echo "=== Loop Seam Tests ==="
test_discovery_lists_present_adapters
test_dispatch_rejects_unknown_verb
test_signal_file_control_contract
test_ralph_exec_argv_launch_contract
test_harden_exec_argv_launch_contract

echo "All loop seam tests passed."
