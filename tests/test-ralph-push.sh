#!/usr/bin/env bash
# test-ralph-push.sh - Regression tests for Ralph's auto-push behavior

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/skills/loop/ralph-loop/scripts/ralph-git.sh"

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

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

setup_origin() {
  local tmp="$1"

  git init --bare "$tmp/origin.git" >/dev/null 2>&1
  git clone "$tmp/origin.git" "$tmp/seed" >/dev/null 2>&1

  (
    cd "$tmp/seed"
    git config user.email "test@example.com"
    git config user.name "Almanac Test"
    printf 'base\n' > README.md
    git add README.md
    git commit -m "base" >/dev/null
    git branch -M main
    git push -u origin main >/dev/null 2>&1
  )

  git --git-dir="$tmp/origin.git" symbolic-ref HEAD refs/heads/main
}

test_mismatched_upstream_pushes_to_same_named_branch() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_origin "$tmp"

  git clone "$tmp/origin.git" "$tmp/work" >/dev/null 2>&1

  (
    cd "$tmp/work"
    git config user.email "test@example.com"
    git config user.name "Almanac Test"
    git config push.default simple

    git checkout -b ralph-push-test origin/main >/dev/null 2>&1
    assert_eq "origin/main" "$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}")" "test setup should track origin/main"

    printf 'change\n' > change.txt
    git add change.txt
    git commit -m "change" >/dev/null

    if git push >/dev/null 2>&1; then
      fail "plain git push should fail with mismatched upstream under push.default=simple"
    fi

    if ! ralph_push_current_branch >/dev/null; then
      fail "ralph push should repair mismatched upstream and push"
    fi

    assert_eq "origin/ralph-push-test" "$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}")" "ralph push should set same-named upstream"
    assert_eq "$(git rev-parse HEAD)" "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/ralph-push-test)" "remote branch should point at pushed commit"
  )

  echo "  PASS: mismatched upstream pushes to same-named branch"
}

test_no_upstream_sets_same_named_branch() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_origin "$tmp"

  git clone "$tmp/origin.git" "$tmp/work" >/dev/null 2>&1

  (
    cd "$tmp/work"
    git config user.email "test@example.com"
    git config user.name "Almanac Test"

    git checkout -b no-upstream main >/dev/null 2>&1
    git branch --unset-upstream >/dev/null 2>&1 || true

    printf 'change\n' > change.txt
    git add change.txt
    git commit -m "change" >/dev/null

    if ! ralph_push_current_branch >/dev/null; then
      fail "ralph push should push branches with no upstream"
    fi

    assert_eq "origin/no-upstream" "$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}")" "ralph push should set upstream for branch without one"
    assert_eq "$(git rev-parse HEAD)" "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/no-upstream)" "remote branch should point at pushed commit"
  )

  echo "  PASS: no upstream sets same-named branch"
}

echo "=== Ralph Push Tests ==="
test_mismatched_upstream_pushes_to_same_named_branch
test_no_upstream_sets_same_named_branch
