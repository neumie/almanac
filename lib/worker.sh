#!/usr/bin/env bash
# worker.sh — worker orchestration (background fan-out).
#
# Per CONTEXT.md's module map, this owns the WRITE/spawn side of a run's workers:
# write/mark a worker's status.tsv, spawn a provider run in the background
# (almanac_loop_worker_start — the fan-out), and stream one worker's live event
# log (almanac_loop_worker_watch). harden's reviewer/fixer fan-out is the
# consumer; the run-level registry, the worker PATH helpers + the worker-health
# read views live in lib/run.sh (this is the orchestration layer on top of them).
#
# Dependencies (sourced idempotently): lib/core.sh (_warn + the _almanac_source_sibling
# helper used below), lib/run.sh (worker path helpers + almanac_loop_status_field +
# almanac_loop_now_utc), lib/agent.sh (the capture shape the spawned worker runs).
# core.sh loads first via the literal snippet so the sibling helper is in scope.
if ! declare -F _warn >/dev/null 2>&1; then
  __worker_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__worker_dir/core.sh"
  unset __worker_dir
fi

_almanac_source_sibling run.sh   almanac_loop_worker_status_file
_almanac_source_sibling agent.sh almanac_loop_agent_capture

# THE single source of truth for the worker-status schema: the canonical field
# list in write order. Mirrors run.sh's almanac_loop_record_fields; the generic
# almanac_loop_tsv_record_set engine iterates this list so every worker record
# carries the same keys regardless of which subset a caller supplies.
almanac_loop_worker_record_fields() {
  printf '%s\n' \
    id run_id pid provider model effort sandbox \
    prompt_file events_file result_file stderr_file \
    started_at status finished_at exit_code
}

# Set one or more worker-status fields by name, round-tripping the rest. Thin
# wrapper over the shared tsv-record engine — callers name only the fields they
# have values for; the rest are preserved (or seeded blank on first write). No
# caller enumerates the worker schema.
almanac_loop_worker_record_set() {
  almanac_loop_tsv_record_set "$(almanac_loop_worker_record_fields)" "$@"
}

almanac_loop_mark_worker_status() {
  [ "$#" -ge 5 ] || return 2

  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local status="$4"
  local exit_code="$5"
  local finished_at="${6:-}"
  local status_file

  case "$status" in
    done|failed) ;;
    *) return 3 ;;
  esac

  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  [ -f "$status_file" ] || return 2

  if [ -z "$finished_at" ]; then
    finished_at="$(almanac_loop_now_utc)"
  fi

  almanac_loop_worker_record_set "$status_file" \
    "status=$status" \
    "finished_at=$finished_at" \
    "exit_code=$exit_code"
}

almanac_loop_worker_start() {
  [ "$#" -ge 8 ] || return 2

  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local provider="$4"
  local model="$5"
  local effort="$6"
  local sandbox="$7"
  local prompt_file="$8"
  local started_at="${9:-}"
  local worker_dir status_file events_file result_file stderr_file worker_pid

  [ -n "$root" ] || return 2
  [ -n "$run_id" ] || return 2
  [ -n "$worker_id" ] || return 2
  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2

  if [ -z "$started_at" ]; then
    started_at="$(almanac_loop_now_utc)"
  fi

  worker_dir="$(almanac_loop_worker_dir "$root" "$run_id" "$worker_id")"
  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  events_file="$(almanac_loop_worker_file "$root" "$run_id" "$worker_id" "events.jsonl")"
  result_file="$(almanac_loop_worker_file "$root" "$run_id" "$worker_id" "result.txt")"
  stderr_file="$(almanac_loop_worker_file "$root" "$run_id" "$worker_id" "stderr.log")"

  if [ -e "$worker_dir" ]; then
    return 3
  fi

  mkdir -p "$worker_dir"

  (
    local status exit_code

    while [ ! -f "$status_file" ]; do
      sleep 0.05
    done

    if almanac_loop_agent_capture "$provider" "$model" "$effort" "$sandbox" "$prompt_file" "$result_file" "$events_file" 2> "$stderr_file"; then
      status="done"
      exit_code=0
    else
      exit_code="$?"
      status="failed"
    fi

    almanac_loop_mark_worker_status "$root" "$run_id" "$worker_id" "$status" "$exit_code" >/dev/null
    exit "$exit_code"
  ) &
  worker_pid="$!"

  almanac_loop_worker_record_set "$status_file" \
    "id=$worker_id" \
    "run_id=$run_id" \
    "pid=$worker_pid" \
    "provider=$provider" \
    "model=$model" \
    "effort=$effort" \
    "sandbox=${sandbox:-danger-full-access}" \
    "prompt_file=$prompt_file" \
    "events_file=$events_file" \
    "result_file=$result_file" \
    "stderr_file=$stderr_file" \
    "started_at=$started_at" \
    "status=running"

  printf '%s\n' "$worker_pid"
}

# Stream one worker's live event log (events.jsonl) so an operator can watch what
# a single reviewer/fixer is doing. Reads the worker's events-file path from its
# status.tsv (falling back to the conventional path), so it works regardless of
# where the runner allocated the log. With follow="follow" on a TTY it tails the
# log live (-f); otherwise it prints the current contents once and returns, so
# tests, pipes, and non-interactive callers never block. Returns 1 (and warns)
# when the worker has produced no event log yet.
almanac_loop_worker_watch() {
  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local follow="${4:-}"
  local status_file events_file=""

  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  if [ -f "$status_file" ]; then
    events_file="$(almanac_loop_status_field "$status_file" "events_file" || true)"
  fi
  [ -n "$events_file" ] || events_file="$(almanac_loop_worker_file "$root" "$run_id" "$worker_id" "events.jsonl")"

  if [ ! -f "$events_file" ]; then
    _warn "No event stream for worker '$worker_id' in run '$run_id' yet."
    return 1
  fi

  if [ "$follow" = "follow" ] && [ -t 1 ]; then
    tail -n +1 -f "$events_file"
  else
    cat "$events_file"
  fi
}
