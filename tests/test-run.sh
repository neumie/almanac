#!/usr/bin/env bash
# test-run.sh - run registry tests (lib/run.sh)
#
# Sources lib/run.sh DIRECTLY (its interface is its own test surface) — loop-core.sh
# was deleted and its run registry, control, worker-health, and hub read-views moved
# into lib/run.sh, alongside the run-status record it already owned. These tests pin:
#   - the run-status RECORD: canonical field list, set/get-by-name, round-trip write,
#     unknown-field rejection, identical-key-set-by-construction
#   - the run REGISTRY: register/mark/update, staleness, list/read
#   - WORKER HEALTH: the pure classifier + the gather wrapper
#   - the HUB read-views: running/recent render, overview, per-run detail/watch
#   - CONTROL: stop/steer signal-file dispatch (via the loop adapter)
#   - the NEW-RUN composer: argv/env for ralph + harden
# The worker ORCHESTRATION (background fan-out) lives in lib/worker.sh and is
# tested in tests/test-worker.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/run.sh"

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

# Portable mapfile -t replacement for macOS bash 3.2 (no `mapfile` builtin):
# splits stdin into the named array, one line per element, ignoring blanks.
split_lines_into() {
  local _arr_name="$1"
  local _line
  eval "$_arr_name=()"
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    eval "$_arr_name+=(\"\$_line\")"
  done
}

test_record_fields_is_canonical_schema() {
  local expected actual
  expected=$(printf '%s\n' \
    id type target pid status_file started_at status finished_at round summary failure_reason \
    provider model effort iterations oversee lenses rounds queue_progress \
    goal prompt exec oversee_every)
  actual="$(almanac_loop_record_fields)"
  assert_eq "$expected" "$actual" "record_fields must be the canonical run-status schema, in order"
  echo "  PASS: record_fields is the canonical schema"
}

test_record_has_field_recognises_only_canonical() {
  almanac_loop_record_has_field "id" || fail "id must be a canonical field"
  almanac_loop_record_has_field "summary" || fail "summary must be a canonical field"
  if almanac_loop_record_has_field "bogus"; then
    fail "a non-canonical field must not be recognised"
  fi
  echo "  PASS: record_has_field recognises only canonical fields"
}

test_record_set_initialises_full_key_set() {
  local tmp file keys expected
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  # Name only a subset; the record must still carry EVERY canonical key in order.
  almanac_loop_record_set "$file" "id=r1" "type=ralph" "status=running"

  keys="$(cut -f1 "$file")"
  expected="$(almanac_loop_record_fields)"
  assert_eq "$expected" "$keys" "a fresh record must carry every canonical key in order"
  assert_eq "r1" "$(almanac_loop_record_get "$file" id)" "supplied id must be set"
  assert_eq "ralph" "$(almanac_loop_record_get "$file" type)" "supplied type must be set"
  assert_eq "running" "$(almanac_loop_record_get "$file" status)" "supplied status must be set"
  assert_eq "" "$(almanac_loop_record_get "$file" summary)" "an unsupplied field must be present but blank"
  echo "  PASS: record_set initialises the full canonical key set"
}

test_record_set_round_trips_untouched_fields() {
  local tmp file
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  almanac_loop_record_set "$file" \
    "id=r1" "type=harden" "target=src/app.js" "pid=42" "status=running" "started_at=T0"
  # update only live progress
  almanac_loop_record_set "$file" "round=3" "summary=lenses=security open-blocking=2"
  # mark terminal
  almanac_loop_record_set "$file" "status=done" "finished_at=T1"

  assert_eq "r1"         "$(almanac_loop_record_get "$file" id)"          "id preserved across sets"
  assert_eq "harden"     "$(almanac_loop_record_get "$file" type)"        "type preserved"
  assert_eq "src/app.js" "$(almanac_loop_record_get "$file" target)"      "target preserved"
  assert_eq "42"         "$(almanac_loop_record_get "$file" pid)"         "pid preserved"
  assert_eq "T0"         "$(almanac_loop_record_get "$file" started_at)"  "started_at preserved"
  assert_eq "3"          "$(almanac_loop_record_get "$file" round)"       "round set"
  assert_eq "lenses=security open-blocking=2" \
    "$(almanac_loop_record_get "$file" summary)" "a value containing '=' is preserved verbatim"
  assert_eq "done"       "$(almanac_loop_record_get "$file" status)"      "status updated"
  assert_eq "T1"         "$(almanac_loop_record_get "$file" finished_at)" "finished_at set"
  echo "  PASS: record_set round-trips untouched fields"
}

test_record_get_absent_field_returns_nonzero() {
  local tmp file rc
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"
  printf 'id\tr1\n' > "$file"   # a partial record missing most keys

  rc=0; almanac_loop_record_get "$file" "summary" >/dev/null || rc=$?
  assert_eq "1" "$rc" "record_get must return 1 for an absent field"
  echo "  PASS: record_get returns non-zero for an absent field"
}

test_record_set_rejects_unknown_field() {
  local tmp file rc
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  rc=0; almanac_loop_record_set "$file" "bogus=x" || rc=$?
  assert_eq "2" "$rc" "record_set must reject a non-canonical field"
  if [ -f "$file" ]; then
    fail "record_set must not write the file when an override is rejected"
  fi
  echo "  PASS: record_set rejects unknown fields"
}

test_record_set_requires_file_arg() {
  local rc
  rc=0; almanac_loop_record_set "" "status=done" || rc=$?
  assert_eq "2" "$rc" "record_set must require a file path"
  echo "  PASS: record_set requires a file argument"
}

test_records_share_identical_key_set_by_construction() {
  local tmp ralph harden ralph_keys harden_keys
  new_tmpdir; tmp="$NEW_TMPDIR"
  ralph="$tmp/ralph.tsv"; harden="$tmp/harden.tsv"

  # Two loops set DIFFERENT subsets — the key set must still be identical because
  # both writes iterate the one canonical field list.
  almanac_loop_record_set "$ralph" \
    "id=a" "type=ralph" "target=prd.md" "status=running"
  almanac_loop_record_set "$harden" \
    "id=b" "type=harden" "target=src/x.js" "status=running" "round=1" "summary=lenses=security"

  ralph_keys="$(cut -f1 "$ralph")"
  harden_keys="$(cut -f1 "$harden")"
  assert_eq "$ralph_keys" "$harden_keys" \
    "ralph and harden records must carry an identical key set by construction"
  assert_eq "$(almanac_loop_record_fields)" "$ralph_keys" \
    "the shared key set must be the canonical schema"
  echo "  PASS: records share an identical key set by construction"
}

test_index_columns_is_a_prefix_of_record_fields() {
  # The index columns are a strict projection of the canonical schema's leading
  # block. If this assertion fails, the schema and the index have drifted apart
  # — register_run's header / mark_run_status's status-column awk will break
  # silently. Pinning the projection here is the cheaper, louder failure.
  local cols all prefix
  cols="$(almanac_loop_index_columns)"
  all="$(almanac_loop_record_fields)"
  prefix="$(printf '%s\n' "$all" | awk -v n="$(printf '%s\n' "$cols" | grep -c .)" 'NR<=n')"
  assert_eq "$cols" "$prefix" \
    "index_columns must be the leading block of record_fields (no drift)"
  echo "  PASS: index_columns is a strict prefix of record_fields"
}

test_index_column_pos_finds_canonical_field() {
  assert_eq "1" "$(almanac_loop_index_column_pos id)"          "id is column 1"
  assert_eq "2" "$(almanac_loop_index_column_pos type)"        "type is column 2"
  assert_eq "7" "$(almanac_loop_index_column_pos status)"      "status is column 7"
  assert_eq "0" "$(almanac_loop_index_column_pos finished_at)" "non-index field returns 0"
  assert_eq "0" "$(almanac_loop_index_column_pos bogus)"       "unknown field returns 0"
  echo "  PASS: index_column_pos returns 1-based position or 0"
}

test_index_row_projects_status_file_into_tab_row() {
  # Project a freshly-seeded status.tsv into the index row format and assert
  # byte-equivalence to what register_run wrote in test_registers_run_in_registry.
  # If the row format changes, this test fails before the integration test even
  # runs — locality of the row contract.
  local tmp file row expected
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  almanac_loop_record_set "$file" \
    "id=r1" "type=harden" "target=src/app.js" "pid=4242" \
    "status_file=.almanac/runs/r1/status.tsv" "started_at=2026-05-25T12:00:00Z" \
    "status=running"

  row="$(almanac_loop_index_row "$file")"
  expected=$'r1\tharden\tsrc/app.js\t4242\t.almanac/runs/r1/status.tsv\t2026-05-25T12:00:00Z\trunning'
  assert_eq "$expected" "$row" "index_row must project the canonical 7 columns, tab-joined"
  echo "  PASS: index_row projects status file into the canonical row format"
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

test_mark_run_failed_records_failure_reason() {
  local tmp status_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "9999" "ralph-fail-001" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "ralph-fail-001" "failed" "2026-05-25T12:15:00Z" "exit=1; Codex failed mid-iteration"

  status_file="$tmp/.almanac/runs/ralph-fail-001/status.tsv"
  assert_file_contains "$status_file" $'status\tfailed' "failed is the recorded status"
  assert_file_contains "$status_file" $'failure_reason\texit=1; Codex failed mid-iteration' "a failure reason passed to mark must be persisted on the record so the hub can show *why*"
  echo "  PASS: mark run failed records failure_reason"
}

test_set_run_config_writes_provider_model_effort() {
  local tmp status_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "9999" "ralph-cfg" "2026-05-26T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "ralph-cfg" \
    "provider=claude" "model=opus" "effort=xhigh" "iterations=20" "oversee=on"

  status_file="$tmp/.almanac/runs/ralph-cfg/status.tsv"
  assert_file_contains "$status_file" $'provider\tclaude' "set_run_config writes provider so hub --resume can read it back"
  assert_file_contains "$status_file" $'model\topus' "set_run_config writes model"
  assert_file_contains "$status_file" $'effort\txhigh' "set_run_config writes effort"
  assert_file_contains "$status_file" $'iterations\t20' "set_run_config writes iterations (afk)"
  assert_file_contains "$status_file" $'oversee\ton' "set_run_config writes oversee (afk)"
  echo "  PASS: set_run_config writes the config fields the resume path reads"
}

test_notify_run_end_writes_to_sink_on_terminal_transition() {
  local tmp sink
  new_tmpdir; tmp="$NEW_TMPDIR"
  sink="$tmp/notify.log"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "9999" "ralph-notify" "2026-05-26T12:00:00Z" >/dev/null
  ALMANAC_NOTIFY_TEST_SINK="$sink" \
    almanac_loop_mark_run_status "$tmp" "ralph-notify" "done" "2026-05-26T12:05:00Z"

  [ -f "$sink" ] || fail "notify sink should have been written on terminal transition"
  assert_file_contains "$sink" "almanac · ralph done" "notify title carries type + status"
  assert_file_contains "$sink" "docs/plans/x/prd.md" "notify body carries target"
  echo "  PASS: notify_run_end fires on mark-status terminal transition"
}

test_notify_run_end_respects_opt_out() {
  local tmp sink
  new_tmpdir; tmp="$NEW_TMPDIR"
  sink="$tmp/notify.log"

  almanac_loop_register_run "$tmp" "ralph" "x" "9999" "ralph-quiet" "2026-05-26T12:00:00Z" >/dev/null
  ALMANAC_NO_NOTIFY=1 ALMANAC_NOTIFY_TEST_SINK="$sink" \
    almanac_loop_mark_run_status "$tmp" "ralph-quiet" "done" "2026-05-26T12:05:00Z"

  [ ! -f "$sink" ] || fail "ALMANAC_NO_NOTIFY=1 must suppress notification entirely (sink must stay unwritten)"
  echo "  PASS: notify_run_end honors ALMANAC_NO_NOTIFY"
}

test_notify_run_end_carries_failure_reason() {
  local tmp sink
  new_tmpdir; tmp="$NEW_TMPDIR"
  sink="$tmp/notify.log"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "9999" "ralph-bad" "2026-05-26T12:00:00Z" >/dev/null
  ALMANAC_NOTIFY_TEST_SINK="$sink" \
    almanac_loop_mark_run_status "$tmp" "ralph-bad" "failed" "2026-05-26T12:05:00Z" "exit=1; Codex failed"

  assert_file_contains "$sink" "almanac · ralph failed" "failed notification carries failed status"
  assert_file_contains "$sink" "exit=1; Codex failed" "failed notification body includes failure_reason"
  echo "  PASS: notify_run_end carries failure_reason on failed runs"
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

  # worker_health_of reads only the worker's status + events_file fields; write
  # them directly (the full worker-status writer lives in lib/worker.sh).
  printf 'status\t%s\nevents_file\t%s\n' "running" "$events" > "$wdir/status.tsv"

  # Pin the clock far ahead of the just-written log so the age crosses the stall
  # threshold deterministically (no sleeps), proving the gather feeds real state
  # into the pure classifier.
  now="$(( $(date +%s) + 100000 ))"
  health="$(almanac_loop_worker_health_of "$tmp" "$run_id" "reviewer-security" "$now" 120 5)"

  assert_eq "stalled" "$health" "a running worker whose log stopped advancing reads as stalled"
  echo "  PASS: worker health of reads worker state"
}

test_trailing_repeat_does_not_cache_full_log() {
  local body
  body="$(declare -f almanac_loop_trailing_repeat)"
  case "$body" in
    *"lines[NR]"*) fail "trailing_repeat must stream the log, not cache every line in awk" ;;
  esac
  echo "  PASS: trailing repeat does not cache the full log"
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
  assert_eq ".ralph-stop"   "$(almanac_loop_signal_file ralph stop)"   "ralph stop file basename"
  assert_eq ".ralph-steer"  "$(almanac_loop_signal_file ralph steer)"  "ralph steer file basename"
  assert_eq ".harden-stop"  "$(almanac_loop_signal_file harden stop)"  "harden stop file basename"
  assert_eq ".harden-steer" "$(almanac_loop_signal_file harden steer)" "harden steer file basename"
  assert_eq ".converge-stop" "$(almanac_loop_signal_file converge stop)" "converge stop file basename"
  assert_eq ".converge-steer" "$(almanac_loop_signal_file converge steer)" "converge steer file basename"
  if almanac_loop_signal_file bogus stop >/dev/null 2>&1; then
    fail "unknown run type must return non-zero"
  fi
  if almanac_loop_signal_file ralph bogus >/dev/null 2>&1; then
    fail "unknown signal kind must return non-zero"
  fi
  echo "  PASS: run signal file maps type to dotfile"
}

test_consume_signal_returns_contents_and_deletes_file() {
  local tmp file out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Steer-shaped consume: contents flow through, file is removed.
  file="$tmp/.harden-steer"
  printf 'redirect: stop adding perf tests\n' > "$file"
  out="$(almanac_loop_consume_signal harden "$tmp" steer)"
  rc=$?
  assert_eq "0" "$rc" "consume must return 0 when the signal file exists"
  assert_eq "redirect: stop adding perf tests" "$out" \
    "consume must emit the file's contents on stdout"
  [ ! -f "$file" ] || fail "consume must delete the signal file after reading"

  # Stop-shaped consume: an empty file is still 'present', returns 0 with empty
  # stdout. Matches harden's pre-deepening _consume_stop semantics (touch + rm,
  # no content carried), so a `touch .harden-stop` still trips the loop.
  file="$tmp/.harden-stop"
  : > "$file"
  out="$(almanac_loop_consume_signal harden "$tmp" stop)"
  rc=$?
  assert_eq "0" "$rc" "consume must return 0 for an empty signal file"
  assert_eq "" "$out" "consume must emit nothing for an empty signal file"
  [ ! -f "$file" ] || fail "consume must delete an empty signal file too"

  echo "  PASS: consume signal returns contents and deletes the file"
}

test_consume_signal_returns_nonzero_when_absent() {
  local tmp out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Missing file: nonzero return, no output, no side effects.
  rc=0
  out="$(almanac_loop_consume_signal harden "$tmp" steer)" || rc=$?
  assert_eq "1" "$rc" "consume must return 1 when the signal file is absent"
  assert_eq "" "$out" "consume must emit nothing when the signal file is absent"

  # Unknown kind/type: nonzero return via almanac_loop_run_control_file.
  rc=0
  out="$(almanac_loop_consume_signal bogus "$tmp" stop)" || rc=$?
  [ "$rc" -ne 0 ] || fail "consume must return non-zero for unknown loop type"

  rc=0
  out="$(almanac_loop_consume_signal harden "$tmp" bogus)" || rc=$?
  [ "$rc" -ne 0 ] || fail "consume must return non-zero for unknown signal kind"

  echo "  PASS: consume signal returns nonzero when absent or unknown"
}

test_consume_signal_routes_through_per_run_base() {
  local tmp plan_a plan_b out rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Converge scopes its signals to a per-run plan_dir (not $root) so a steer
  # queued for run A does not bleed into run B that happens to share the
  # workspace. Mirror that scoping by passing distinct bases.
  plan_a="$tmp/plan-a"
  plan_b="$tmp/plan-b"
  mkdir -p "$plan_a" "$plan_b"

  printf 'directive for A\n' > "$plan_a/.converge-steer"
  printf 'directive for B\n' > "$plan_b/.converge-steer"

  out="$(almanac_loop_consume_signal converge "$plan_a" steer)"
  rc=$?
  assert_eq "0" "$rc" "per-base consume must succeed for plan A"
  assert_eq "directive for A" "$out" "per-base consume must return A's directive"
  [ ! -f "$plan_a/.converge-steer" ] || fail "consuming A must delete A's signal"
  [ -f "$plan_b/.converge-steer" ] || fail "consuming A must NOT touch B's signal"

  echo "  PASS: consume signal routes through per-run base"
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

test_run_stop_does_not_signal_recorded_pid() {
  local tmp pid
  new_tmpdir
  tmp="$NEW_TMPDIR"

  sleep 60 &
  pid="$!"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "$pid" "stop-live" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_run_stop "$tmp" "stop-live"
  sleep 0.2

  if ! kill -0 "$pid" 2>/dev/null; then
    fail "hub stop must not TERM project-controlled recorded pids"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "  PASS: run stop does not signal recorded pid"
}

test_run_stop_ignores_finished_runs() {
  local tmp pid rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  sleep 60 &
  pid="$!"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/x/prd.md" "$pid" "done-run" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "done-run" "done" "2026-05-25T12:01:00Z"

  rc=0; almanac_loop_run_stop "$tmp" "done-run" || rc=$?
  assert_eq "4" "$rc" "stopping a terminal run must return 4"
  sleep 0.2
  if ! kill -0 "$pid" 2>/dev/null; then
    fail "stopping a finished run must not TERM a reused recorded pid"
  fi
  [ ! -f "$tmp/.ralph-stop" ] || fail "terminal runs should not receive a new stop file"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "  PASS: run stop ignores finished runs"
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
  rc=0; almanac_loop_new_run_argv converge exec="echo hi" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "a converge run without a goal must return 2"
  rc=0; almanac_loop_new_run_argv converge goal="ship it" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "a converge run without a prompt or exec must return 2"
  echo "  PASS: new-run argv rejects unknown type and missing required config"
}

test_new_run_argv_converge_composes_flags() {
  local flat rc

  # Exec mode
  flat="$(almanac_loop_new_run_argv converge \
    goal="ship it" exec="echo hi" rounds=5 oversee=off oversee_every=2 | tr '\n' ' ')"
  assert_contains "$flat" "converge " "argv starts with converge subcommand"
  assert_contains "$flat" "--goal ship it" "argv carries --goal"
  assert_contains "$flat" "--exec echo hi" "argv carries --exec"
  assert_contains "$flat" "--rounds 5" "argv carries --rounds"
  assert_contains "$flat" "--no-oversee" "argv carries --no-oversee when oversee=off"
  assert_contains "$flat" "--oversee-every 2" "argv carries --oversee-every"
  # Provider/model/effort are env, NOT argv (same split as harden)
  case "$flat" in
    *"--provider"*) fail "provider must ride on env, not argv" ;;
    *"--model"*)    fail "model must ride on env, not argv" ;;
    *"--effort"*)   fail "effort must ride on env, not argv" ;;
  esac

  # Prompt mode
  flat="$(almanac_loop_new_run_argv converge \
    goal="ship it" prompt="/almanac:codebase-improve" rounds=3 | tr '\n' ' ')"
  assert_contains "$flat" "--prompt /almanac:codebase-improve" "argv carries --prompt"
  assert_contains "$flat" "--rounds 3" "prompt-mode argv still carries --rounds"
  case "$flat" in
    *"--exec"*) fail "prompt-mode argv must NOT carry --exec" ;;
  esac

  # Mutex: both prompt and exec → 2
  rc=0; almanac_loop_new_run_argv converge goal="g" prompt="p" exec="e" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "converge with both prompt and exec must return 2 (mutex)"

  # oversee=on (or omitted) must NOT emit --no-oversee
  flat="$(almanac_loop_new_run_argv converge goal="g" prompt="/x" | tr '\n' ' ')"
  case "$flat" in
    *"--no-oversee"*) fail "default (overseer on) must NOT emit --no-oversee" ;;
  esac
  echo "  PASS: new-run argv composes converge flags"
}

test_new_run_env_maps_converge_config() {
  local out
  out="$(almanac_loop_new_run_env converge provider=codex model=gpt-5.5 effort=high)"
  assert_contains "$out" "CONVERGE_PROVIDER=codex" "converge env carries CONVERGE_PROVIDER"
  assert_contains "$out" "CONVERGE_MODEL=gpt-5.5" "converge env carries CONVERGE_MODEL"
  assert_contains "$out" "CONVERGE_EFFORT=high"   "converge env carries CONVERGE_EFFORT"
  echo "  PASS: new-run env maps converge config"
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

test_status_to_opts_inverts_new_run_for_ralph() {
  local tmp status_file opts flat
  new_tmpdir; tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/auth-system/prd.md" "$$" "ralph-r" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "ralph-r" \
    "provider=codex" "model=gpt-5.5" "effort=high" "iterations=8" "oversee=off"
  status_file="$(almanac_loop_run_status_file "$tmp" "ralph-r")"

  opts="$(almanac_loop_adapter_call ralph status_to_opts "$status_file")"
  case "$opts" in *prd=auth-system*) ;; *) fail "ralph status_to_opts must derive prd from target dirname" ;; esac
  case "$opts" in *mode=afk*)         ;; *) fail "ralph status_to_opts must emit mode=afk when iterations is set" ;; esac
  case "$opts" in *iterations=8*)     ;; *) fail "ralph status_to_opts must carry iterations" ;; esac
  case "$opts" in *provider=codex*)   ;; *) fail "ralph status_to_opts must carry provider" ;; esac
  case "$opts" in *oversee=off*)      ;; *) fail "ralph status_to_opts must carry oversee=off" ;; esac

  # Round-trip: feeding the emitted opts into new_run_argv must produce a usable
  # ralph launcher invocation — the hub depends on this inversion.
  split_lines_into opt_arr <<< "$opts"
  flat="$(almanac_loop_new_run_argv ralph "${opt_arr[@]}" | tr '\n' ' ')"
  assert_contains "$flat" "--prd auth-system" "round-trip emits --prd"
  assert_contains "$flat" "--iterations 8"    "round-trip emits --iterations"
  echo "  PASS: status_to_opts inverts ralph status into new_run opts"
}

test_status_to_opts_handles_ralph_once_mode() {
  local tmp status_file opts
  new_tmpdir; tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/auth-system/prd.md" "$$" "ralph-once" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "ralph-once" "provider=codex"
  status_file="$(almanac_loop_run_status_file "$tmp" "ralph-once")"

  opts="$(almanac_loop_adapter_call ralph status_to_opts "$status_file")"
  case "$opts" in *mode=once*) ;; *) fail "ralph status_to_opts must emit mode=once when iterations is absent" ;; esac
  case "$opts" in *mode=afk*)  fail "no iterations → no mode=afk" ;; *) ;; esac
  echo "  PASS: status_to_opts treats missing iterations as once-mode"
}

test_status_to_opts_inverts_new_run_for_harden() {
  local tmp status_file opts flat
  new_tmpdir; tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "harden" "src/app.js" "$$" "harden-r" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "harden-r" \
    "provider=codex" "model=gpt-5.5" "effort=high" "lenses=security,perf" "rounds=3"
  status_file="$(almanac_loop_run_status_file "$tmp" "harden-r")"

  opts="$(almanac_loop_adapter_call harden status_to_opts "$status_file")"
  case "$opts" in *target=src/app.js*)   ;; *) fail "harden status_to_opts must carry target" ;; esac
  case "$opts" in *lenses=security,perf*) ;; *) fail "harden status_to_opts must carry lenses" ;; esac
  case "$opts" in *rounds=3*)            ;; *) fail "harden status_to_opts must carry rounds" ;; esac
  case "$opts" in *provider=codex*)      ;; *) fail "harden status_to_opts must carry provider" ;; esac

  split_lines_into opt_arr <<< "$opts"
  flat="$(almanac_loop_new_run_argv harden "${opt_arr[@]}" | tr '\n' ' ')"
  assert_contains "$flat" "harden src/app.js --loop" "round-trip relaunches the harden loop on the same target"
  assert_contains "$flat" "--rounds 3" "round-trip carries --rounds"
  echo "  PASS: status_to_opts inverts harden status into new_run opts"
}

test_status_to_opts_inverts_new_run_for_converge() {
  local tmp status_file opts flat
  new_tmpdir; tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "converge" "docs/plans/converge/x" "$$" "converge-r" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "converge-r" \
    "goal=ship it" "prompt=/almanac:codebase-improve" "rounds=5" \
    "provider=codex" "model=gpt-5.5" "effort=high" "oversee=off" "oversee_every=2"
  status_file="$(almanac_loop_run_status_file "$tmp" "converge-r")"

  opts="$(almanac_loop_adapter_call converge status_to_opts "$status_file")"
  case "$opts" in *"goal=ship it"*)                          ;; *) fail "converge status_to_opts must carry goal" ;; esac
  case "$opts" in *prompt=/almanac:codebase-improve*)        ;; *) fail "converge status_to_opts must carry prompt" ;; esac
  case "$opts" in *rounds=5*)                                ;; *) fail "converge status_to_opts must carry rounds" ;; esac
  case "$opts" in *oversee=off*)                             ;; *) fail "converge status_to_opts must carry oversee=off" ;; esac
  case "$opts" in *oversee_every=2*)                         ;; *) fail "converge status_to_opts must carry oversee_every" ;; esac

  split_lines_into opt_arr <<< "$opts"
  flat="$(almanac_loop_new_run_argv converge "${opt_arr[@]}" | tr '\n' ' ')"
  assert_contains "$flat" "--goal ship it" "round-trip carries --goal"
  assert_contains "$flat" "--prompt /almanac:codebase-improve" "round-trip carries --prompt"
  assert_contains "$flat" "--no-oversee" "round-trip carries --no-oversee"
  assert_contains "$flat" "--oversee-every 2" "round-trip carries --oversee-every"
  echo "  PASS: status_to_opts inverts converge status into new_run opts"
}

test_launch_backed_signals_launcher_only_loops() {
  # ralph runs through the launcher (which accepts --yes); harden + converge exec
  # their direct runners and would reject --yes. The hub's resume path uses this
  # verb to decide whether to append --yes — the only place that policy lives.
  local rc
  rc=0; almanac_loop_adapter_call ralph launch_backed >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "ralph adapter must declare itself launcher-backed"
  rc=0; almanac_loop_adapter_call harden launch_backed >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "harden adapter must NOT implement launch_backed (direct-runner)"
  rc=0; almanac_loop_adapter_call converge launch_backed >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "converge adapter must NOT implement launch_backed (direct-runner)"
  echo "  PASS: launch_backed signals launcher-only loops"
}

test_hub_stats_groups_by_type_provider_model() {
  local tmp out
  new_tmpdir; tmp="$NEW_TMPDIR"

  # 3 ralph runs with claude/opus: 2 done, 1 failed → expect 67% success.
  almanac_loop_register_run "$tmp" "ralph" "demo" "1" "r1" "2026-05-26T10:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "r1" "provider=claude" "model=opus"
  almanac_loop_mark_run_status "$tmp" "r1" "done" "2026-05-26T10:30:00Z"
  almanac_loop_register_run "$tmp" "ralph" "demo" "2" "r2" "2026-05-26T11:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "r2" "provider=claude" "model=opus"
  almanac_loop_mark_run_status "$tmp" "r2" "done" "2026-05-26T11:30:00Z"
  almanac_loop_register_run "$tmp" "ralph" "demo" "3" "r3" "2026-05-26T12:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "r3" "provider=claude" "model=opus"
  almanac_loop_mark_run_status "$tmp" "r3" "failed" "2026-05-26T12:30:00Z"

  # 1 harden run with codex/gpt-5.4: done → expect 100%.
  almanac_loop_register_run "$tmp" "harden" "src/x" "4" "h1" "2026-05-26T13:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "h1" "provider=codex" "model=gpt-5.4"
  almanac_loop_mark_run_status "$tmp" "h1" "done" "2026-05-26T13:30:00Z"

  out=$(almanac_loop_hub_stats "$tmp")
  assert_contains "$out" "type" "stats prints a header row"
  assert_contains "$out" "ralph" "stats includes the ralph (claude/opus) bucket"
  assert_contains "$out" "harden" "stats includes the harden (codex/gpt-5.4) bucket"
  assert_contains "$out" "opus" "stats groups by model"
  assert_contains "$out" "67%" "stats computes success rate (2 done / 3 ralph runs = 67%)"
  assert_contains "$out" "100%" "stats computes 100% for the single harden done run"
  echo "  PASS: hub_stats groups by (type, provider, model) and reports counts + success rate"
}

test_hub_stats_empty_registry_returns_nonzero() {
  local tmp rc
  new_tmpdir; tmp="$NEW_TMPDIR"
  rc=0; almanac_loop_hub_stats "$tmp" >/dev/null || rc=$?
  assert_eq "1" "$rc" "empty registry → no rows → returns 1 so the caller can print an empty-state line"
  echo "  PASS: hub_stats returns 1 on empty registry"
}

# --- Worker path helpers ------------------------------------------------------
#
# Pin almanac_loop_worker_{dir,status_file,file} in isolation. These three pure
# path-builders sit beneath every worker write/read in the engine — harden's
# reviewer/fixer fan-out, the worker watch, the hub's worker views — so a single
# format bug (trailing slash, missing slug, etc) would silently fan out across
# the system. The lifecycle tests above exercise them transitively; these tests
# pin the path shape directly.

test_worker_dir_composes_registry_run_worker_with_slug() {
  local tmp expected actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  expected="$tmp/.almanac/runs/r1/workers/reviewer-correctness"
  actual="$(almanac_loop_worker_dir "$tmp" "r1" "reviewer-correctness")"
  assert_eq "$expected" "$actual" "worker_dir = <registry>/<run_id>/workers/<slug(worker_id)>"
  echo "  PASS: worker_dir composes <registry>/<run_id>/workers/<slug>"
}

test_worker_dir_slugifies_the_worker_id() {
  local tmp actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  # Upper-case, spaces, and punctuation must collapse through almanac_loop_slug
  # so the on-disk path is file-safe regardless of how the caller spells the id.
  actual="$(almanac_loop_worker_dir "$tmp" "r1" "Reviewer / Edge & Tests")"
  assert_eq "$tmp/.almanac/runs/r1/workers/reviewer-edge-tests" "$actual" \
    "worker_dir must slugify the worker_id (lowercase, non-alnum runs → single dash, trim)"
  echo "  PASS: worker_dir slugifies the worker_id segment"
}

test_worker_status_file_is_status_tsv_under_worker_dir() {
  local tmp expected actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  expected="$tmp/.almanac/runs/r1/workers/fixer/status.tsv"
  actual="$(almanac_loop_worker_status_file "$tmp" "r1" "fixer")"
  assert_eq "$expected" "$actual" "worker_status_file = <worker_dir>/status.tsv"
  echo "  PASS: worker_status_file is status.tsv under worker_dir"
}

test_worker_file_joins_filename_under_worker_dir() {
  local tmp expected actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  expected="$tmp/.almanac/runs/r1/workers/reviewer-security/events.log"
  actual="$(almanac_loop_worker_file "$tmp" "r1" "reviewer-security" "events.log")"
  assert_eq "$expected" "$actual" "worker_file = <worker_dir>/<filename>"
  echo "  PASS: worker_file appends a named file under worker_dir"
}

test_plan_dir_composes_root_docs_plans_type_slug() {
  local tmp actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  actual="$(almanac_loop_plan_dir "harden" "$tmp" "src-app-js")"
  assert_eq "$tmp/docs/plans/harden/src-app-js" "$actual" \
    "plan_dir = <root>/docs/plans/<type>/<slug>"
  actual="$(almanac_loop_plan_dir "converge" "$tmp" "say-hello")"
  assert_eq "$tmp/docs/plans/converge/say-hello" "$actual" \
    "plan_dir composes the same path shape for every loop type"
  echo "  PASS: plan_dir composes <root>/docs/plans/<type>/<slug>"
}

test_plan_container_composes_root_docs_plans_type() {
  local tmp actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  actual="$(almanac_loop_plan_container "harden" "$tmp")"
  assert_eq "$tmp/docs/plans/harden" "$actual" \
    "plan_container = <root>/docs/plans/<type>"
  actual="$(almanac_loop_plan_container "converge" "$tmp")"
  assert_eq "$tmp/docs/plans/converge" "$actual" \
    "plan_container composes the same parent shape for every loop type"
  echo "  PASS: plan_container composes <root>/docs/plans/<type>"
}

test_plan_dir_composes_off_plan_container() {
  local tmp container plan_dir
  new_tmpdir; tmp="$NEW_TMPDIR"
  # The container is the parent of every per-run plan dir for a type — the
  # invariant that justifies the seam. If plan_dir ever forks its own prefix
  # (instead of composing off plan_container), this assertion catches drift.
  container="$(almanac_loop_plan_container "converge" "$tmp")"
  plan_dir="$(almanac_loop_plan_dir "converge" "$tmp" "any-slug")"
  assert_eq "$container/any-slug" "$plan_dir" \
    "plan_dir must equal <plan_container>/<slug>"
  echo "  PASS: plan_dir composes off plan_container (one prefix definition)"
}

test_plan_dir_passes_through_caller_slug() {
  local tmp actual
  new_tmpdir; tmp="$NEW_TMPDIR"
  # plan_dir is a pure path joiner — it must NOT re-slugify. Caller-supplied
  # slugs (raw strings) are emitted verbatim so the helper stays single-purpose.
  actual="$(almanac_loop_plan_dir "harden" "$tmp" "Already Has Spaces")"
  assert_eq "$tmp/docs/plans/harden/Already Has Spaces" "$actual" \
    "plan_dir must not slugify its slug argument (slugification is the caller's job)"
  echo "  PASS: plan_dir does not re-slugify its slug argument"
}

test_worker_paths_agree_on_shared_directory() {
  local tmp dir status_file event_file
  new_tmpdir; tmp="$NEW_TMPDIR"
  dir="$(almanac_loop_worker_dir "$tmp" "r1" "reviewer-perf")"
  status_file="$(almanac_loop_worker_status_file "$tmp" "r1" "reviewer-perf")"
  event_file="$(almanac_loop_worker_file "$tmp" "r1" "reviewer-perf" "events.log")"
  # All three must root in the same worker dir — if one diverged, every
  # status/event mkdir would land in the wrong place. Pin the agreement.
  assert_eq "$dir/status.tsv" "$status_file" "status_file must live under worker_dir"
  assert_eq "$dir/events.log" "$event_file"  "worker_file must live under worker_dir"
  echo "  PASS: worker_dir / worker_status_file / worker_file share the same parent"
}

echo "=== Run-Status Record Tests ==="
test_record_fields_is_canonical_schema
test_record_has_field_recognises_only_canonical
test_record_set_initialises_full_key_set
test_record_set_round_trips_untouched_fields
test_record_get_absent_field_returns_nonzero
test_record_set_rejects_unknown_field
test_record_set_requires_file_arg
test_records_share_identical_key_set_by_construction
test_index_columns_is_a_prefix_of_record_fields
test_index_column_pos_finds_canonical_field
test_index_row_projects_status_file_into_tab_row

echo ""
echo "=== Run Registry / Worker-Health / Hub / Control Tests ==="
test_registers_run_in_registry
test_marks_registered_run_done
test_update_run_progress_records_round_and_summary
test_mark_run_aborted_preserves_progress
test_mark_run_failed_records_failure_reason
test_set_run_config_writes_provider_model_effort
test_notify_run_end_writes_to_sink_on_terminal_transition
test_notify_run_end_respects_opt_out
test_notify_run_end_carries_failure_reason
test_run_is_stale_detects_dead_pid
test_list_runs_returns_all_registered_runs
test_read_run_returns_single_run_status
test_worker_health_classifies_states
test_worker_health_of_reads_state
test_trailing_repeat_does_not_cache_full_log
test_hub_render_lists_running_with_live_status
test_hub_render_recent_newest_first_capped
test_hub_overview_degrades_without_gum
test_hub_overview_empty_registry_shows_empty_states
test_run_signal_file_maps_type_to_dotfile
test_consume_signal_returns_contents_and_deletes_file
test_consume_signal_returns_nonzero_when_absent
test_consume_signal_routes_through_per_run_base
test_run_stop_writes_stopfile_and_signals
test_run_stop_does_not_signal_recorded_pid
test_run_stop_ignores_finished_runs
test_run_steer_writes_steerfile_with_directive
test_run_detail_renders_run_status
test_run_watch_one_shot_renders_detail
test_new_run_argv_ralph_composes_flags
test_new_run_argv_harden_composes_loop
test_new_run_argv_rejects_unknown_and_missing
test_new_run_argv_converge_composes_flags
test_new_run_env_maps_harden_config
test_new_run_env_maps_converge_config
test_status_to_opts_inverts_new_run_for_ralph
test_status_to_opts_handles_ralph_once_mode
test_status_to_opts_inverts_new_run_for_harden
test_status_to_opts_inverts_new_run_for_converge
test_launch_backed_signals_launcher_only_loops
test_hub_stats_groups_by_type_provider_model
test_hub_stats_empty_registry_returns_nonzero

echo ""
echo "=== Worker Path Helper Tests ==="
test_worker_dir_composes_registry_run_worker_with_slug
test_worker_dir_slugifies_the_worker_id
test_worker_status_file_is_status_tsv_under_worker_dir
test_worker_file_joins_filename_under_worker_dir
test_plan_dir_composes_root_docs_plans_type_slug
test_plan_container_composes_root_docs_plans_type
test_plan_dir_composes_off_plan_container
test_plan_dir_passes_through_caller_slug
test_worker_paths_agree_on_shared_directory

echo ""
echo "All run registry tests passed."
