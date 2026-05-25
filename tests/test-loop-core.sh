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

echo "=== Loop Core Tests ==="
test_detects_project_marker_commands
test_dedupes_python_markers
test_detects_repo_test_scripts
test_registers_run_in_registry
test_marks_registered_run_done
test_resolves_role_config_with_lens_overrides
test_resolves_role_config_with_ralph_style_fallbacks
test_agent_runner_invokes_codex_with_common_config
test_agent_runner_invokes_claude_with_common_config
test_agent_runner_propagates_codex_failure
test_agent_runner_propagates_claude_failure
test_worker_start_tracks_background_agent
