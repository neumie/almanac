#!/usr/bin/env bash
# test-loops.sh - loop-adapter seam tests (lib/loops.sh + lib/loops/*)
#
# Sources lib/loops.sh DIRECTLY (not through loop-core / the launcher) so the
# seam's interface is its own test surface. The adapters are pure config (exec
# argv/new-run composition + signal-file mapping), so nothing here calls a real runner —
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
  case "$list" in *loop*) ;; *) fail "loop list should include the loop adapter file" ;; esac
  case "$list" in *harden*) ;; *) fail "loop list should include the harden adapter file" ;; esac
  case "$list" in *converge*) ;; *) fail "loop list should include the converge adapter file" ;; esac

  almanac_loop_adapter_known loop  || fail "loop must be a known loop"
  almanac_loop_adapter_known harden || fail "harden must be a known loop"
  almanac_loop_adapter_known converge || fail "converge must be a known loop"
  almanac_loop_adapter_known LOOP  || fail "known must normalise case (LOOP -> loop)"
  if almanac_loop_adapter_known bogus; then fail "an undiscovered name must not be known"; fi
  echo "  PASS: discovery lists present adapters"
}

test_dispatch_rejects_unknown_verb() {
  local rc=0
  almanac_loop_adapter_call loop no_such_verb >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc" "dispatch should return 2 for a verb the adapter does not implement"
  echo "  PASS: dispatch rejects an unimplemented verb"
}

test_new_run_usage_contract() {
  local out
  out="$(almanac_loop_adapter_call loop new_run_usage)"
  case "$out" in *"--prd"*) ;; *) fail "loop new_run_usage should mention --prd" ;; esac
  out="$(almanac_loop_adapter_call harden new_run_usage)"
  case "$out" in *"--target"*) ;; *) fail "harden new_run_usage should mention --target" ;; esac
  out="$(almanac_loop_adapter_call converge new_run_usage)"
  case "$out" in *"--goal"*--prompt*--exec*) ;; *) fail "converge new_run_usage should mention goal plus prompt/exec" ;; esac
  echo "  PASS: new_run_usage contract"
}

test_signal_file_control_contract() {
  # The control contract is the resolved signal-file (adapter override OR default
  # convention from lib/loops.sh). Adapters that follow the standard
  # `.${name}-${kind}` pattern need not define signal_file at all — the default
  # provides it. Test at the public resolver, not the adapter, so deleting the
  # three identical adapter functions doesn't break this surface.
  assert_eq ".loop-stop"   "$(almanac_loop_signal_file loop stop)"   "loop stop file basename"
  assert_eq ".loop-steer"  "$(almanac_loop_signal_file loop steer)"  "loop steer file basename"
  assert_eq ".harden-stop"  "$(almanac_loop_signal_file harden stop)"  "harden stop file basename"
  assert_eq ".harden-steer" "$(almanac_loop_signal_file harden steer)" "harden steer file basename"
  assert_eq ".converge-stop" "$(almanac_loop_signal_file converge stop)" "converge stop file basename"
  assert_eq ".converge-steer" "$(almanac_loop_signal_file converge steer)" "converge steer file basename"

  local rc=0
  almanac_loop_signal_file loop bogus >/dev/null 2>&1 || rc=$?
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

test_loop_exec_argv_launch_contract() {
  local ALMANAC_HOME="/fake/home"

  almanac_loop_adapter_call loop exec_argv once "demo-prd"
  assert_eq "bash /fake/home/skills/loop/loop/scripts/once.sh demo-prd" \
    "${_ALMANAC_LOOP_ARGV[*]}" "loop once exec argv"

  almanac_loop_adapter_call loop exec_argv afk "demo-prd" "7"
  assert_eq "bash /fake/home/skills/loop/loop/scripts/afk.sh demo-prd 7" \
    "${_ALMANAC_LOOP_ARGV[*]}" "loop afk exec argv"

  local rc=0
  almanac_loop_adapter_call loop exec_argv bogus "demo-prd" >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc" "an unknown loop mode should be rejected"
  echo "  PASS: loop exec_argv launch contract"
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

test_kv_get_picks_value() {
  assert_eq "auth-system" "$(_almanac_loop_kv_get prd prd=auth-system mode=afk)" "kv_get picks the matching value"
  assert_eq "afk"         "$(_almanac_loop_kv_get mode prd=auth-system mode=afk)" "kv_get scans every pair"
  assert_eq ""            "$(_almanac_loop_kv_get missing prd=auth-system)"      "kv_get echoes empty for an absent key"
  assert_eq ""            "$(_almanac_loop_kv_get prd)"                          "kv_get echoes empty with no pairs"
  # A value that contains `=` round-trips (e.g. converge --exec foo=bar).
  assert_eq "echo foo=bar" "$(_almanac_loop_kv_get exec "exec=echo foo=bar")"    "kv_get preserves '=' in values"
  # Last pair wins (matches the case-statement semantics the loops used inline).
  assert_eq "second" "$(_almanac_loop_kv_get k k=first k=second)" "kv_get: later pair wins"
  echo "  PASS: _almanac_loop_kv_get"
}

echo "=== Loop Seam Tests ==="
test_discovery_lists_present_adapters
test_dispatch_rejects_unknown_verb
test_new_run_usage_contract
test_signal_file_control_contract
test_loop_exec_argv_launch_contract
test_harden_exec_argv_launch_contract
test_converge_exec_argv_launch_contract
test_kv_get_picks_value

echo "All loop seam tests passed."
