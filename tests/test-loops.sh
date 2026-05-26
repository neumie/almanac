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
  case "$list" in *converge*) ;; *) fail "loop list should include the converge adapter file" ;; esac

  almanac_loop_adapter_known ralph  || fail "ralph must be a known loop"
  almanac_loop_adapter_known harden || fail "harden must be a known loop"
  almanac_loop_adapter_known converge || fail "converge must be a known loop"
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
  # The control contract is the resolved signal-file (adapter override OR default
  # convention from lib/loops.sh). Adapters that follow the standard
  # `.${name}-${kind}` pattern need not define signal_file at all — the default
  # provides it. Test at the public resolver, not the adapter, so deleting the
  # three identical adapter functions doesn't break this surface.
  assert_eq ".ralph-stop"   "$(almanac_loop_signal_file ralph stop)"   "ralph stop file basename"
  assert_eq ".ralph-steer"  "$(almanac_loop_signal_file ralph steer)"  "ralph steer file basename"
  assert_eq ".harden-stop"  "$(almanac_loop_signal_file harden stop)"  "harden stop file basename"
  assert_eq ".harden-steer" "$(almanac_loop_signal_file harden steer)" "harden steer file basename"
  assert_eq ".converge-stop" "$(almanac_loop_signal_file converge stop)" "converge stop file basename"
  assert_eq ".converge-steer" "$(almanac_loop_signal_file converge steer)" "converge steer file basename"

  local rc=0
  almanac_loop_signal_file ralph bogus >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "an unknown signal kind should be rejected"

  rc=0
  almanac_loop_signal_file bogus stop >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "an unknown loop name should be rejected"

  # The default applies to a hypothetical new loop without writing a single
  # signal_file function — this is the deepening claim under test.
  assert_eq ".future-stop"  "$(almanac_loop_default_signal_file future stop)"  "default signal file applies to any loop name"
  assert_eq ".future-steer" "$(almanac_loop_default_signal_file future steer)" "default signal file applies to any loop name"
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

test_converge_exec_argv_launch_contract() {
  local ALMANAC_HOME="/fake/home"
  local rc

  # Minimum exec-mode: goal + exec
  almanac_loop_adapter_call converge exec_argv "ship it" "exec" "echo hi"
  assert_eq "bash /fake/home/bin/almanac converge --goal ship it --exec echo hi" \
    "${_ALMANAC_LOOP_ARGV[*]}" "converge exec argv (exec-mode goal + action)"

  # Minimum prompt-mode: goal + prompt
  almanac_loop_adapter_call converge exec_argv "ship it" "prompt" "/almanac:codebase-improve"
  assert_eq "bash /fake/home/bin/almanac converge --goal ship it --prompt /almanac:codebase-improve" \
    "${_ALMANAC_LOOP_ARGV[*]}" "converge exec argv (prompt-mode goal + action)"

  # With rounds (4th positional)
  almanac_loop_adapter_call converge exec_argv "ship it" "exec" "echo hi" "5"
  assert_eq "bash /fake/home/bin/almanac converge --goal ship it --exec echo hi --rounds 5" \
    "${_ALMANAC_LOOP_ARGV[*]}" "converge exec argv (with rounds)"

  # With --no-oversee (5th positional, non-empty + non-"0" enables)
  almanac_loop_adapter_call converge exec_argv "ship it" "exec" "echo hi" "5" "1"
  assert_eq "bash /fake/home/bin/almanac converge --goal ship it --exec echo hi --rounds 5 --no-oversee" \
    "${_ALMANAC_LOOP_ARGV[*]}" "converge exec argv (with --no-oversee)"

  # An empty no_oversee or "0" must NOT emit the flag
  almanac_loop_adapter_call converge exec_argv "ship it" "exec" "echo hi" "5" ""
  case " ${_ALMANAC_LOOP_ARGV[*]} " in
    *" --no-oversee "*) fail "empty no_oversee must NOT emit --no-oversee" ;;
  esac

  # With --oversee-every (6th positional)
  almanac_loop_adapter_call converge exec_argv "ship it" "exec" "echo hi" "" "" "3"
  assert_eq "bash /fake/home/bin/almanac converge --goal ship it --exec echo hi --oversee-every 3" \
    "${_ALMANAC_LOOP_ARGV[*]}" "converge exec argv (with --oversee-every)"

  # Unknown mode returns 2
  rc=0; almanac_loop_adapter_call converge exec_argv "ship it" "bogus" "x" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "converge exec_argv must return 2 for an unknown mode"

  echo "  PASS: converge exec_argv launch contract"
}

echo "=== Loop Seam Tests ==="
test_discovery_lists_present_adapters
test_dispatch_rejects_unknown_verb
test_signal_file_control_contract
test_ralph_exec_argv_launch_contract
test_harden_exec_argv_launch_contract
test_converge_exec_argv_launch_contract

echo "All loop seam tests passed."
