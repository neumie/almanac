#!/usr/bin/env bash
# test-worker.sh - worker orchestration tests (lib/worker.sh)
#
# Sources lib/worker.sh DIRECTLY (its interface is its own test surface) — the
# worker ORCHESTRATION (background fan-out) moved here from the deleted loop-core.sh.
# worker.sh pulls in lib/run.sh (worker path helpers + run-status reader) and
# lib/agent.sh (the capture shape a spawned worker runs) idempotently, so sourcing
# worker.sh alone gives these tests everything they exercise:
#   - almanac_loop_worker_start: spawns a provider run in the background through the
#     agent capture shape, recording the worker's status.tsv / events.jsonl /
#     result.txt under the run dir, and marks it done with the agent's exit code
#   - almanac_loop_worker_watch: streams one worker's live event log (and reports
#     cleanly when no log exists yet)
# The run registry / worker-health read-views live in lib/run.sh (tests/test-run.sh).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/worker.sh"

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

assert_file_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
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
  almanac_loop_worker_record_set "$wdir/status.tsv" \
    "id=reviewer-security" "run_id=$run_id" "pid=111" "provider=codex" \
    "sandbox=read-only" "prompt_file=p" "events_file=$events" \
    "result_file=r" "stderr_file=s" "started_at=2026-05-25T12:00:00Z" "status=running"

  out="$(almanac_loop_worker_watch "$tmp" "$run_id" "reviewer-security")"
  assert_contains "$out" '{"e":"started"}' "watch should stream the worker's event log"
  assert_contains "$out" '{"e":"thinking"}' "watch should stream every event line"

  # A worker whose event log does not exist yet reports cleanly (non-zero) instead
  # of hanging or erroring.
  perfdir="$tmp/.almanac/runs/$run_id/workers/reviewer-perf"
  mkdir -p "$perfdir"
  almanac_loop_worker_record_set "$perfdir/status.tsv" \
    "id=reviewer-perf" "run_id=$run_id" "pid=112" "provider=codex" \
    "sandbox=read-only" "prompt_file=p" "events_file=$perfdir/events.jsonl" \
    "result_file=r" "stderr_file=s" "started_at=2026-05-25T12:00:00Z" "status=running"
  rc=0
  almanac_loop_worker_watch "$tmp" "$run_id" "reviewer-perf" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "watch should return non-zero when the worker has no event log yet (got $rc)"
  echo "  PASS: worker watch streams the worker event log"
}

echo "=== Worker Orchestration Tests ==="
test_worker_start_tracks_background_agent
test_worker_watch_streams_event_log

echo ""
echo "All worker orchestration tests passed."
