#!/usr/bin/env bash
# test-loop-core.sh - Shared loop engine behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/loop-core.sh"

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message" ;;
  esac
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

write_fake_codex_agent() {
  local fakebin="$1"
  local args_log="$2"

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
  local fakebin="$1"
  local args_log="$2"

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

write_fake_failing_agent() {
  local fakebin="$1"
  local name="$2"

  mkdir -p "$fakebin"
  cat > "$fakebin/$name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_message","message":"partial"}}'
exit 7
EOF
  chmod +x "$fakebin/$name"
}

test_detects_project_marker_commands() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  touch "$tmp/package.json"
  touch "$tmp/Makefile"
  touch "$tmp/Cargo.toml"
  touch "$tmp/go.mod"
  touch "$tmp/pyproject.toml"

  expected=$(cat <<'EOF'
npm run test
npm run typecheck
npm run lint
make test
make check
cargo test
cargo check
go test ./...
go vet ./...
pytest
mypy
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "marker files should map to feedback commands"
  echo "  PASS: detects project marker commands"
}

test_dedupes_python_markers() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  touch "$tmp/pyproject.toml"
  touch "$tmp/setup.py"

  expected=$(cat <<'EOF'
pytest
mypy
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "python markers should not duplicate commands"
  echo "  PASS: dedupes python markers"
}

test_detects_repo_test_scripts() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/tests"
  touch "$tmp/tests/test-skills.sh"
  touch "$tmp/tests/test-structure.sh"

  expected=$(cat <<'EOF'
bash tests/test-skills.sh
bash tests/test-structure.sh
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "repo test scripts should be feedback commands"
  echo "  PASS: detects repo test scripts"
}

test_no_markers_yields_no_commands() {
  local tmp actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # An empty project (no marker files at all) detects nothing — the runner then
  # has no objective gate to run rather than erroring.
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "" "$actual" "a project with no marker files should yield no feedback commands"
  echo "  PASS: no markers yields no commands"
}

test_feedback_run_reports_per_loop_verdict() {
  local tmp verdicts rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Two detectable repo test scripts: one green, one red, so the runner must
  # emit a distinct pass/fail verdict per loop and a non-zero aggregate.
  mkdir -p "$tmp/tests"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/tests/test-skills.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$tmp/tests/test-structure.sh"
  chmod +x "$tmp/tests/test-skills.sh" "$tmp/tests/test-structure.sh"

  rc=0
  verdicts="$(almanac_loop_feedback_run "$tmp")" || rc=$?

  assert_contains "$verdicts" $'bash tests/test-skills.sh\tpass' "a green loop should report pass"
  assert_contains "$verdicts" $'bash tests/test-structure.sh\tfail' "a red loop should report fail"
  [ "$rc" -ne 0 ] || fail "the aggregate must be non-zero when any loop fails"
  echo "  PASS: feedback run reports per-loop verdict"
}

test_feedback_run_passes_when_all_green() {
  local tmp verdicts rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/tests"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/tests/test-skills.sh"
  chmod +x "$tmp/tests/test-skills.sh"

  rc=0
  verdicts="$(almanac_loop_feedback_run "$tmp")" || rc=$?

  assert_contains "$verdicts" $'bash tests/test-skills.sh\tpass' "the green loop should report pass"
  [ "$rc" -eq 0 ] || fail "the aggregate must be zero when every loop passes"
  echo "  PASS: feedback run passes when all loops green"
}

test_registers_run_in_registry() {
  local tmp run_id status_file index_file expected_index
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_id="$(almanac_loop_register_run "$tmp" "harden" "src/app.js" "4242" "harden-src-app-js-001" "2026-05-25T12:00:00Z")"
  status_file="$tmp/.almanac/runs/harden-src-app-js-001/status.tsv"
  index_file="$tmp/.almanac/runs/index.tsv"

  expected_index=$(cat <<'EOF'
id	type	target	pid	status_file	started_at	status
harden-src-app-js-001	harden	src/app.js	4242	.almanac/runs/harden-src-app-js-001/status.tsv	2026-05-25T12:00:00Z	running
EOF
)

  assert_eq "harden-src-app-js-001" "$run_id" "register should print run id"
  [ -f "$status_file" ] || fail "register should write run status file"
  [ -f "$index_file" ] || fail "register should write run index"
  assert_eq "$expected_index" "$(cat "$index_file")" "run index should capture launched run"
  assert_file_contains "$status_file" $'id\tharden-src-app-js-001' "status should record id"
  assert_file_contains "$status_file" $'type\tharden' "status should record type"
  assert_file_contains "$status_file" $'target\tsrc/app.js' "status should record target"
  assert_file_contains "$status_file" $'pid\t4242' "status should record pid"
  assert_file_contains "$status_file" $'status\trunning' "status should start running"
  assert_file_contains "$status_file" $'started_at\t2026-05-25T12:00:00Z' "status should record start time"
  echo "  PASS: registers run in registry"
}

test_marks_registered_run_done() {
  local tmp status_file index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/demo/prd.md" "31337" "ralph-demo-001" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "ralph-demo-001" "done" "2026-05-25T12:10:00Z"

  status_file="$tmp/.almanac/runs/ralph-demo-001/status.tsv"
  index_file="$tmp/.almanac/runs/index.tsv"

  assert_file_contains "$status_file" $'status\tdone' "status file should mark run done"
  assert_file_contains "$status_file" $'finished_at\t2026-05-25T12:10:00Z' "status file should record finish time"
  assert_file_contains "$index_file" $'ralph-demo-001\tralph\tdocs/plans/demo/prd.md\t31337\t.almanac/runs/ralph-demo-001/status.tsv\t2026-05-25T12:00:00Z\tdone' "index should mark run done"
  echo "  PASS: marks registered run done"
}

test_update_run_progress_records_round_and_summary() {
  local tmp status_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "4242" "harden-demo-002" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "harden-demo-002" "2" "reviewers: security,perf,correctness"

  status_file="$tmp/.almanac/runs/harden-demo-002/status.tsv"
  assert_file_contains "$status_file" $'round\t2' "progress update should record the round/iteration"
  assert_file_contains "$status_file" $'summary\treviewers: security,perf,correctness' "progress update should record the worker/lens summary"
  assert_file_contains "$status_file" $'status\trunning' "progress update must not change lifecycle status"
  assert_file_contains "$status_file" $'started_at\t2026-05-25T12:00:00Z' "progress update must preserve start time"
  assert_eq "" "$(almanac_loop_status_field "$status_file" "finished_at")" "progress update must leave a live run unfinished"
  echo "  PASS: update run progress records round and summary"
}

test_mark_run_aborted_preserves_progress() {
  local tmp status_file index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "4242" "harden-demo-003" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "harden-demo-003" "3" "reviewers: security"
  almanac_loop_mark_run_status "$tmp" "harden-demo-003" "aborted" "2026-05-25T12:30:00Z"

  status_file="$tmp/.almanac/runs/harden-demo-003/status.tsv"
  index_file="$tmp/.almanac/runs/index.tsv"
  assert_file_contains "$status_file" $'status\taborted' "aborted is a valid terminal state"
  assert_file_contains "$status_file" $'finished_at\t2026-05-25T12:30:00Z' "aborted run should record finish time"
  assert_file_contains "$status_file" $'round\t3' "marking a run must preserve recorded round"
  assert_file_contains "$status_file" $'summary\treviewers: security' "marking a run must preserve recorded summary"
  assert_file_contains "$index_file" $'harden-demo-003\tharden\tsrc/app.js\t4242\t.almanac/runs/harden-demo-003/status.tsv\t2026-05-25T12:00:00Z\taborted' "index should reflect aborted status"
  echo "  PASS: mark run aborted preserves progress"
}

test_run_is_stale_detects_dead_pid() {
  local tmp rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # A running entry whose pid is long dead is stale.
  almanac_loop_register_run "$tmp" "harden" "src/app.js" "2147483647" "harden-dead" "2026-05-25T12:00:00Z" >/dev/null
  rc=0; almanac_loop_run_is_stale "$tmp" "harden-dead" || rc=$?
  assert_eq "0" "$rc" "a running entry with a dead pid must be detected as stale"

  # A running entry whose pid is alive (this test process) is not stale.
  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "harden-alive" "2026-05-25T12:00:00Z" >/dev/null
  rc=0; almanac_loop_run_is_stale "$tmp" "harden-alive" || rc=$?
  assert_eq "1" "$rc" "a running entry with a live pid must not be stale"

  # A terminal entry is never stale regardless of pid.
  almanac_loop_register_run "$tmp" "harden" "src/app.js" "2147483647" "harden-done" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "harden-done" "done" "2026-05-25T12:10:00Z"
  rc=0; almanac_loop_run_is_stale "$tmp" "harden-done" || rc=$?
  assert_eq "1" "$rc" "a finished run is never stale"
  echo "  PASS: run is stale detects dead pid"
}

test_list_runs_returns_all_registered_runs() {
  local tmp out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # No registry yet -> non-zero, no rows.
  rc=0; almanac_loop_list_runs "$tmp" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "listing runs with no registry should report no runs"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "11" "harden-a" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_register_run "$tmp" "ralph" "docs/plans/demo/prd.md" "22" "ralph-b" "2026-05-25T12:01:00Z" >/dev/null

  out="$(almanac_loop_list_runs "$tmp")"
  assert_eq "2" "$(printf '%s\n' "$out" | grep -c '[^[:space:]]')" "list should return one row per run, no header"
  assert_contains "$out" "harden-a" "list should include the harden run"
  assert_contains "$out" "ralph-b" "list should include the ralph run"
  case "$out" in
    id*) fail "list should not include the index header row" ;;
  esac
  echo "  PASS: list runs returns all registered runs"
}

test_read_run_returns_single_run_status() {
  local tmp out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "4242" "harden-read" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "harden-read" "4" "reviewers: security,perf"

  out="$(almanac_loop_read_run "$tmp" "harden-read")"
  assert_contains "$out" $'id\tharden-read' "read should return the run id"
  assert_contains "$out" $'type\tharden' "read should return the run type"
  assert_contains "$out" $'round\t4' "read should return the live round"
  assert_contains "$out" $'summary\treviewers: security,perf' "read should return the worker/lens summary"

  rc=0; almanac_loop_read_run "$tmp" "no-such-run" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "reading an unknown run should report failure"
  echo "  PASS: read run returns single run status"
}

test_resolves_role_config_with_lens_overrides() {
  local expected actual

  expected=$(cat <<'EOF'
provider	codex
model	security-model
effort	medium
EOF
)

  actual="$(
    HARDEN_PROVIDER=claude \
    HARDEN_MODEL=default-model \
    HARDEN_EFFORT=medium \
    HARDEN_REVIEWER_PROVIDER=codex \
    HARDEN_REVIEWER_SECURITY_MODEL=security-model \
    almanac_loop_role_config "harden" "reviewer" "security" "fallback-provider" "fallback-model" "low"
  )"

  assert_eq "$expected" "$actual" "lens config should layer lens, role, shared, then defaults"
  echo "  PASS: resolves role config with lens overrides"
}

test_resolves_role_config_with_ralph_style_fallbacks() {
  local expected actual

  expected=$(cat <<'EOF'
provider	claude
model	sonnet
effort	high
EOF
)

  actual="$(
    RALPH_PROVIDER=claude \
    RALPH_MODEL=sonnet \
    RALPH_EFFORT=high \
    almanac_loop_role_config "ralph" "worker" "" "codex" "" "medium"
  )"

  assert_eq "$expected" "$actual" "shared config should support Ralph-style global overrides"
  echo "  PASS: resolves role config with Ralph-style fallbacks"
}

test_agent_runner_invokes_codex_with_common_config() {
  local tmp fakebin prompt result events args printed
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  printed="$(PATH="$fakebin:$PATH" almanac_loop_agent_run "codex" "gpt-test" "high" "read-only" "$prompt" "$result" "$events")"

  args="$(cat "$tmp/codex-args.txt")"
  assert_contains "$args" "--ask-for-approval never" "codex runner should disable approval prompts"
  assert_contains "$args" "--sandbox read-only" "codex runner should pass sandbox mode"
  assert_contains "$args" "--model gpt-test" "codex runner should pass model override"
  assert_contains "$args" "model_reasoning_effort=\"high\"" "codex runner should pass effort override"
  assert_file_contains "$result" "codex final: review target" "codex runner should write provider final result"
  assert_file_contains "$events" "codex event" "codex runner should stream provider events to the log file"
  assert_eq "$events" "$printed" "codex runner should return the events log path"
  echo "  PASS: agent runner invokes codex with common config"
}

test_agent_runner_invokes_claude_with_common_config() {
  local tmp fakebin prompt result events args printed
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  printed="$(PATH="$fakebin:$PATH" almanac_loop_agent_run "claude" "sonnet-test" "medium" "read-only" "$prompt" "$result" "$events")"

  args="$(cat "$tmp/claude-args.txt")"
  assert_contains "$args" "--print" "claude runner should print non-interactively"
  assert_contains "$args" "--output-format stream-json" "claude runner should stream json events"
  assert_contains "$args" "--permission-mode plan" "claude read-only runner should use plan permission mode"
  assert_contains "$args" "--model sonnet-test" "claude runner should pass model override"
  assert_contains "$args" "--effort medium" "claude runner should pass effort override"
  assert_file_contains "$result" "claude final" "claude runner should extract final result"
  assert_file_contains "$events" "claude event" "claude runner should stream provider events to the log file"
  assert_eq "$events" "$printed" "claude runner should return the events log path"
  echo "  PASS: agent runner invokes claude with common config"
}

test_agent_runner_propagates_codex_failure() {
  local tmp fakebin prompt result events rc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "codex"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_run "codex" "" "" "read-only" "$prompt" "$result" "$events" >/dev/null || rc=$?

  assert_eq "7" "$rc" "codex runner should propagate the provider's non-zero exit"
  echo "  PASS: agent runner propagates codex failure"
}

test_agent_runner_propagates_claude_failure() {
  local tmp fakebin prompt result events rc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "claude"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_run "claude" "" "" "read-only" "$prompt" "$result" "$events" >/dev/null || rc=$?

  assert_eq "7" "$rc" "claude runner should propagate the provider's non-zero exit (not mask it behind a pipe)"
  echo "  PASS: agent runner propagates claude failure"
}

# Opt-in live-stream mode (the 8th arg). In stream mode the seam tees the
# provider's live assistant text to stdout through the same jq filter ralph's
# once.sh/afk.sh use, while STILL capturing the raw event stream and final
# result to their files. Default (no 8th arg) is unchanged and covered by the
# tests above. This pins the live-stream half the ralph migration needs before
# its provider invocation can route through this seam (issue #66 criterion 1).
test_agent_runner_streams_claude_live_text() {
  local tmp fakebin prompt result events out
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: agent runner streams claude live text (no jq)"; return 0; }
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_claude_agent "$fakebin" "$tmp/claude-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_run "claude" "" "" "workspace-write" "$prompt" "$result" "$events" stream)"

  assert_contains "$out" "claude event" "stream mode should emit the assistant text live to stdout"
  case "$out" in
    *'"type":"assistant"'*) fail "stream mode must filter raw JSON envelopes out of the live stdout" ;;
  esac
  case "$out" in
    *"$events"*) fail "stream mode must not print the events-file path into the live stream" ;;
  esac
  assert_file_contains "$events" "claude event" "stream mode should still capture the raw event stream to the log file"
  assert_file_contains "$result" "claude final" "stream mode should still extract the final result"
  echo "  PASS: agent runner streams claude live text"
}

test_agent_runner_streams_codex_live_text() {
  local tmp fakebin prompt result events out
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: agent runner streams codex live text (no jq)"; return 0; }
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  out="$(PATH="$fakebin:$PATH" almanac_loop_agent_run "codex" "" "" "danger-full-access" "$prompt" "$result" "$events" stream)"

  assert_contains "$out" "codex streamed: hardened" "stream mode should emit codex agent-message text live to stdout"
  case "$out" in
    *'"type":"item.completed"'*) fail "stream mode must filter raw codex JSON out of the live stdout" ;;
  esac
  assert_file_contains "$events" "codex streamed: hardened" "stream mode should still capture the raw codex event stream"
  assert_file_contains "$result" "codex final: review target" "stream mode should still write the codex final result"
  echo "  PASS: agent runner streams codex live text"
}

# The streaming pipe must not swallow a provider failure behind the jq filter:
# PIPESTATUS of the producer (not the filter) drives the exit code, so a broken
# run still propagates non-zero — the contract harden's worker orchestration
# and ralph's overseer both rely on.
test_agent_runner_stream_mode_propagates_failure() {
  local tmp fakebin prompt result events rc
  command -v jq >/dev/null 2>&1 || { echo "  SKIP: agent runner stream-mode failure (no jq)"; return 0; }
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"
  result="$tmp/result.txt"
  events="$tmp/events.jsonl"

  printf '%s\n' "review target" > "$prompt"
  write_fake_failing_agent "$fakebin" "claude"

  rc=0
  PATH="$fakebin:$PATH" almanac_loop_agent_run "claude" "" "" "workspace-write" "$prompt" "$result" "$events" stream >/dev/null 2>&1 || rc=$?

  assert_eq "7" "$rc" "stream mode must propagate the provider's exit code (PIPESTATUS), not the jq filter's"
  echo "  PASS: agent runner stream mode propagates provider failure"
}

test_worker_start_tracks_background_agent() {
  local tmp fakebin prompt pid status_file events_file result_file args
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  prompt="$tmp/prompt.md"

  printf '%s\n' "review target" > "$prompt"
  write_fake_codex_agent "$fakebin" "$tmp/codex-args.txt"

  PATH="$fakebin:$PATH" almanac_loop_worker_start \
    "$tmp" \
    "harden-demo-001" \
    "reviewer-security" \
    "codex" \
    "gpt-worker" \
    "high" \
    "read-only" \
    "$prompt" \
    "2026-05-25T12:00:00Z" > "$tmp/worker-pid.txt"

  pid="$(cat "$tmp/worker-pid.txt")"
  wait "$pid"

  status_file="$tmp/.almanac/runs/harden-demo-001/workers/reviewer-security/status.tsv"
  events_file="$tmp/.almanac/runs/harden-demo-001/workers/reviewer-security/events.jsonl"
  result_file="$tmp/.almanac/runs/harden-demo-001/workers/reviewer-security/result.txt"

  [ -f "$status_file" ] || fail "worker should write status file"
  [ -f "$events_file" ] || fail "worker should write event log"
  [ -f "$result_file" ] || fail "worker should write result file"
  assert_file_contains "$status_file" $'id\treviewer-security' "worker status should record id"
  assert_file_contains "$status_file" $'run_id\tharden-demo-001' "worker status should record run id"
  assert_file_contains "$status_file" $'provider\tcodex' "worker status should record provider"
  assert_file_contains "$status_file" $'sandbox\tread-only' "worker status should record sandbox"
  assert_file_contains "$status_file" $'status\tdone' "worker status should mark successful completion"
  assert_file_contains "$status_file" $'exit_code\t0' "worker status should record exit code"
  assert_file_contains "$events_file" "codex event" "worker should stream agent events to log"
  assert_file_contains "$result_file" "codex final: review target" "worker should capture agent result"
  args="$(cat "$tmp/codex-args.txt")"
  assert_contains "$args" "--sandbox read-only" "worker should pass sandbox through agent runner"
  echo "  PASS: worker start tracks background agent"
}

test_worker_health_classifies_states() {
  # Pure predicate over (status, log-age, event-count, trailing-repeat, stall,
  # loop) — no files, clock, or terminal, so the whole input space is table-able.
  assert_eq "running" "$(almanac_loop_worker_health running 0 5 1 120 5)" "a fresh, progressing worker is running"
  assert_eq "stalled" "$(almanac_loop_worker_health running 300 5 1 120 5)" "log silence past the stall threshold is stalled"
  assert_eq "idle"    "$(almanac_loop_worker_health running 300 0 0 120 5)" "running with zero events past the threshold is idle"
  assert_eq "looping" "$(almanac_loop_worker_health running 5 50 6 120 5)" "a long run of identical trailing events is looping"
  assert_eq "done"    "$(almanac_loop_worker_health done 0 0 0 120 5)" "a completed worker is done"
  assert_eq "failed"  "$(almanac_loop_worker_health failed 0 0 0 120 5)" "a failed worker is failed"
  echo "  PASS: worker health classifies states"
}

test_worker_health_of_reads_state() {
  local tmp run_id wdir events now health
  new_tmpdir
  tmp="$NEW_TMPDIR"
  run_id="harden-demo-001"
  wdir="$tmp/.almanac/runs/$run_id/workers/reviewer-security"
  mkdir -p "$wdir"
  events="$wdir/events.jsonl"
  printf '%s\n' '{"e":1}' '{"e":2}' > "$events"

  almanac_loop_write_worker_status "$wdir/status.tsv" "reviewer-security" "$run_id" \
    "111" "codex" "" "" "read-only" "p" "$events" "r" "s" "2026-05-25T12:00:00Z" "running" "" ""

  # Pin the clock far ahead of the just-written log so the age crosses the stall
  # threshold deterministically (no sleeps), proving the gather feeds real state
  # into the pure classifier.
  now="$(( $(date +%s) + 100000 ))"
  health="$(almanac_loop_worker_health_of "$tmp" "$run_id" "reviewer-security" "$now" 120 5)"

  assert_eq "stalled" "$health" "a running worker whose log stopped advancing reads as stalled"
  echo "  PASS: worker health of reads worker state"
}

# A single worker's live event stream can be watched: the shared watcher reads the
# worker's events-file path from its status.tsv and prints the log (non-follow mode
# so it returns rather than tailing), and reports cleanly when no log exists yet.
test_worker_watch_streams_event_log() {
  local tmp run_id wdir events out rc perfdir
  new_tmpdir
  tmp="$NEW_TMPDIR"
  run_id="harden-demo-001"
  wdir="$tmp/.almanac/runs/$run_id/workers/reviewer-security"
  mkdir -p "$wdir"
  events="$wdir/events.jsonl"
  printf '%s\n' '{"e":"started"}' '{"e":"thinking"}' > "$events"
  almanac_loop_write_worker_status "$wdir/status.tsv" "reviewer-security" "$run_id" \
    "111" "codex" "" "" "read-only" "p" "$events" "r" "s" "2026-05-25T12:00:00Z" "running" "" ""

  out="$(almanac_loop_worker_watch "$tmp" "$run_id" "reviewer-security")"
  assert_contains "$out" '{"e":"started"}' "watch should stream the worker's event log"
  assert_contains "$out" '{"e":"thinking"}' "watch should stream every event line"

  # A worker whose event log does not exist yet reports cleanly (non-zero) instead
  # of hanging or erroring.
  perfdir="$tmp/.almanac/runs/$run_id/workers/reviewer-perf"
  mkdir -p "$perfdir"
  almanac_loop_write_worker_status "$perfdir/status.tsv" "reviewer-perf" "$run_id" \
    "112" "codex" "" "" "read-only" "p" "$perfdir/events.jsonl" "r" "s" "2026-05-25T12:00:00Z" "running" "" ""
  rc=0
  almanac_loop_worker_watch "$tmp" "$run_id" "reviewer-perf" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "watch should return non-zero when the worker has no event log yet (got $rc)"
  echo "  PASS: worker watch streams the worker event log"
}

test_ui_render_degrades_without_gum() {
  local out rc
  out="$(printf '%s\n' "reviewer-security stalled" | ALMANAC_NO_GUM=1 almanac_loop_ui_render)"
  assert_contains "$out" "reviewer-security stalled" "ui render must pass content through plainly when gum is suppressed"

  rc=0
  ALMANAC_NO_GUM=1 almanac_loop_ui_has_gum || rc=$?
  [ "$rc" -ne 0 ] || fail "has_gum must report absent when ALMANAC_NO_GUM is set"
  echo "  PASS: ui render degrades without gum"
}

echo "=== Loop Core Tests ==="
test_detects_project_marker_commands
test_dedupes_python_markers
test_detects_repo_test_scripts
test_no_markers_yields_no_commands
test_feedback_run_reports_per_loop_verdict
test_feedback_run_passes_when_all_green
test_registers_run_in_registry
test_marks_registered_run_done
test_update_run_progress_records_round_and_summary
test_mark_run_aborted_preserves_progress
test_run_is_stale_detects_dead_pid
test_list_runs_returns_all_registered_runs
test_read_run_returns_single_run_status
test_resolves_role_config_with_lens_overrides
test_resolves_role_config_with_ralph_style_fallbacks
test_agent_runner_invokes_codex_with_common_config
test_agent_runner_invokes_claude_with_common_config
test_agent_runner_propagates_codex_failure
test_agent_runner_propagates_claude_failure
test_agent_runner_streams_claude_live_text
test_agent_runner_streams_codex_live_text
test_agent_runner_stream_mode_propagates_failure
test_worker_start_tracks_background_agent
test_worker_health_classifies_states
test_worker_health_of_reads_state
test_worker_watch_streams_event_log
test_ui_render_degrades_without_gum
