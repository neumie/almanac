#!/usr/bin/env bash
# test-home-resolve.sh — Unit tests for almanac_resolve_home (lib/core.sh), the
# canonical ALMANAC_HOME resolver mirrored by every entry point's inline
# bootstrap. Pins: prefer-exported, depth climbing, and symlink-safety (the
# install dir-symlink and a plain checkout both resolve to the real repo).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/core.sh"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0
fail() { echo "  FAIL: $1" >&2; exit 1; }
assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
  echo "  PASS: $3"
  PASS=$((PASS + 1))
}

echo "=== Home Resolution Tests ==="

# A real repo-shaped tree plus an install-style directory symlink pointing into
# it. pwd -P collapses macOS /var -> /private/var, so the expected root is itself
# resolved physically.
mkdir -p "$TMP/real/skills/loop/loop/scripts"
mkdir -p "$TMP/real/bin"
ln -s "$TMP/real/skills/loop/loop" "$TMP/linkdir"
REAL_ROOT="$(cd -P "$TMP/real" && pwd -P)"

# Resolution cases must run with ALMANAC_HOME unset so the prefer-exported branch
# doesn't short-circuit.
unset ALMANAC_HOME

# 1. Plain checkout: a skill script at depth 4 resolves to the real root.
got="$(almanac_resolve_home "$TMP/real/skills/loop/loop/scripts/once.sh" 4)"
assert_eq "$REAL_ROOT" "$got" "repo checkout resolves to real root (depth 4)"

# 2. Install dir-symlink: same script reached via the symlinked path resolves to
#    the real repo, not the symlink's lexical parent.
got="$(almanac_resolve_home "$TMP/linkdir/scripts/once.sh" 4)"
assert_eq "$REAL_ROOT" "$got" "install dir-symlink resolves to real root (depth 4)"

# 3. bin/ entry point is depth 1 below the root.
got="$(almanac_resolve_home "$TMP/real/bin/almanac" 1)"
assert_eq "$REAL_ROOT" "$got" "bin/ entry point resolves to real root (depth 1)"

# 4. Default depth of 0 yields the script's own physical directory.
got="$(almanac_resolve_home "$TMP/linkdir/scripts/once.sh")"
assert_eq "$REAL_ROOT/skills/loop/loop/scripts" "$got" "depth 0 yields own dir"

# 5. An already-exported ALMANAC_HOME is preferred verbatim (no self-resolution).
got="$(ALMANAC_HOME=/exported/override almanac_resolve_home "$TMP/linkdir/scripts/once.sh" 4)"
assert_eq "/exported/override" "$got" "prefers an exported ALMANAC_HOME"

# 6. Drift guard: the inline bootstrap snippet (the literal form entry points
#    use) must agree with the function for the symlink case.
src="$TMP/linkdir/scripts/once.sh"
snippet="$(cd -P "$(dirname "$src")/../../../.." && pwd -P)"
assert_eq "$(almanac_resolve_home "$src" 4)" "$snippet" "inline snippet matches resolver"

echo ""
echo "Results: $PASS passed"
