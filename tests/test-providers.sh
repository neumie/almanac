#!/usr/bin/env bash
# test-providers.sh - provider-adapter seam tests (lib/agent.sh + lib/providers/*)
#
# Sources lib/agent.sh DIRECTLY (not through loop-core) so the seam's interface is
# its own test surface. Availability + default-selection run behind a fake
# command -v: a temp bin holds fake `codex`/`claude` executables and PATH is
# restricted to it plus the system coreutils dirs, so no real provider CLI is
# consulted and no model is ever called.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/agent.sh"

# A minimal PATH that excludes any real codex/claude (those live in
# /usr/local/bin, ~/.local/bin, npm prefixes — never /usr/bin or /bin) but keeps
# the coreutils the seam needs (tr, basename, mktemp).
SYSPATH="/usr/bin:/bin"

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message (looking for '$needle' in '$haystack')" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) fail "$message (unexpected '$needle' in '$haystack')" ;;
  esac
}

# Write fake provider executables (just need to exist + be executable for
# command -v) into a fresh temp bin. Args after the dir name the providers.
make_fakebin() {
  local dir="$1"; shift
  local p
  mkdir -p "$dir"
  for p in "$@"; do
    printf '#!/bin/sh\nexit 0\n' > "$dir/$p"
    chmod +x "$dir/$p"
  done
}

test_discovery_lists_present_adapters() {
  local list
  list="$(almanac_provider_list)"
  assert_contains "$list" "codex" "provider list should include the codex adapter file"
  assert_contains "$list" "claude" "provider list should include the claude adapter file"

  almanac_provider_known codex  || fail "codex must be a known provider"
  almanac_provider_known claude || fail "claude must be a known provider"
  almanac_provider_known CLAUDE || fail "known must normalise case (CLAUDE -> claude)"
  almanac_provider_known claude-code || fail "known must normalise claude-code -> claude"
  if almanac_provider_known bogus; then fail "an undiscovered name must not be known"; fi
  echo "  PASS: discovery lists present adapters"
}

test_availability_behind_fake_command_v() {
  local tmp
  tmp="$(mktemp -d)"
  make_fakebin "$tmp/bin" codex claude

  PATH="$tmp/bin:$SYSPATH" almanac_provider_available codex  || fail "codex should be available when its CLI is on PATH"
  PATH="$tmp/bin:$SYSPATH" almanac_provider_available claude || fail "claude should be available when its CLI is on PATH"

  make_fakebin "$tmp/only-codex" codex
  if PATH="$tmp/only-codex:$SYSPATH" almanac_provider_available claude; then
    fail "claude should be unavailable when only codex is on PATH"
  fi
  rm -rf "$tmp"
  echo "  PASS: availability checks consult command -v"
}

test_active_env_signals() {
  ( CODEX_THREAD_ID=thread-123 almanac_provider_active_env codex ) \
    || fail "codex active_env should be true inside a codex thread"
  if ( unset CODEX_THREAD_ID; almanac_provider_active_env codex ); then
    fail "codex active_env should be false with no CODEX_THREAD_ID"
  fi
  if almanac_provider_active_env claude; then
    fail "claude active_env should always be false (no thread-resume signal)"
  fi
  echo "  PASS: active-env signals"
}

test_menus_and_display() {
  local models efforts
  models="$(almanac_provider_models codex)"
  assert_contains "$models" "default" "codex models should offer the default sentinel"
  assert_contains "$models" "gpt-5.5" "codex models should list a codex model"
  assert_contains "$models" "custom"  "codex models should offer the custom sentinel"

  efforts="$(almanac_provider_efforts claude)"
  assert_contains "$efforts" "max" "claude efforts should include max (claude-only)"
  efforts="$(almanac_provider_efforts codex)"
  assert_not_contains "$efforts" "max" "codex efforts should not include max"

  assert_eq "Codex" "$(almanac_provider_display codex)" "codex display name"
  assert_eq "Claude Code" "$(almanac_provider_display claude)" "claude display name"
  echo "  PASS: menus and display"
}

test_codex_argv_deep_invocation() {
  almanac_provider_call codex argv "gpt-test" "high" "read-only" "/tmp/res" "structured"
  local args="${_ALMANAC_AGENT_ARGV[*]}"
  assert_eq "codex" "${_ALMANAC_AGENT_ARGV[0]}" "codex argv should begin with the codex executable"
  assert_contains "$args" "--ask-for-approval never" "codex argv should disable approval prompts"
  assert_contains "$args" "--sandbox read-only" "codex argv should pass the sandbox value"
  assert_contains "$args" "--json" "structured codex argv should request --json"
  assert_contains "$args" "--output-last-message /tmp/res" "codex argv should capture the final message"
  assert_contains "$args" "--model gpt-test" "codex argv should pass the model"
  assert_contains "$args" 'model_reasoning_effort="high"' "codex argv should pass the effort"

  almanac_provider_call codex argv "" "" "danger-full-access" "/tmp/res" "raw"
  args="${_ALMANAC_AGENT_ARGV[*]}"
  assert_not_contains "$args" "--json" "raw codex argv should omit --json (native passthrough)"
  assert_contains "$args" "--sandbox danger-full-access" "raw codex argv should still pass the sandbox"
  echo "  PASS: codex argv (deep invocation)"
}

test_claude_argv_permission_mapping() {
  almanac_provider_call claude argv "sonnet-test" "medium" "read-only" "/tmp/res" "structured"
  local args="${_ALMANAC_AGENT_ARGV[*]}"
  assert_eq "claude" "${_ALMANAC_AGENT_ARGV[0]}" "claude argv should begin with the claude executable"
  assert_contains "$args" "--print" "claude argv should print non-interactively"
  assert_contains "$args" "--output-format stream-json" "claude argv should stream json"
  assert_contains "$args" "--permission-mode plan" "read-only sandbox maps to plan"
  assert_contains "$args" "--model sonnet-test" "claude argv should pass the model"
  assert_contains "$args" "--effort medium" "claude argv should pass the effort"

  almanac_provider_call claude argv "" "" "workspace-write" "/tmp/res" "structured"
  assert_contains "${_ALMANAC_AGENT_ARGV[*]}" "--permission-mode acceptEdits" "workspace-write maps to acceptEdits"

  almanac_provider_call claude argv "" "" "default" "/tmp/res" "structured"
  assert_not_contains "${_ALMANAC_AGENT_ARGV[*]}" "--permission-mode" "the default sentinel omits --permission-mode"
  echo "  PASS: claude argv (sandbox -> permission mapping)"
}

test_filters_defined_in_adapter() {
  local cf
  cf="$(almanac_provider_filter codex)"
  assert_contains "$cf" "item.completed" "codex filter should match codex agent-message events"
  cf="$(almanac_provider_filter claude)"
  assert_contains "$cf" "assistant" "claude filter should match claude assistant events"
  echo "  PASS: filters defined in the adapter"
}

test_default_selection_policy() {
  local tmp out
  tmp="$(mktemp -d)"
  make_fakebin "$tmp/both" codex claude
  make_fakebin "$tmp/only-codex" codex

  # Active-env (codex thread) wins over preference order, when codex is installed.
  out="$(CODEX_THREAD_ID=t PATH="$tmp/both:$SYSPATH" almanac_provider_default)"
  assert_eq "codex" "$out" "active-env codex thread should select codex"

  # No active env: preference order is claude -> codex.
  out="$(unset CODEX_THREAD_ID; PATH="$tmp/both:$SYSPATH" almanac_provider_default)"
  assert_eq "claude" "$out" "with no active env, claude is preferred over codex"

  # Only codex installed: codex even without an active thread.
  out="$(unset CODEX_THREAD_ID; PATH="$tmp/only-codex:$SYSPATH" almanac_provider_default)"
  assert_eq "codex" "$out" "codex is selected when it is the only installed provider"

  # Nothing installed: empty.
  out="$(unset CODEX_THREAD_ID; PATH="$tmp/empty:$SYSPATH" almanac_provider_default)"
  assert_eq "" "$out" "no installed provider should yield an empty default"

  rm -rf "$tmp"
  echo "  PASS: default-selection policy"
}

echo "=== Provider Seam Tests ==="
test_discovery_lists_present_adapters
test_availability_behind_fake_command_v
test_active_env_signals
test_menus_and_display
test_codex_argv_deep_invocation
test_claude_argv_permission_mapping
test_filters_defined_in_adapter
test_default_selection_policy

echo "All provider seam tests passed."
