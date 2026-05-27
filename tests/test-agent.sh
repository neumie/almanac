#!/usr/bin/env bash
# test-agent.sh - agent run-shape tests (lib/agent.sh)
#
# Sources lib/agent.sh DIRECTLY (not through loop-core) so the three run shapes —
# almanac_loop_agent_capture / _stream / _raw — are their own test surface. Each
# shape runs behind a FAKE provider: a temp bin holds fake `codex`/`claude`
# executables that emit the same event-stream shape the real adapters parse, so no
# real model is ever called. The provider-adapter seam itself (discovery, argv,
# filter, default-selection) is covered by test-providers.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/agent.sh"

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
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message (looking for '$needle')" ;;
  esac
}

assert_file_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

# --- Fake providers ------------------------------------------------------------
# Each emits the event-stream shape its real adapter parses, records its argv to a
# log, and (codex) writes its --output-last-message result. PATH puts the fake
# first so it shadows any real codex/claude on the host.

write_fake_codex_agent() {
  local fakebin="$1" args_log="$2"
  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "\$*" > "$args_log"
result_file=""
prompt=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message)
      shift
      result_file="\${1:-}"
      ;;
    *)
      prompt="\$1"
      ;;
  esac
  shift || true
done

[ -n "\$result_file" ] && printf '%s\n' "codex final: \$prompt" > "\$result_file"
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_message","message":"codex event"}}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"codex streamed: hardened"}}'
EOF
  chmod +x "$fakebin/codex"
}

write_fake_claude_agent() {
  local fakebin="$1" args_log="$2"
  mkdir -p "$fakebin"
  cat > "$fakebin/claude" <<EOF
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "\$*" > "$args_log"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"claude event"}]}}'
printf '%s\n' '{"type":"result","result":"claude final"}'
EOF
  chmod +x "$fakebin/claude"
}

# Fake codex that writes a diagnostic to stderr (before its json events) so the
# stream shape's opt-in merge-stderr (2>&1) capture can be exercised.
write_fake_codex_stderr_agent() {
  local fakebin="$1"
  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
      ;;
  esac
  shift || true
done

printf '%s\n' "codex-stderr-diagnostic" >&2
[ -n "$result_file" ] && printf '%s\n' "codex final" > "$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"codex streamed: hardened"}}'
EOF
  chmod +x "$fakebin/codex"
}

write_fake_failing_agent() {
  local fakebin="$1" name="$2"
  mkdir -p "$fakebin"
  cat > "$fakebin/$name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_message","message":"partial"}}'
exit 7
EOF
  chmod +x "$fakebin/$name"
}

# --- capture -------------------------------------------------------------------

# capture runs the provider silently: the raw event stream lands in the events
# file, the final result in the result file, and NOTHING goes to stdout.
test_capture_invokes_codex_with_common_config() {
  local tmp fakebin prompt result events args printed
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  printed="$(PATH="$fakebin:$PATH" almanac_loop_agent_capture "codex" "gpt-test" "high" "read-only" "$prompt" "$result" "$events")"

  args="$(cat "$tmp/codex-args.txt")"
  assert_contains "$args" "--ask-for-approval never" "codex capture should disable approval prompts"
  assert_contains "$args" "--sandbox read-only" "codex capture should pass the sandbox"
  assert_contains "$args" "--model gpt-test" "codex capture should pass the model"
  assert_contains "$args" "model_reasoning_effort=\"high\"" "codex capture should pass the effort"
  assert_file_contains "$result" "codex final: review target" "codex capture should write the provider result"
  assert_file_contains "$events" "codex event" "codex capture should write the raw event stream to the log"
  assert_eq "" "$printed" "capture is silent — it must not write to stdout"
  echo "  PASS: capture invokes codex with common config (silent)"
}

test_capture_invokes_claude_with_common_config() {
  local tmp fakebin prompt result events args printed
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  printed="$(PATH="$fakebin:$PATH" almanac_loop_agent_capture "claude" "sonnet-test" "medium" "read-only" "$prompt" "$result" "$events")"

  args="$(cat "$tmp/claude-args.txt")"
  assert_contains "$args" "--print" "claude capture should print non-interactively"
  assert_contains "$args" "--output-format stream-json" "claude capture should stream json"
  assert_contains "$args" "--permission-mode plan" "claude read-only capture should use plan permission mode"
  assert_contains "$args" "--model sonnet-test" "claude capture should pass the model"
  assert_contains "$args" "--effort medium" "claude capture should pass the effort"
  assert_file_contains "$result" "claude final" "claude capture should extract the final result"
  assert_file_contains "$events" "claude event" "claude capture should write the raw event stream to the log"
  assert_eq "" "$printed" "capture is silent — it must not write to stdout"
  echo "  PASS: capture invokes claude with common config (silent)"
}

# The `default` sandbox sentinel omits --permission-mode so claude uses its own
# default mode (afk's iteration agent has never set one).
test_capture_claude_default_sandbox_omits_permission_mode() {
  local tmp fakebin prompt result events args
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "iterate" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  PATH="$fakebin:$PATH" almanac_loop_agent_capture "claude" "" "" "default" "$prompt" "$result" "$events"

  args="$(cat "$tmp/claude-args.txt")"
  assert_contains "$args" "--output-format stream-json" "default-sandbox claude should still stream json"
  case "$args" in
    *"--permission-mode"*) fail "the default sandbox must omit --permission-mode so claude uses its own default mode" ;;
  esac
  assert_file_contains "$result" "claude final" "default-sandbox claude should still extract the final result"
  echo "  PASS: capture claude default sandbox omits permission mode"
}

test_capture_propagates_codex_failure() {
  local tmp fakebin prompt result events rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "codex"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_capture "codex" "" "" "read-only" "$prompt" "$result" "$events" || rc=$?
  assert_eq "7" "$rc" "codex capture should propagate the provider's non-zero exit"
  echo "  PASS: capture propagates codex failure"
}

test_capture_propagates_claude_failure() {
  local tmp fakebin prompt result events rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "claude"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_capture "claude" "" "" "read-only" "$prompt" "$result" "$events" || rc=$?
  assert_eq "7" "$rc" "claude capture should propagate the provider's non-zero exit (not mask it behind a pipe)"
  echo "  PASS: capture propagates claude failure"
}

# An unknown provider is rejected with a diagnostic before any exec (return 3).
test_capture_rejects_unknown_provider() {
  local tmp prompt result events rc err
  new_tmpdir; tmp="$NEW_TMPDIR"
  prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "x" > "$prompt"

  rc=0
  err="$(almanac_loop_agent_capture "bogus" "" "" "read-only" "$prompt" "$result" "$events" 2>&1)" || rc=$?
  assert_eq "3" "$rc" "an unknown provider should return 3"
  assert_contains "$err" "unsupported provider: bogus" "an unknown provider should emit a diagnostic"
  echo "  PASS: capture rejects unknown provider"
}

# --- stream --------------------------------------------------------------------

# stream tees the raw event stream to the events file AND pipes the adapter's
# filtered live text to stdout, while still extracting the final result.
test_stream_claude_live_text() {
  local tmp fakebin prompt result events out
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: stream claude live text (no jq)"; return 0; }
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_stream "claude" "" "" "workspace-write" "$prompt" "$result" "$events")"

  assert_contains "$out" "claude event" "stream should emit the assistant text live to stdout"
  case "$out" in
    *'"type":"assistant"'*) fail "stream must filter raw JSON envelopes out of the live stdout" ;;
  esac
  case "$out" in
    *"$events"*) fail "stream must not print the events-file path into the live stream" ;;
  esac
  assert_file_contains "$events" "claude event" "stream should still capture the raw event stream to the log"
  assert_file_contains "$result" "claude final" "stream should still extract the final result"
  echo "  PASS: stream emits claude live text"
}

test_stream_codex_live_text() {
  local tmp fakebin prompt result events out
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: stream codex live text (no jq)"; return 0; }
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_stream "codex" "" "" "danger-full-access" "$prompt" "$result" "$events")"

  assert_contains "$out" "codex streamed: hardened" "stream should emit codex agent-message text live to stdout"
  case "$out" in
    *'"type":"item.completed"'*) fail "stream must filter raw codex JSON out of the live stdout" ;;
  esac
  assert_file_contains "$events" "codex streamed: hardened" "stream should still capture the raw codex event stream"
  assert_file_contains "$result" "codex final: review target" "stream should still write the codex final result"
  echo "  PASS: stream emits codex live text"
}

# The streaming pipe must not swallow a provider failure behind the jq filter:
# PIPESTATUS of the producer drives the exit, so a broken run still propagates.
test_stream_propagates_failure() {
  local tmp fakebin prompt result events rc
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: stream failure propagation (no jq)"; return 0; }
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"; events="$tmp/events.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "claude"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_stream "claude" "" "" "workspace-write" "$prompt" "$result" "$events" >/dev/null 2>&1 || rc=$?
  assert_eq "7" "$rc" "stream must propagate the provider's exit (PIPESTATUS), not the jq filter's"
  echo "  PASS: stream propagates provider failure"
}

# Opt-in merge-stderr folds the provider's stderr into the captured event log
# (2>&1) — preserving ralph's `codex ... 2>&1 | tee`. Default leaves it off.
test_stream_merge_stderr_is_opt_in() {
  local tmp fakebin prompt result events_default events_merge out
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: stream merge-stderr (no jq)"; return 0; }
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"
  events_default="$tmp/events-default.jsonl"; events_merge="$tmp/events-merge.jsonl"
  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_stderr_agent "$fakebin"

  PATH="$fakebin:$PATH" almanac_loop_agent_stream "codex" "" "" "danger-full-access" "$prompt" "$result" "$events_default" >/dev/null 2>&1
  if grep -Fq "codex-stderr-diagnostic" "$events_default"; then
    fail "default stream must not capture provider stderr in the event log"
  fi

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_stream "codex" "" "" "danger-full-access" "$prompt" "$result" "$events_merge" merge-stderr)"
  assert_file_contains "$events_merge" "codex-stderr-diagnostic" "merge-stderr should capture provider stderr in the event log"
  assert_contains "$out" "codex streamed: hardened" "merge-stderr should still stream the agent-message text live"
  case "$out" in
    *"codex-stderr-diagnostic"*) fail "merge-stderr must not leak the raw stderr line onto the filtered live stdout" ;;
  esac
  echo "  PASS: stream merge-stderr is opt-in"
}

# --- raw -----------------------------------------------------------------------

# raw runs codex WITHOUT --json so its native output streams straight to stdout
# (no jq filter, no events capture), while --output-last-message still captures
# the result. No jq is required, since raw never filters.
test_raw_codex_passes_native_output_through() {
  local tmp fakebin prompt result args out
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"
  printf '%s\n' "verbose target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_raw "codex" "gpt-test" "high" "danger-full-access" "$prompt" "$result")"

  args="$(cat "$tmp/codex-args.txt")"
  case "$args" in
    *"--json"*) fail "raw must omit --json so codex emits its native output" ;;
  esac
  assert_contains "$args" "--output-last-message" "raw should still capture the provider final message"
  assert_contains "$args" "--sandbox danger-full-access" "raw should pass the sandbox"
  assert_contains "$args" "--model gpt-test" "raw should pass the model override"
  assert_contains "$args" "model_reasoning_effort=\"high\"" "raw should pass the effort override"
  assert_contains "$out" "codex event" "raw should pass codex native output straight through (no filter, no redirect)"
  assert_file_contains "$result" "codex final: verbose target" "raw should capture the provider final result"
  echo "  PASS: raw codex passes native output through"
}

# A provider WITHOUT raw support (claude) degrades to a silent capture, so output
# is never dropped: the result is still extracted and nothing leaks to stdout.
test_raw_degrades_to_capture_for_non_raw_provider() {
  local tmp fakebin prompt result out
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"
  printf '%s\n' "iterate" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_raw "claude" "" "" "workspace-write" "$prompt" "$result")"

  assert_file_contains "$result" "claude final" "raw on a non-raw provider should still extract the result (capture fallback)"
  assert_eq "" "$out" "the capture fallback is silent — no stdout"
  echo "  PASS: raw degrades to capture for a non-raw provider"
}

# The raw fallback used to allocate an events tmpfile without ever cleaning it
# up — a leak per invocation. The RETURN-trapped cleanup must remove the throw-
# away log on every exit path, including provider failure.
test_raw_fallback_does_not_leak_events_tmpfile() {
  local tmp fakebin prompt result tmproot before after rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"; prompt="$tmp/prompt.md"; result="$tmp/result.txt"
  tmproot="$tmp/scratch"; mkdir -p "$tmproot"
  printf '%s\n' "iterate" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  before="$(find "$tmproot" -maxdepth 1 -name 'almanac-loop-events.*' | wc -l | tr -d ' ')"
  TMPDIR="$tmproot" PATH="$fakebin:$PATH" almanac_loop_agent_raw "claude" "" "" "workspace-write" "$prompt" "$result" >/dev/null
  after="$(find "$tmproot" -maxdepth 1 -name 'almanac-loop-events.*' | wc -l | tr -d ' ')"
  assert_eq "$before" "$after" "raw fallback must clean its throwaway events tmpfile (was leaking before)"

  # And on a failing provider (the cleanup must still fire).
  write_fake_failing_agent "$fakebin" "claude"
  rc=0
  TMPDIR="$tmproot" PATH="$fakebin:$PATH" almanac_loop_agent_raw "claude" "" "" "workspace-write" "$prompt" "$result" >/dev/null || rc=$?
  after="$(find "$tmproot" -maxdepth 1 -name 'almanac-loop-events.*' | wc -l | tr -d ' ')"
  assert_eq "7" "$rc" "raw fallback should still propagate the provider failure"
  assert_eq "$before" "$after" "raw fallback must clean its throwaway events tmpfile on failure too"
  echo "  PASS: raw fallback does not leak events tmpfile"
}

# --- capture_text --------------------------------------------------------------

# capture_text takes a prompt STRING and returns the provider's result text on
# stdout. It owns the tmpfile lifecycle inside an EXIT-trapped subshell so
# callers no longer need to allocate/clean prompt+result+events tmpfiles.
test_capture_text_returns_result_string() {
  local tmp fakebin out
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_capture_text "codex" "gpt-test" "high" "read-only" "review me")"

  assert_contains "$out" "codex final: review me" "capture_text should return the provider's result on stdout"
  echo "  PASS: capture_text returns the result string"
}

# capture_text must propagate the provider's non-zero exit (not mask it behind
# the subshell), so callers can branch on rc like the file-based capture.
test_capture_text_propagates_failure() {
  local tmp fakebin rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  write_fake_failing_agent "$fakebin" "codex"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_capture_text "codex" "" "" "read-only" "x" >/dev/null 2>&1 || rc=$?
  assert_eq "7" "$rc" "capture_text should propagate the provider's non-zero exit through the subshell"
  echo "  PASS: capture_text propagates provider failure"
}

# capture_text owns its tmpfile lifecycle: the subshell's EXIT trap must clean
# the workdir regardless of exit path. Without the trap, every invocation
# leaked one tmpdir under $TMPDIR (the pattern the 3-tmpfile call sites were
# all rolling by hand).
test_capture_text_cleans_workdir_on_success_and_failure() {
  local tmp fakebin tmproot before after rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  tmproot="$tmp/scratch"; mkdir -p "$tmproot"

  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"
  before="$(find "$tmproot" -maxdepth 1 -name 'almanac-capture-text.*' | wc -l | tr -d ' ')"
  TMPDIR="$tmproot" PATH="$fakebin:$PATH" almanac_loop_agent_capture_text "codex" "" "" "read-only" "x" >/dev/null
  after="$(find "$tmproot" -maxdepth 1 -name 'almanac-capture-text.*' | wc -l | tr -d ' ')"
  assert_eq "$before" "$after" "capture_text must clean its workdir on success"

  write_fake_failing_agent "$fakebin" "codex"
  rc=0
  TMPDIR="$tmproot" PATH="$fakebin:$PATH" almanac_loop_agent_capture_text "codex" "" "" "read-only" "x" >/dev/null 2>&1 || rc=$?
  after="$(find "$tmproot" -maxdepth 1 -name 'almanac-capture-text.*' | wc -l | tr -d ' ')"
  assert_eq "7" "$rc" "capture_text must still propagate failure when cleaning"
  assert_eq "$before" "$after" "capture_text must clean its workdir on failure"
  echo "  PASS: capture_text cleans workdir on success and failure"
}

echo "=== Agent Run-Shape Tests ==="
test_capture_invokes_codex_with_common_config
test_capture_invokes_claude_with_common_config
test_capture_claude_default_sandbox_omits_permission_mode
test_capture_propagates_codex_failure
test_capture_propagates_claude_failure
test_capture_rejects_unknown_provider
test_stream_claude_live_text
test_stream_codex_live_text
test_stream_propagates_failure
test_stream_merge_stderr_is_opt_in
test_raw_codex_passes_native_output_through
test_raw_degrades_to_capture_for_non_raw_provider
test_raw_fallback_does_not_leak_events_tmpfile
test_capture_text_returns_result_string
test_capture_text_propagates_failure
test_capture_text_cleans_workdir_on_success_and_failure

echo "All agent run-shape tests passed."
