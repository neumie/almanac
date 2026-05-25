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
