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

# Role config resolution (almanac_loop_role_field / role_config) moved to
# lib/role.sh in loop-engine-split slice 06; its precedence + role_config tests
# now live in tests/test-role.sh (sourced directly), not here.

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

test_hub_render_lists_running_with_live_status() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # A live run (this process's pid), a crashed run (dead pid, never marked), and
  # a finished run.
  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "harden-live" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "harden-live" "2" "reviewers: security,perf"
  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "2147483647" "ralph-dead" "2026-05-25T12:01:00Z" >/dev/null
  almanac_loop_register_run "$tmp" "harden" "src/old.js" "$$" "harden-fin" "2026-05-25T11:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "harden-fin" "done" "2026-05-25T11:30:00Z"

  out="$(almanac_loop_hub_render "$tmp" running)"
  assert_contains "$out" "harden-live" "running list includes the live harden run"
  assert_contains "$out" "round 2" "running list shows the live round"
  assert_contains "$out" "reviewers: security,perf" "running list shows the live summary"
  assert_contains "$out" "running" "live run is shown running"
  assert_contains "$out" "ralph-dead" "running list includes the crashed run"
  assert_contains "$out" "stale" "a running entry with a dead pid is surfaced as stale"
  case "$out" in
    *harden-fin*) fail "running list must exclude finished runs" ;;
  esac
  echo "  PASS: hub render lists running with live status"
}

test_hub_render_recent_newest_first_capped() {
  local tmp out first
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "a.js" "$$" "fin-old" "2026-05-25T10:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "fin-old" "done" "2026-05-25T10:10:00Z"
  almanac_loop_register_run "$tmp" "ralph" "b/prd.md" "$$" "fin-mid" "2026-05-25T11:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "fin-mid" "failed" "2026-05-25T11:10:00Z"
  almanac_loop_register_run "$tmp" "harden" "c.js" "$$" "fin-new" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "fin-new" "aborted" "2026-05-25T12:10:00Z"
  # A still-running run never appears under recent.
  almanac_loop_register_run "$tmp" "harden" "d.js" "$$" "still-live" "2026-05-25T12:05:00Z" >/dev/null

  out="$(almanac_loop_hub_render "$tmp" recent)"
  assert_contains "$out" "fin-new" "recent includes finished runs"
  assert_contains "$out" "aborted" "recent shows the terminal status"
  case "$out" in
    *still-live*) fail "recent must exclude running runs" ;;
  esac
  first="$(printf '%s\n' "$out" | head -1)"
  assert_contains "$first" "fin-new" "recent is ordered newest finish first"

  # limit caps the number of rows, dropping the oldest.
  out="$(almanac_loop_hub_render "$tmp" recent 2)"
  assert_eq "2" "$(printf '%s\n' "$out" | grep -c '[^[:space:]]')" "recent honors the limit"
  case "$out" in
    *fin-old*) fail "recent limit should drop the oldest run" ;;
  esac
  echo "  PASS: hub render recent newest first capped"
}

test_hub_overview_degrades_without_gum() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "ov-live" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_register_run "$tmp" "ralph" "p/prd.md" "$$" "ov-done" "2026-05-25T11:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "ov-done" "done" "2026-05-25T11:30:00Z"

  out="$(ALMANAC_NO_GUM=1 almanac_loop_hub_overview "$tmp")"
  assert_contains "$out" "Running" "overview has a running section"
  assert_contains "$out" "Recent" "overview has a recent section"
  assert_contains "$out" "ov-live" "overview lists the running run"
  assert_contains "$out" "ov-done" "overview lists the finished run"
  echo "  PASS: hub overview degrades without gum"
}

test_hub_overview_empty_registry_shows_empty_states() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  out="$(ALMANAC_NO_GUM=1 almanac_loop_hub_overview "$tmp")"
  assert_contains "$out" "no running loops" "empty registry shows a running empty-state"
  assert_contains "$out" "no recent loops" "empty registry shows a recent empty-state"
  echo "  PASS: hub overview empty registry shows empty states"
}

# --- Hub per-run actions (crit 4: watch / stop / queue-steer) ------------------

test_run_signal_file_maps_type_to_dotfile() {
  assert_eq ".ralph-stop"   "$(almanac_loop_run_signal_file ralph stop)"   "ralph stop file basename"
  assert_eq ".ralph-steer"  "$(almanac_loop_run_signal_file ralph steer)"  "ralph steer file basename"
  assert_eq ".harden-stop"  "$(almanac_loop_run_signal_file harden stop)"  "harden stop file basename"
  assert_eq ".harden-steer" "$(almanac_loop_run_signal_file harden steer)" "harden steer file basename"
  if almanac_loop_run_signal_file bogus stop >/dev/null 2>&1; then
    fail "unknown run type must return non-zero"
  fi
  if almanac_loop_run_signal_file ralph bogus >/dev/null 2>&1; then
    fail "unknown signal kind must return non-zero"
  fi
  echo "  PASS: run signal file maps type to dotfile"
}

test_run_stop_writes_stopfile_and_signals() {
  local tmp rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Dead pid so the best-effort TERM is a no-op (never signals the test process).
  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "2147483647" "stop-me" "2026-05-25T12:00:00Z" >/dev/null

  almanac_loop_run_stop "$tmp" "stop-me"
  [ -f "$tmp/.ralph-stop" ] || fail "stop must write the run type's stop file under root"

  rc=0; almanac_loop_run_stop "$tmp" "ghost" || rc=$?
  assert_eq "2" "$rc" "stopping an unknown run must return 2"
  echo "  PASS: run stop writes stop file and is best-effort"
}

test_run_steer_writes_steerfile_with_directive() {
  local tmp rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "$$" "steer-me" "2026-05-25T12:00:00Z" >/dev/null

  almanac_loop_run_steer "$tmp" "steer-me" "stop adding perf tests; the PRD scopes that out"
  [ -f "$tmp/.ralph-steer" ] || fail "steer must write the run type's steer file under root"
  assert_file_contains "$tmp/.ralph-steer" "stop adding perf tests" "steer file must carry the directive"

  rc=0; almanac_loop_run_steer "$tmp" "ghost" "do something" || rc=$?
  assert_eq "2" "$rc" "steering an unknown run must return 2"

  rc=0; almanac_loop_run_steer "$tmp" "steer-me" "   " || rc=$?
  assert_eq "4" "$rc" "a blank steer directive must be rejected"
  echo "  PASS: run steer writes steer file with directive"
}

test_run_detail_renders_run_status() {
  local tmp out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "detail-run" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "detail-run" "3" "lenses=security,perf open-blocking=2"

  out="$(almanac_loop_run_detail "$tmp" "detail-run")"
  assert_contains "$out" "detail-run" "detail shows the run id"
  assert_contains "$out" "harden" "detail shows the run type"
  assert_contains "$out" "src/app.js" "detail shows the target"
  assert_contains "$out" "3" "detail shows the live round"
  assert_contains "$out" "open-blocking=2" "detail shows the live summary"

  rc=0; almanac_loop_run_detail "$tmp" "ghost" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "detail for an unknown run must return 1"
  echo "  PASS: run detail renders run status"
}

test_run_watch_one_shot_renders_detail() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "p/prd.md" "$$" "watch-run" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_update_run_progress "$tmp" "watch-run" "5" "iteration 5"

  # No follow mode (and captured, so not a TTY): one frame, then return — never blocks.
  out="$(ALMANAC_NO_GUM=1 almanac_loop_run_watch "$tmp" "watch-run")"
  assert_contains "$out" "watch-run" "one-shot watch renders the run detail"
  assert_contains "$out" "iteration 5" "one-shot watch shows the live summary"
  echo "  PASS: run watch one-shot renders detail"
}

test_new_run_argv_ralph_composes_flags() {
  local flat
  flat="$(almanac_loop_new_run_argv ralph prd=auth-system mode=afk provider=codex model=gpt-5.5 effort=high iterations=8 oversee=off | tr '\n' ' ')"
  assert_contains "$flat" "ralph " "ralph new-run argv leads with the ralph subcommand"
  assert_contains "$flat" "--prd auth-system" "ralph argv carries --prd <name>"
  assert_contains "$flat" "--mode afk" "ralph argv carries --mode"
  assert_contains "$flat" "--provider codex" "ralph argv carries --provider"
  assert_contains "$flat" "--model gpt-5.5" "ralph argv carries --model"
  assert_contains "$flat" "--effort high" "ralph argv carries --effort"
  assert_contains "$flat" "--iterations 8" "ralph argv carries --iterations"
  assert_contains "$flat" "--no-oversee" "oversee=off adds --no-oversee"

  # Overseer left on (the default) must NOT add --no-oversee.
  flat="$(almanac_loop_new_run_argv ralph prd=auth-system mode=afk | tr '\n' ' ')"
  case "$flat" in
    *"--no-oversee"*) fail "overseer defaults to on (no --no-oversee flag when oversee unset)" ;;
  esac
  echo "  PASS: new-run argv composes ralph flags"
}

test_new_run_argv_harden_composes_loop() {
  local flat
  flat="$(almanac_loop_new_run_argv harden target=src/app.js rounds=3 | tr '\n' ' ')"
  assert_contains "$flat" "harden src/app.js --loop" "harden argv launches the convergence loop"
  assert_contains "$flat" "--rounds 3" "harden argv carries --rounds when set"

  # Rounds omitted -> no --rounds (harden falls back to its own default budget).
  flat="$(almanac_loop_new_run_argv harden target=src/app.js | tr '\n' ' ')"
  case "$flat" in
    *"--rounds"*) fail "no --rounds flag when rounds is unset" ;;
  esac
  echo "  PASS: new-run argv composes harden loop launch"
}

test_new_run_argv_rejects_unknown_and_missing() {
  local rc
  rc=0; almanac_loop_new_run_argv bogus target=x >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "an unknown run type must return 1"
  rc=0; almanac_loop_new_run_argv ralph mode=afk >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "a ralph run without a prd must return 2"
  rc=0; almanac_loop_new_run_argv harden rounds=2 >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "a harden run without a target must return 2"
  echo "  PASS: new-run argv rejects unknown type and missing required config"
}

test_new_run_env_maps_harden_config() {
  local out
  out="$(almanac_loop_new_run_env harden lenses=security,perf provider=codex model=gpt-5.5 effort=high)"
  assert_contains "$out" "HARDEN_LENSES=security,perf" "harden env carries HARDEN_LENSES"
  assert_contains "$out" "HARDEN_PROVIDER=codex" "harden env carries HARDEN_PROVIDER"
  assert_contains "$out" "HARDEN_MODEL=gpt-5.5" "harden env carries HARDEN_MODEL"
  assert_contains "$out" "HARDEN_EFFORT=high" "harden env carries HARDEN_EFFORT"

  # Ralph config rides on flags (argv), not env — so its env stream is empty.
  out="$(almanac_loop_new_run_env ralph provider=codex model=gpt-5.5)"
  assert_eq "" "$out" "ralph new-run emits no env lines (config via flags)"
  echo "  PASS: new-run env maps harden config"
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
test_worker_start_tracks_background_agent
test_worker_health_classifies_states
test_worker_health_of_reads_state
test_worker_watch_streams_event_log
test_hub_render_lists_running_with_live_status
test_hub_render_recent_newest_first_capped
test_hub_overview_degrades_without_gum
test_hub_overview_empty_registry_shows_empty_states
test_run_signal_file_maps_type_to_dotfile
test_run_stop_writes_stopfile_and_signals
test_run_steer_writes_steerfile_with_directive
test_run_detail_renders_run_status
test_run_watch_one_shot_renders_detail
test_new_run_argv_ralph_composes_flags
test_new_run_argv_harden_composes_loop
test_new_run_argv_rejects_unknown_and_missing
test_new_run_env_maps_harden_config
