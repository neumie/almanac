#!/usr/bin/env bash
# test-cli.sh — black-box tests for the almanac CLI dispatch + command contract.
#
# Drives the real bin/almanac the way a user does, and lints each cmd/*.sh
# against the conventions that keep the CLI consistent. These turn the "proper
# CLI" rules into enforced invariants: a new command that skips the metadata
# header, strict mode, a lib source, or a stdout --help fails here.
#
# Conventions enforced (see AGENTS.md "CLI commands"):
#   - dispatch is registry-driven (a command is valid iff cmd/<name>.sh exists)
#   - unknown / path-traversal-shaped commands are rejected with exit 1
#   - `almanac help` lists every registered command (generated, never hand-kept)
#   - every command declares `# summary:`, `# usage:`, `# group:` headers
#   - every command sets `set -euo pipefail` and sources a lib/ file
#   - `almanac <cmd> --help` exits 0 and prints usage to stdout

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ALMANAC_HOME="$ROOT"   # the in-process registry helpers resolve cmd/ from it
ALMANAC_BIN="$ROOT/bin/almanac"
source "$ROOT/lib/core.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
failf() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

assert_contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *)      failf "$3 (missing '$2')" ;;
  esac
}

echo "=== CLI Dispatch Tests ==="

# almanac_command_meta must read its own "$1", not a caller's `name` var. On
# bash 3.2 a single `local name=… file=…$name…` resolves the caller's name —
# this calls it with a conflicting `name` in scope to catch that regression.
meta_isolation_check() {
  local name="bogus"   # deliberately wrong; helper must ignore this
  local got
  got="$(almanac_command_meta converge summary)"
  case "$got" in
    *converg*) pass "command_meta ignores caller's name var" ;;
    *)         failf "command_meta leaked caller name: got '$got' (want converge's summary)" ;;
  esac
}
meta_isolation_check

# Registry is non-empty and lists the commands we expect to exist.
COMMANDS="$(almanac_list_commands)"
[ -n "$COMMANDS" ] && pass "registry lists commands" || failf "registry is empty"
for expected in help install uninstall list update sync doctor loop converge hub; do
  case $'\n'"$COMMANDS"$'\n' in
    *$'\n'"$expected"$'\n'*) pass "registry includes '$expected'" ;;
    *)                       failf "registry missing '$expected'" ;;
  esac
done

# Unknown command → error + exit 1.
out="$("$ALMANAC_BIN" definitely-not-a-command 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] && pass "unknown command exits 1" || failf "unknown command exit was $rc (want 1)"
assert_contains "$out" "Unknown command" "unknown command names the error"

# A path-traversal-shaped command must be rejected by the dispatch guard, never
# sourced — even if such a path existed.
out="$("$ALMANAC_BIN" ../../etc/passwd 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] && pass "path-traversal command rejected" || failf "path-traversal exit was $rc (want 1)"

# Bare almanac, non-interactive, prints help — must not block on / open the hub.
out="$("$ALMANAC_BIN" </dev/null 2>&1)"
assert_contains "$out" "Usage: almanac" "bare almanac (non-tty) prints help"

# Top-level -h/--help is an alias for `almanac help` (stdout, exit 0).
for flag in -h --help; do
  out="$("$ALMANAC_BIN" "$flag" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    pass "top-level '$flag' prints help to stdout (exit 0)"
  else
    failf "top-level '$flag' rc=$rc (want 0 with stdout)"
  fi
done

# `almanac help` is generated from the registry — every command appears.
help_out="$("$ALMANAC_BIN" help 2>&1)"
while IFS= read -r name; do
  case "$help_out" in
    *"$name"*) pass "help lists '$name'" ;;
    *)         failf "help is missing '$name'" ;;
  esac
done <<< "$COMMANDS"

# Section headers prove the grouping renders.
for section in "Loops:" "Providers:" "Maintenance:"; do
  assert_contains "$help_out" "$section" "help shows section '$section'"
done

echo ""
echo "=== Command Contract Tests ==="

while IFS= read -r name; do
  file="$ROOT/cmd/$name.sh"

  # Self-describing metadata headers (read by help generation + this test).
  for field in summary usage group; do
    if [ -n "$(almanac_command_meta "$name" "$field" || true)" ]; then
      pass "$name declares '# $field:'"
    else
      failf "$name missing '# $field:' header"
    fi
  done

  # Strict mode + a lib source = self-contained, robust under direct execution.
  grep -q 'set -euo pipefail' "$file" \
    && pass "$name sets strict mode" \
    || failf "$name missing 'set -euo pipefail'"
  grep -Eq 'source .*/lib/' "$file" \
    && pass "$name sources a lib/ file" \
    || failf "$name sources no lib/ file"

  # --help exits 0 and prints usage to stdout (not stderr, not a side effect).
  help_stdout="$("$ALMANAC_BIN" "$name" --help 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$help_stdout" ]; then
    pass "$name --help exits 0 with stdout"
  else
    failf "$name --help rc=$rc stdout_empty=$([ -z "$help_stdout" ] && echo yes || echo no)"
  fi
done <<< "$COMMANDS"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
