#!/usr/bin/env bash
# test-ralph-run-registry.sh - Ralph launcher run registry tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ONCE_SCRIPT="$ROOT/skills/loop/ralph-loop/scripts/once.sh"
AFK_SCRIPT="$ROOT/skills/loop/ralph-loop/scripts/afk.sh"

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_file_lacks() {
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

write_fake_codex() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
exit_code="${FAKE_CODEX_EXIT:-0}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
      ;;
  esac
  shift || true
done

[ -n "$result_file" ] && printf '%s\n' "fake codex complete" > "$result_file"
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_message","message":"fake codex event"}}'
exit "$exit_code"
EOF
  chmod +x "$fakebin/codex"
}

# Fake codex that records its argv (to $FAKE_CODEX_ARGV, one arg per line),
# writes a diagnostic to stderr (to exercise the seam's merge-stderr 2>&1 log
# capture), writes a final message to --output-last-message, and emits one
# item.completed/agent_message line the codex stream filter matches. Exit code
# overridable via $FAKE_CODEX_EXIT.
write_fake_codex_recording() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ -n "${FAKE_CODEX_ARGV:-}" ] && printf '%s\n' "$@" > "$FAKE_CODEX_ARGV"
result_file=""
exit_code="${FAKE_CODEX_EXIT:-0}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
      ;;
  esac
  shift || true
done

printf '%s\n' "FAKE_CODEX_STDERR_LINE" >&2
[ -n "$result_file" ] && printf '%s\n' "fake codex final" > "$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"FAKE_CODEX_STREAM_TEXT"}}'
exit "$exit_code"
EOF
  chmod +x "$fakebin/codex"
}

# Fake claude that records its argv (to $FAKE_CLAUDE_ARGV, one arg per line) and
# emits a minimal stream-json event sequence: an init model line, one assistant
# text block, and a result. Exit code overridable via $FAKE_CLAUDE_EXIT.
write_fake_claude() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ -n "${FAKE_CLAUDE_ARGV:-}" ] && printf '%s\n' "$@" > "$FAKE_CLAUDE_ARGV"
exit_code="${FAKE_CLAUDE_EXIT:-0}"

printf '%s\n' '{"type":"system","subtype":"init","model":"fake-claude-model"}'
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"FAKE_CLAUDE_ASSISTANT_TEXT"}]}}'
printf '%s\n' '{"type":"result","result":"fake claude final"}'
exit "$exit_code"
EOF
  chmod +x "$fakebin/claude"
}

# Fake codex for the overseer routing tests. It distinguishes the iteration agent
# (sandbox danger-full-access) from the overseer judge call (sandbox read-only,
# the seam's read-only mapping). The overseer invocation records its argv to
# $FAKE_OVERSEER_ARGV, signals it ran by touching $OVERSEER_FIRED, and writes a
# benign low/none verdict; the iteration agent BLOCKS until the overseer has
# fired (bounded fallback) so the overseer is guaranteed to run — and route
# through the seam — before the single-iteration loop exits.
write_fake_codex_overseer() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
sandbox=""
args=("$@")
n=${#args[@]}
i=0
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    --output-last-message) i=$((i+1)); result_file="${args[$i]:-}" ;;
    --sandbox)             i=$((i+1)); sandbox="${args[$i]:-}" ;;
  esac
  i=$((i+1))
done

if [ "$sandbox" = "read-only" ]; then
  [ -n "${FAKE_OVERSEER_ARGV:-}" ] && printf '%s\n' "$@" > "$FAKE_OVERSEER_ARGV"
  [ -n "${OVERSEER_FIRED:-}" ] && touch "$OVERSEER_FIRED"
  [ -n "$result_file" ] && printf 'DRIFT_LEVEL: low\nREASON: fine\nSTEER: none\n' > "$result_file"
  printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"overseer ok"}}'
else
  if [ -n "${OVERSEER_FIRED:-}" ]; then
    j=0
    while [ "$j" -lt 100 ] && [ ! -f "$OVERSEER_FIRED" ]; do sleep 0.1; j=$((j+1)); done
  fi
  [ -n "$result_file" ] && printf '%s\n' "iteration progress (no promise)" > "$result_file"
  printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"iteration ok"}}'
fi
exit 0
EOF
  chmod +x "$fakebin/codex"
}

# Fake claude for the overseer routing tests. afk's iteration agent runs with the
# `default` sandbox (no --permission-mode), while the overseer's read-only judge
# call maps to --permission-mode plan, so the fake branches on that flag. The
# overseer invocation records its argv to $FAKE_OVERSEER_ARGV, touches
# $OVERSEER_FIRED, and emits a benign low/none verdict in its result event; the
# iteration agent blocks until the overseer has fired, then emits a normal stream.
write_fake_claude_overseer() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

perm=""
args=("$@")
n=${#args[@]}
i=0
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    --permission-mode) i=$((i+1)); perm="${args[$i]:-}" ;;
  esac
  i=$((i+1))
done

if [ "$perm" = "plan" ]; then
  [ -n "${FAKE_OVERSEER_ARGV:-}" ] && printf '%s\n' "$@" > "$FAKE_OVERSEER_ARGV"
  [ -n "${OVERSEER_FIRED:-}" ] && touch "$OVERSEER_FIRED"
  printf '%s\n' '{"type":"result","result":"DRIFT_LEVEL: low\nREASON: fine\nSTEER: none"}'
else
  if [ -n "${OVERSEER_FIRED:-}" ]; then
    j=0
    while [ "$j" -lt 100 ] && [ ! -f "$OVERSEER_FIRED" ]; do sleep 0.1; j=$((j+1)); done
  fi
  printf '%s\n' '{"type":"system","subtype":"init","model":"fake-claude-model"}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"iteration ok"}]}}'
  printf '%s\n' '{"type":"result","result":"iteration progress (no promise)"}'
fi
exit 0
EOF
  chmod +x "$fakebin/claude"
}

test_once_registers_and_marks_run_done() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex bash "$ONCE_SCRIPT" demo >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "ralph once should write run index"
  assert_file_contains "$index_file" $'id\ttype\ttarget\tpid\tstatus_file\tstarted_at\tstatus' "index should include header"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record ralph PRD target"
  assert_file_contains "$index_file" $'done' "index should mark run done"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph once should write status file"
  assert_file_contains "$status_file" $'type\tralph' "status should record ralph type"
  assert_file_contains "$status_file" $'target\tdocs/plans/demo/prd.md' "status should record PRD target"
  assert_file_contains "$status_file" $'status\tdone' "status should mark run done"
  echo "  PASS: once registers and marks run done"
}

test_once_marks_run_failed_on_provider_error() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex FAKE_CODEX_EXIT=7 bash "$ONCE_SCRIPT" demo >/dev/null 2>&1); then
    fail "ralph once should fail when provider exits nonzero"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed ralph once should still write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record failed ralph PRD target"
  assert_file_contains "$index_file" $'failed' "index should mark run failed"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "failed ralph once should still write status file"
  assert_file_contains "$status_file" $'status\tfailed' "status should mark run failed"
  echo "  PASS: once marks run failed on provider error"
}

test_afk_registers_and_marks_run_done() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 bash "$AFK_SCRIPT" demo 1 >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "ralph afk should write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record afk PRD target"
  assert_file_contains "$index_file" $'done' "index should mark afk run done"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph afk should write status file"
  assert_file_contains "$status_file" $'type\tralph' "status should record ralph type"
  assert_file_contains "$status_file" $'target\tdocs/plans/demo/prd.md' "status should record PRD target"
  assert_file_contains "$status_file" $'status\tdone' "status should mark afk run done"
  echo "  PASS: afk registers and marks run done"
}

test_afk_marks_run_failed_on_provider_error() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 FAKE_CODEX_EXIT=9 bash "$AFK_SCRIPT" demo 1 >/dev/null 2>&1); then
    fail "ralph afk should fail when provider exits nonzero"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed ralph afk should still write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record failed afk PRD target"
  assert_file_contains "$index_file" $'failed' "index should mark afk run failed"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "failed ralph afk should still write status file"
  assert_file_contains "$status_file" $'status\tfailed' "status should mark afk run failed"
  echo "  PASS: afk marks run failed on provider error"
}

test_once_emits_live_run_progress_contract() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex bash "$ONCE_SCRIPT" demo >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph once should write status file"
  assert_file_contains "$status_file" $'round\t1' "once should record the live iteration as round in the run-status contract"
  assert_file_contains "$status_file" $'summary\tprovider=codex iteration=1/1' "once should record the live iteration summary in the run-status contract"
  echo "  PASS: once emits the live run-status progress contract"
}

test_afk_emits_live_run_progress_contract() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 bash "$AFK_SCRIPT" demo 1 >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph afk should write status file"
  assert_file_contains "$status_file" $'round\t1' "afk should record the live iteration as round in the run-status contract"
  assert_file_contains "$status_file" $'summary\tprovider=codex iteration=1/1' "afk should record the live iteration summary in the run-status contract"
  echo "  PASS: afk emits the live run-status progress contract"
}

# once.sh routes its claude provider invocation through the shared agent_run
# seam (#66 — ralph migration). The seam must build once.sh's exact claude
# invocation (acceptEdits, stream-json) honoring RALPH_MODEL/RALPH_EFFORT and
# stream the live assistant text to stdout byte-for-byte as before.
test_once_claude_routes_provider_invocation_through_seam() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once claude seam routing (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/claude-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_claude "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=claude \
    RALPH_MODEL=fake-model RALPH_EFFORT=high FAKE_CLAUDE_ARGV="$argv_file" \
    bash "$ONCE_SCRIPT" demo)

  # Live assistant stream reaches stdout via the seam's claude jq filter.
  printf '%s' "$out" | grep -Fq "Claude model: fake-claude-model" \
    || fail "once claude should stream the init model line through the seam"
  printf '%s' "$out" | grep -Fq "FAKE_CLAUDE_ASSISTANT_TEXT" \
    || fail "once claude should stream the assistant text through the seam"

  # The seam built once.sh's claude invocation, honoring model + effort.
  [ -f "$argv_file" ] || fail "fake claude should have been invoked"
  assert_file_contains "$argv_file" "--output-format" "claude invocation should request a structured output format"
  assert_file_contains "$argv_file" "stream-json" "claude invocation should request stream-json"
  assert_file_contains "$argv_file" "--permission-mode" "claude invocation should set a permission mode"
  assert_file_contains "$argv_file" "acceptEdits" "once claude permission mode should be acceptEdits"
  assert_file_contains "$argv_file" "fake-model" "claude invocation should honor RALPH_MODEL"
  assert_file_contains "$argv_file" "high" "claude invocation should honor RALPH_EFFORT"
  echo "  PASS: once routes claude provider invocation through the shared seam"
}

# A failing claude provider must propagate through the seam's pipe (PIPESTATUS)
# so once.sh exits nonzero and the run is marked failed.
test_once_claude_propagates_provider_failure() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once claude failure propagation (jq not available)"
    return 0
  fi

  local tmp fakebin index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_claude "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=claude FAKE_CLAUDE_EXIT=5 \
    bash "$ONCE_SCRIPT" demo >/dev/null 2>&1); then
    fail "once should fail when the claude provider exits nonzero (seam PIPESTATUS)"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed once claude should still write run index"
  assert_file_contains "$index_file" $'failed' "failed once claude should mark run failed"
  echo "  PASS: once claude propagates provider failure through the seam"
}

# once.sh routes its default (non-verbose) codex provider invocation through the
# shared agent_run seam (#66 — ralph migration). The seam must build once.sh's
# exact codex invocation (--json, --output-last-message, danger-full-access)
# honoring RALPH_MODEL/RALPH_EFFORT, stream the live agent-message text, capture
# the raw stream AND merged stderr (2>&1) to the session log, and once.sh prints
# the final result — byte-for-byte as the old inline pipe did.
test_once_codex_routes_provider_invocation_through_seam() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once codex seam routing (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file codex_log out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex \
    RALPH_MODEL=fake-model RALPH_EFFORT=high FAKE_CODEX_ARGV="$argv_file" \
    bash "$ONCE_SCRIPT" demo)

  # Live agent-message stream reaches stdout via the seam's codex jq filter.
  printf '%s' "$out" | grep -Fq "FAKE_CODEX_STREAM_TEXT" \
    || fail "once codex should stream the agent-message text through the seam"
  # once.sh prints the seam's captured final result.
  printf '%s' "$out" | grep -Fq "fake codex final" \
    || fail "once codex should print the seam's final result"

  # The seam built once.sh's codex invocation, honoring model + effort.
  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_contains "$argv_file" "--json" "codex invocation should request json events"
  assert_file_contains "$argv_file" "--output-last-message" "codex invocation should capture the final message"
  assert_file_contains "$argv_file" "--sandbox" "codex invocation should set a sandbox"
  assert_file_contains "$argv_file" "danger-full-access" "once codex sandbox should be danger-full-access"
  assert_file_contains "$argv_file" "fake-model" "codex invocation should honor RALPH_MODEL"
  assert_file_contains "$argv_file" "high" "codex invocation should honor RALPH_EFFORT"

  # The session log captures the raw stream AND merged stderr (2>&1 preserved).
  codex_log="$tmp/docs/plans/demo/ralph-codex-once.log"
  [ -f "$codex_log" ] || fail "once codex should write the session log via the seam"
  assert_file_contains "$codex_log" "FAKE_CODEX_STREAM_TEXT" "session log should capture the raw codex event stream"
  assert_file_contains "$codex_log" "FAKE_CODEX_STDERR_LINE" "session log should capture codex stderr (merge-stderr 2>&1)"
  echo "  PASS: once routes codex provider invocation through the shared seam"
}

# A failing codex provider must propagate through the seam so once.sh prints the
# failure tail and exits nonzero, marking the run failed.
test_once_codex_propagates_provider_failure() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once codex failure propagation (jq not available)"
    return 0
  fi

  local tmp fakebin index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex FAKE_CODEX_EXIT=5 \
    bash "$ONCE_SCRIPT" demo >/dev/null 2>&1); then
    fail "once should fail when the codex provider exits nonzero (seam PIPESTATUS)"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed once codex should still write run index"
  assert_file_contains "$index_file" $'failed' "failed once codex should mark run failed"
  echo "  PASS: once codex propagates provider failure through the seam"
}

# afk.sh routes its default (non-verbose) codex provider invocation through the
# shared agent_run seam (#66 — ralph migration). The seam must build afk's exact
# codex invocation (--json, --output-last-message, danger-full-access) honoring
# RALPH_MODEL/RALPH_EFFORT, stream the live agent-message text, capture the raw
# stream AND merged stderr (2>&1) to the per-iteration session log, and afk both
# prints the final result and reads it back for <promise> extraction — byte-for-
# byte as the old inline pipe did.
test_afk_codex_routes_provider_invocation_through_seam() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: afk codex seam routing (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file codex_log out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 \
    RALPH_MODEL=fake-model RALPH_EFFORT=high FAKE_CODEX_ARGV="$argv_file" \
    bash "$AFK_SCRIPT" demo 1)

  # Live agent-message stream reaches stdout via the seam's codex jq filter.
  printf '%s' "$out" | grep -Fq "FAKE_CODEX_STREAM_TEXT" \
    || fail "afk codex should stream the agent-message text through the seam"
  # afk prints the seam's captured final result.
  printf '%s' "$out" | grep -Fq "fake codex final" \
    || fail "afk codex should print the seam's final result"

  # The seam built afk's codex invocation, honoring model + effort.
  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_contains "$argv_file" "--json" "codex invocation should request json events"
  assert_file_contains "$argv_file" "--output-last-message" "codex invocation should capture the final message"
  assert_file_contains "$argv_file" "--sandbox" "codex invocation should set a sandbox"
  assert_file_contains "$argv_file" "danger-full-access" "afk codex sandbox should be danger-full-access"
  assert_file_contains "$argv_file" "fake-model" "codex invocation should honor RALPH_MODEL"
  assert_file_contains "$argv_file" "high" "codex invocation should honor RALPH_EFFORT"

  # The per-iteration session log captures the raw stream AND merged stderr.
  codex_log="$tmp/docs/plans/demo/ralph-codex-iteration-1.log"
  [ -f "$codex_log" ] || fail "afk codex should write the session log via the seam"
  assert_file_contains "$codex_log" "FAKE_CODEX_STREAM_TEXT" "session log should capture the raw codex event stream"
  assert_file_contains "$codex_log" "FAKE_CODEX_STDERR_LINE" "session log should capture codex stderr (merge-stderr 2>&1)"
  echo "  PASS: afk routes codex provider invocation through the shared seam"
}

# afk.sh routes its claude iteration path through the shared agent_run seam (#66
# — ralph migration). Unlike once.sh, afk's iteration agent has NEVER set a
# permission mode, so the seam must build afk's claude invocation WITHOUT
# --permission-mode (via the `default` sandbox sentinel), still honoring
# RALPH_MODEL/RALPH_EFFORT, stream the live assistant text to stdout, and afk
# reads the seam's result back for <promise> extraction.
test_afk_claude_routes_provider_invocation_through_seam() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: afk claude seam routing (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/claude-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_claude "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=claude RALPH_NO_OVERSEE=1 \
    RALPH_MODEL=fake-model RALPH_EFFORT=high FAKE_CLAUDE_ARGV="$argv_file" \
    bash "$AFK_SCRIPT" demo 1)

  # Live assistant stream reaches stdout via the seam's claude jq filter.
  printf '%s' "$out" | grep -Fq "Claude model: fake-claude-model" \
    || fail "afk claude should stream the init model line through the seam"
  printf '%s' "$out" | grep -Fq "FAKE_CLAUDE_ASSISTANT_TEXT" \
    || fail "afk claude should stream the assistant text through the seam"

  # The seam built afk's claude invocation, honoring model + effort.
  [ -f "$argv_file" ] || fail "fake claude should have been invoked"
  assert_file_contains "$argv_file" "--output-format" "claude invocation should request a structured output format"
  assert_file_contains "$argv_file" "stream-json" "claude invocation should request stream-json"
  assert_file_contains "$argv_file" "fake-model" "claude invocation should honor RALPH_MODEL"
  assert_file_contains "$argv_file" "high" "claude invocation should honor RALPH_EFFORT"

  # Crucially, afk's claude path must NOT set --permission-mode — its iteration
  # agent has never set one (the `default` sandbox sentinel preserves that).
  if grep -Fq -- "--permission-mode" "$argv_file"; then
    fail "afk claude must NOT set --permission-mode (default sandbox sentinel preserves afk's behavior)"
  fi
  echo "  PASS: afk routes claude provider invocation through the shared seam"
}

# A failing claude provider must propagate through the seam's pipe (PIPESTATUS)
# so afk exits nonzero and the run is marked failed. This is the genuine behavior
# change of routing afk's claude through the seam: the old inline pipe had no
# `pipefail`, so a claude failure was swallowed (jq exited 0) and the run was
# falsely marked done — red against the old pipe, green via the seam.
test_afk_claude_propagates_provider_failure() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: afk claude failure propagation (jq not available)"
    return 0
  fi

  local tmp fakebin index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_claude "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=claude RALPH_NO_OVERSEE=1 \
    FAKE_CLAUDE_EXIT=5 bash "$AFK_SCRIPT" demo 1 >/dev/null 2>&1); then
    fail "afk should fail when the claude provider exits nonzero (seam PIPESTATUS)"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed afk claude should still write run index"
  assert_file_contains "$index_file" $'failed' "failed afk claude should mark run failed"
  echo "  PASS: afk claude propagates provider failure through the seam"
}

# RALPH_CODEX_VERBOSE=1 routes once.sh's codex through the shared agent_run seam's
# raw passthrough mode (#66 crit 6 — no inline provider exec remains). Raw mode
# runs codex WITHOUT --json so its native output passes straight through, while
# still honoring model/effort/sandbox and capturing the final message. No jq is
# needed, since raw mode never filters.
test_once_codex_verbose_routes_through_seam_raw_mode() {
  local tmp fakebin argv_file out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_CODEX_VERBOSE=1 \
    RALPH_MODEL=fake-model RALPH_EFFORT=high FAKE_CODEX_ARGV="$argv_file" \
    bash "$ONCE_SCRIPT" demo)

  # The seam built once.sh's verbose codex invocation in raw mode: NO --json,
  # honoring model/effort + sandbox, still capturing the final message.
  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_lacks "$argv_file" "--json" "verbose codex should run raw (no --json) through the seam"
  assert_file_contains "$argv_file" "--output-last-message" "verbose codex should still capture the final message"
  assert_file_contains "$argv_file" "danger-full-access" "verbose codex sandbox should be danger-full-access"
  assert_file_contains "$argv_file" "fake-model" "verbose codex should honor RALPH_MODEL via the seam"
  assert_file_contains "$argv_file" "high" "verbose codex should honor RALPH_EFFORT via the seam"

  # Native codex output passes straight through (the recording fake prints a raw
  # JSON event line that raw mode does not filter).
  printf '%s' "$out" | grep -Fq "FAKE_CODEX_STREAM_TEXT" \
    || fail "verbose codex native output should reach stdout unfiltered"
  echo "  PASS: once routes verbose codex through the shared seam raw mode"
}

# RALPH_CODEX_VERBOSE=1 routes afk.sh's codex through the seam's raw passthrough
# mode too, and afk reads the seam's captured result back for <promise>
# extraction (the result lands in $tmpfile via --output-last-message).
test_afk_codex_verbose_routes_through_seam_raw_mode() {
  local tmp fakebin argv_file out
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  out=$(cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 \
    RALPH_CODEX_VERBOSE=1 RALPH_MODEL=fake-model RALPH_EFFORT=high \
    FAKE_CODEX_ARGV="$argv_file" bash "$AFK_SCRIPT" demo 1)

  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_lacks "$argv_file" "--json" "verbose codex should run raw (no --json) through the seam"
  assert_file_contains "$argv_file" "--output-last-message" "verbose codex should still capture the final message"
  assert_file_contains "$argv_file" "danger-full-access" "verbose codex sandbox should be danger-full-access"
  assert_file_contains "$argv_file" "fake-model" "verbose codex should honor RALPH_MODEL via the seam"
  assert_file_contains "$argv_file" "high" "verbose codex should honor RALPH_EFFORT via the seam"

  # Native codex output passes straight through unfiltered.
  printf '%s' "$out" | grep -Fq "FAKE_CODEX_STREAM_TEXT" \
    || fail "verbose codex native output should reach stdout unfiltered"
  echo "  PASS: afk routes verbose codex through the shared seam raw mode"
}

# once.sh resolves its iteration-agent model/effort through the shared role-config
# helper (almanac_loop_role_field), so the per-role RALPH_AGENT_* keys override the
# bare RALPH_* keys (#66 crit 3 — ralph uses the shared role config). The seam's
# codex invocation must carry the AGENT-role model/effort, not the bare-env ones.
test_once_resolves_agent_model_via_shared_role_config() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once agent role-config (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex \
    RALPH_AGENT_MODEL=agentrolemodel RALPH_MODEL=baseenvmodel \
    RALPH_AGENT_EFFORT=agentroleeffort RALPH_EFFORT=baseenveffort \
    FAKE_CODEX_ARGV="$argv_file" bash "$ONCE_SCRIPT" demo >/dev/null)

  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_contains "$argv_file" "agentrolemodel" "once should resolve RALPH_AGENT_MODEL over RALPH_MODEL via shared role config"
  assert_file_lacks "$argv_file" "baseenvmodel" "once should not pass RALPH_MODEL when RALPH_AGENT_MODEL is set"
  assert_file_contains "$argv_file" "agentroleeffort" "once should resolve RALPH_AGENT_EFFORT over RALPH_EFFORT via shared role config"
  assert_file_lacks "$argv_file" "baseenveffort" "once should not pass RALPH_EFFORT when RALPH_AGENT_EFFORT is set"
  echo "  PASS: once resolves the agent model/effort via the shared role config"
}

# afk.sh resolves its iteration-agent model/effort through the shared role-config
# helper too, so RALPH_AGENT_* overrides RALPH_* (#66 crit 3).
test_afk_resolves_agent_model_via_shared_role_config() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: afk agent role-config (jq not available)"
    return 0
  fi

  local tmp fakebin argv_file
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  argv_file="$tmp/codex-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 \
    RALPH_AGENT_MODEL=agentrolemodel RALPH_MODEL=baseenvmodel \
    RALPH_AGENT_EFFORT=agentroleeffort RALPH_EFFORT=baseenveffort \
    FAKE_CODEX_ARGV="$argv_file" bash "$AFK_SCRIPT" demo 1 >/dev/null)

  [ -f "$argv_file" ] || fail "fake codex should have been invoked"
  assert_file_contains "$argv_file" "agentrolemodel" "afk should resolve RALPH_AGENT_MODEL over RALPH_MODEL via shared role config"
  assert_file_lacks "$argv_file" "baseenvmodel" "afk should not pass RALPH_MODEL when RALPH_AGENT_MODEL is set"
  assert_file_contains "$argv_file" "agentroleeffort" "afk should resolve RALPH_AGENT_EFFORT over RALPH_EFFORT via shared role config"
  assert_file_lacks "$argv_file" "baseenveffort" "afk should not pass RALPH_EFFORT when RALPH_AGENT_EFFORT is set"
  echo "  PASS: afk resolves the agent model/effort via the shared role config"
}

# once.sh resolves its iteration-agent provider through the shared role-config
# helper, so RALPH_AGENT_PROVIDER selects the provider over auto-detection (#66
# crit 3). With both providers on PATH, auto-detect would pick claude; the
# AGENT-role provider key must win and select codex instead.
test_once_resolves_agent_provider_via_shared_role_config() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: once agent provider role-config (jq not available)"
    return 0
  fi

  local tmp fakebin codex_argv claude_argv
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  codex_argv="$tmp/codex-argv.txt"
  claude_argv="$tmp/claude-argv.txt"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_recording "$fakebin"
  write_fake_claude "$fakebin"

  # No RALPH_PROVIDER — only the AGENT-role key. Both CLIs are on PATH, so the
  # bare auto-detection would resolve claude; role config must select codex.
  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_AGENT_PROVIDER=codex \
    FAKE_CODEX_ARGV="$codex_argv" FAKE_CLAUDE_ARGV="$claude_argv" \
    bash "$ONCE_SCRIPT" demo >/dev/null)

  [ -f "$codex_argv" ] || fail "RALPH_AGENT_PROVIDER=codex should select the codex provider via shared role config"
  [ -f "$claude_argv" ] && fail "RALPH_AGENT_PROVIDER=codex must not fall through to claude auto-detection"
  assert_file_contains "$codex_argv" "--json" "the selected codex provider should run through the seam"
  echo "  PASS: once resolves the agent provider via the shared role config"
}

# afk.sh routes the overseer's codex judge call through the shared agent_run seam
# (#66 crit 6 — no inline provider exec remains). The seam runs codex read-only
# (--sandbox read-only) and, unlike the old inline overseer call, requests --json
# and --output-last-message — so their presence in the read-only invocation proves
# the overseer now goes through the seam. Driven end-to-end with a short overseer
# interval and a fake whose iteration agent blocks until the overseer has fired,
# making the ordering deterministic. No jq needed (the verdict comes back via
# --output-last-message; the iteration stream degrades to a raw tee without jq).
test_afk_overseer_routes_codex_judge_call_through_seam() {
  local tmp fakebin overseer_argv fired
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  overseer_argv="$tmp/overseer-argv.txt"
  fired="$tmp/overseer-fired"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex_overseer "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex \
    RALPH_OVERSEE_INTERVAL=1 OVERSEER_FIRED="$fired" FAKE_OVERSEER_ARGV="$overseer_argv" \
    bash "$AFK_SCRIPT" demo 1 >/dev/null 2>&1)

  [ -f "$fired" ] || fail "afk overseer should have fired (routed its codex judge call)"
  [ -f "$overseer_argv" ] || fail "afk overseer codex call should have been recorded"
  assert_file_contains "$overseer_argv" "--json" "overseer codex should route through the seam (--json, absent from the old inline overseer call)"
  assert_file_contains "$overseer_argv" "--sandbox" "overseer codex invocation should set a sandbox via the seam"
  assert_file_contains "$overseer_argv" "read-only" "overseer codex sandbox should be read-only"
  assert_file_contains "$overseer_argv" "--output-last-message" "overseer codex should capture its verdict via the seam"
  echo "  PASS: afk routes the overseer codex judge call through the shared seam"
}

# afk.sh routes the overseer's claude judge call through the seam too. The
# overseer needs read-only -> --permission-mode plan, and the seam uses
# --output-format stream-json (the old inline overseer used plain --print, never
# stream-json) — so stream-json in the plan invocation proves seam routing.
test_afk_overseer_routes_claude_judge_call_through_seam() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: afk overseer claude seam routing (jq not available)"
    return 0
  fi

  local tmp fakebin overseer_argv fired
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  overseer_argv="$tmp/overseer-argv.txt"
  fired="$tmp/overseer-fired"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_claude_overseer "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=claude \
    RALPH_OVERSEE_INTERVAL=1 OVERSEER_FIRED="$fired" FAKE_OVERSEER_ARGV="$overseer_argv" \
    bash "$AFK_SCRIPT" demo 1 >/dev/null 2>&1)

  [ -f "$fired" ] || fail "afk overseer should have fired (routed its claude judge call)"
  [ -f "$overseer_argv" ] || fail "afk overseer claude call should have been recorded"
  assert_file_contains "$overseer_argv" "--output-format" "overseer claude should route through the seam (structured output, unlike the old inline --print)"
  assert_file_contains "$overseer_argv" "stream-json" "overseer claude should request stream-json via the seam"
  assert_file_contains "$overseer_argv" "--permission-mode" "overseer claude should set a permission mode via the seam"
  assert_file_contains "$overseer_argv" "plan" "overseer claude permission mode should be plan (read-only)"
  echo "  PASS: afk routes the overseer claude judge call through the shared seam"
}

# Criterion 6 (#66): no duplicate provider/feedback logic remains in ralph
# scripts — every provider invocation now lives in the shared agent_run seam, so
# the launchers carry no raw provider-invocation flags of their own. Strip
# comments first (the scripts document the seam's invocation in prose), then
# assert no inline exec flag survives in once.sh or afk.sh.
test_ralph_scripts_carry_no_inline_provider_invocation() {
  local script code flag
  for script in "$ONCE_SCRIPT" "$AFK_SCRIPT"; do
    code="$(sed 's/#.*//' "$script")"
    for flag in --ask-for-approval --output-format --permission-mode --output-last-message; do
      if printf '%s' "$code" | grep -Fq -- "$flag"; then
        fail "$(basename "$script") still has an inline provider invocation ($flag) — it must route through the shared seam (#66 crit 6)"
      fi
    done
  done
  echo "  PASS: ralph scripts carry no inline provider invocation (all routed through the seam)"
}

echo "=== Ralph Run Registry Tests ==="
test_once_registers_and_marks_run_done
test_once_marks_run_failed_on_provider_error
test_once_emits_live_run_progress_contract
test_once_claude_routes_provider_invocation_through_seam
test_once_claude_propagates_provider_failure
test_once_codex_routes_provider_invocation_through_seam
test_once_codex_propagates_provider_failure
test_afk_registers_and_marks_run_done
test_afk_marks_run_failed_on_provider_error
test_afk_emits_live_run_progress_contract
test_afk_codex_routes_provider_invocation_through_seam
test_afk_claude_routes_provider_invocation_through_seam
test_afk_claude_propagates_provider_failure
test_once_codex_verbose_routes_through_seam_raw_mode
test_afk_codex_verbose_routes_through_seam_raw_mode
test_once_resolves_agent_model_via_shared_role_config
test_afk_resolves_agent_model_via_shared_role_config
test_once_resolves_agent_provider_via_shared_role_config
test_afk_overseer_routes_codex_judge_call_through_seam
test_afk_overseer_routes_claude_judge_call_through_seam
test_ralph_scripts_carry_no_inline_provider_invocation
