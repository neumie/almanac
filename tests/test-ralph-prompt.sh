#!/usr/bin/env bash
# test-ralph-prompt.sh - Ralph prompt generation tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_SCRIPT="$ROOT/skills/loop/ralph-loop/scripts/prompt.sh"

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
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

test_generates_prompt_with_shared_feedback_commands() {
  local tmp prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/docs/plans/demo" "$tmp/tests"
  printf '%s\n' '# Demo PRD' > "$tmp/docs/plans/demo/prd.md"
  touch "$tmp/package.json"
  touch "$tmp/tests/test-skills.sh"
  touch "$tmp/tests/test-structure.sh"

  (cd "$tmp" && bash "$PROMPT_SCRIPT" demo >/dev/null)

  prompt="$tmp/docs/plans/demo/prompt.md"
  [ -f "$prompt" ] || fail "prompt should be generated"
  assert_contains "$prompt" "Pull @docs/plans/demo/prd.md into your context." "prompt should reference selected PRD"
  assert_contains "$prompt" "- \`npm run test\` to run npm tests" "prompt should include package feedback from shared detector"
  assert_contains "$prompt" "- \`bash tests/test-skills.sh\` to validate skill format/content" "prompt should include skill feedback from shared detector"
  assert_contains "$prompt" "- \`bash tests/test-structure.sh\` to validate repo layout" "prompt should include structure feedback from shared detector"
  echo "  PASS: generates prompt with shared feedback commands"
}

echo "=== Ralph Prompt Tests ==="
test_generates_prompt_with_shared_feedback_commands
