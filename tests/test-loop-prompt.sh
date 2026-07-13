#!/usr/bin/env bash
# test-loop-prompt.sh - Loop prompt generation tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_SCRIPT="$ROOT/skills/loop/loop/scripts/prompt.sh"

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

assert_lacks() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file"; then
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
  # Define the npm `test` script so the shared detector emits it (a package.json
  # without the script is no longer assumed to have it — see lib/feedback.sh).
  printf '%s\n' '{"scripts":{"test":"node --test"}}' > "$tmp/package.json"
  touch "$tmp/tests/test-skills.sh"
  touch "$tmp/tests/test-structure.sh"

  (cd "$tmp" && bash "$PROMPT_SCRIPT" demo >/dev/null)

  prompt="$tmp/docs/plans/demo/prompt.md"
  [ -f "$prompt" ] || fail "prompt should be generated"
  assert_contains "$prompt" "Pull @docs/plans/demo/prd.md into your context." "prompt should reference selected PRD"
  assert_contains "$prompt" "- \`npm run test\` to run npm tests" "prompt should include package feedback from shared detector"
  assert_contains "$prompt" "- \`bash tests/test-skills.sh\` to validate skill format/content" "prompt should include skill feedback from shared detector"
  assert_contains "$prompt" "- \`bash tests/test-structure.sh\` to validate repo layout" "prompt should include structure feedback from shared detector"
  assert_contains "$prompt" 'status: ready-for-agent|ready-for-human' "prompt should describe readiness-based local tickets"
  assert_contains "$prompt" 'legacy tickets may have no readiness label' "prompt should preserve legacy GitHub queues"
  assert_contains "$prompt" 'Follow the `implement` skill for this one selected task' "prompt should delegate one-ticket execution to implement"
  echo "  PASS: generates prompt with shared feedback commands"
}

# Loop's feedback-loop DETECTION uses the shared runner (#66 crit 2): prompt.sh
# injects the FEEDBACK LOOPS list via almanac_loop_feedback_markdown ->
# almanac_loop_feedback_commands (lib/feedback.sh), and once.sh/afk.sh carry NO
# private detection. This pins that the list is marker-DRIVEN by the shared
# detector, not a hardcoded loop list: a project whose only marker is Cargo.toml
# must yield the shared detector's Rust commands and none of the npm commands a
# fixed list would always print. (Loop does not EXECUTE feedback loops — the
# in-iteration agent runs them per the prompt — so the shared executor
# almanac_loop_feedback_run is genuinely N/A for loop; detection is the
# criterion's subject and it is shared.)
test_prompt_feedback_detection_is_marker_driven_by_shared_runner() {
  local tmp prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' '# Demo PRD' > "$tmp/docs/plans/demo/prd.md"
  # Only a Rust marker — no package.json, no repo test scripts.
  printf '%s\n' '[package]' > "$tmp/Cargo.toml"

  (cd "$tmp" && bash "$PROMPT_SCRIPT" demo >/dev/null)

  prompt="$tmp/docs/plans/demo/prompt.md"
  [ -f "$prompt" ] || fail "prompt should be generated"
  assert_contains "$prompt" "- \`cargo test\` to run Rust tests" "Cargo.toml marker should yield the shared detector's cargo test"
  assert_contains "$prompt" "- \`cargo check\` to run Rust compiler checks" "Cargo.toml marker should yield the shared detector's cargo check"
  assert_lacks "$prompt" "npm run test" "feedback list must be marker-driven by the shared detector, not a hardcoded npm list"
  echo "  PASS: prompt feedback detection is marker-driven by the shared runner"
}

echo "=== Loop Prompt Tests ==="
test_generates_prompt_with_shared_feedback_commands
test_prompt_feedback_detection_is_marker_driven_by_shared_runner
