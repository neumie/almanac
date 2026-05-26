#!/usr/bin/env bash
# run.sh — the run registry: the run-status record, registry, control, worker
# health, and the hub's read views, owned in one module (per CONTEXT.md's module
# map). loop-core.sh (the old god-module) is deleted; this is where its registry/
# control/worker-health/hub-view concerns now live (the worker orchestration /
# background fan-out lives in lib/worker.sh).
#
# A run-status *record* is a per-run status.tsv — one `key<TAB>value` line per
# field. This module owns the CANONICAL FIELD LIST and the only set/get-by-name
# accessors for it, so the run-status contract — every run (ralph or harden)
# carries exactly this key set, in this order — is enforced *by construction*:
# a caller names only the fields it has values for; the record fills in the rest,
# and no writer ever enumerates the schema by hand.
#
# No lib/core.sh dependency (uses only printf/read/awk/etc), so the record +
# registry are their own test surface — tests/test-run.sh sources this file
# directly. The hub read-views compose the gum-or-plain UI seam (lib/ui.sh) and
# the per-run control dispatches each loop's signal files through its adapter
# (lib/loops.sh), so source those two idempotently — they are self-contained
# (no core.sh) too. pwd -P resolves the install symlink so the siblings are found
# from either path.
if ! declare -F almanac_loop_ui_render >/dev/null 2>&1; then
  __run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/ui.sh
  source "$__run_dir/ui.sh"
  unset __run_dir
fi

if ! declare -F almanac_loop_adapter_call >/dev/null 2>&1; then
  __run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/loops.sh
  source "$__run_dir/loops.sh"
  unset __run_dir
fi

# THE single source of truth for the run-status schema: the canonical field list
# in write order. record_set iterates exactly this list, so every record carries
# the same keys regardless of which subset a caller supplies. The first seven are
# also the registry's index.tsv columns (the lightweight list pointer); the last
# three (finished_at/round/summary) are the per-run detail the index omits.
almanac_loop_record_fields() {
  printf '%s\n' \
    id type target pid status_file started_at status finished_at round summary failure_reason \
    provider model effort iterations oversee lenses rounds queue_progress
}

# True when NAME is a canonical run-status field. Lets record_set reject a typo
# rather than silently writing a key no reader ever looks for.
almanac_loop_record_has_field() {
  local wanted="$1" field
  while IFS= read -r field; do
    [ "$field" = "$wanted" ] && return 0
  done <<< "$(almanac_loop_record_fields)"
  return 1
}

# Get one field from a record FILE by name. Prints the value (which may itself
# contain tabs — reassembled from the trailing columns) and returns 0; returns 1
# when the field is absent. This is the generic tab-field reader for the run
# registry; almanac_loop_status_field (below) is a thin alias over it for the
# worker-status and hub read paths.
almanac_loop_record_get() {
  local file="$1" wanted="$2" key value rest

  while IFS=$'\t' read -r key value rest; do
    if [ "$key" = "$wanted" ]; then
      if [ -n "${rest:-}" ]; then
        value="${value}"$'\t'"${rest}"
      fi
      printf '%s\n' "$value"
      return 0
    fi
  done < "$file"

  return 1
}

# Set one or more fields by name, round-tripping the rest. Each argument is a
# `field=value` pair (the value may itself contain `=`). The record is rewritten
# with the FULL canonical key set in canonical order: every canonical field
# already in the file is preserved unless overridden, and a not-yet-existing file
# is initialised with every key (blank where unset). So `register` seeds the
# record by naming only its known fields, while `mark`/`update` change only
# theirs and leave the rest intact — no caller enumerates the schema. Returns 2
# on a missing file argument or a `field=value` whose field is not canonical.
almanac_loop_record_set() {
  local file="$1"
  shift
  [ -n "$file" ] || return 2

  local pair pfield field cur val out=""
  local have_file=0
  if [ -f "$file" ]; then
    have_file=1
  fi

  # Reject any override outside the canonical schema before writing anything.
  for pair in "$@"; do
    pfield="${pair%%=*}"
    almanac_loop_record_has_field "$pfield" || return 2
  done

  while IFS= read -r field; do
    [ -n "$field" ] || continue
    cur=""
    if [ "$have_file" = 1 ]; then
      cur="$(almanac_loop_record_get "$file" "$field" || true)"
    fi
    val="$cur"
    for pair in "$@"; do
      pfield="${pair%%=*}"
      if [ "$pfield" = "$field" ]; then
        val="${pair#*=}"
      fi
    done
    out="${out}${field}"$'\t'"${val}"$'\n'
  done <<< "$(almanac_loop_record_fields)"

  printf '%s' "$out" > "$file"
}

almanac_loop_slug() {
  local raw="$1"
  local slug

  slug="$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"

  if [ -z "$slug" ]; then
    slug="run"
  fi

  printf '%s\n' "$slug"
}

almanac_loop_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

almanac_loop_run_id() {
  local type="$1"
  local target="$2"
  local compact_now

  compact_now="$(date -u '+%Y%m%dT%H%M%SZ')"
  printf '%s-%s-%s-%s\n' \
    "$(almanac_loop_slug "$type")" \
    "$(almanac_loop_slug "$target")" \
    "$compact_now" \
    "$$"
}

almanac_loop_registry_dir() {
  local root="${1:-.}"

  if [ "$root" != "/" ]; then
    root="${root%/}"
  fi

  printf '%s/.almanac/runs\n' "$root"
}

almanac_loop_run_status_file() {
  local root="$1"
  local run_id="$2"

  printf '%s/%s/status.tsv\n' "$(almanac_loop_registry_dir "$root")" "$run_id"
}

almanac_loop_run_status_relpath() {
  local run_id="$1"

  printf '.almanac/runs/%s/status.tsv\n' "$run_id"
}

almanac_loop_run_index_file() {
  local root="$1"

  printf '%s/index.tsv\n' "$(almanac_loop_registry_dir "$root")"
}

# The run's status.tsv blob — the per-run detail view the hub reads — is the
# run-status RECORD: its canonical field list and the set/get-by-name accessors
# (almanac_loop_record_*) live above. The registry functions below seed and
# update it through that record, so the schema (id/type/target/pid/
# status_file/started_at/status + the live finished_at/round/summary) is never
# enumerated here. The index.tsv is a separate lightweight list pointer (the
# record's first seven fields), written below.

# Thin alias for the record's generic tab-field reader, kept for the worker-status
# and hub read paths that read a field by name. The implementation (and the
# run-status record's canonical getter) is almanac_loop_record_get, above.
almanac_loop_status_field() {
  almanac_loop_record_get "$@"
}

almanac_loop_register_run() {
  [ "$#" -ge 4 ] || return 2

  local root="$1"
  local type="$2"
  local target="$3"
  local pid="$4"
  local run_id="${5:-}"
  local started_at="${6:-}"
  local registry_dir run_dir status_file status_rel index_file

  [ -n "$root" ] || return 2
  [ -n "$type" ] || return 2
  [ -n "$target" ] || return 2
  [ -n "$pid" ] || return 2

  if [ -z "$run_id" ]; then
    run_id="$(almanac_loop_run_id "$type" "$target")"
  fi

  if [ -z "$started_at" ]; then
    started_at="$(almanac_loop_now_utc)"
  fi

  registry_dir="$(almanac_loop_registry_dir "$root")"
  run_dir="$registry_dir/$run_id"
  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  status_rel="$(almanac_loop_run_status_relpath "$run_id")"
  index_file="$(almanac_loop_run_index_file "$root")"

  if [ -e "$run_dir" ]; then
    return 3
  fi

  mkdir -p "$run_dir"

  if [ ! -f "$index_file" ]; then
    printf 'id\ttype\ttarget\tpid\tstatus_file\tstarted_at\tstatus\n' > "$index_file"
  fi

  # Seed the run-status record by naming only the fields known at launch; the
  # record fills the rest (finished_at/round/summary blank) from the canonical
  # schema. The index row is the lightweight pointer (the record's first seven
  # fields).
  almanac_loop_record_set "$status_file" "id=$run_id" "type=$type" "target=$target" "pid=$pid" "status_file=$status_rel" "started_at=$started_at" "status=running"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "running" >> "$index_file"
  printf '%s\n' "$run_id"
}

# Set config fields on a run after registration. Thin convenience over record_set
# that names intent: "store the resolved launch config so resume can rebuild it."
# Accepts any subset of the config keys (provider/model/effort/iterations/oversee
# for ralph; provider/model/effort/lenses/rounds for harden). Blank values are
# acceptable — record_set keeps the field present-but-blank. Returns 2 when the
# run is unknown so callers can guard without aborting.
almanac_loop_set_run_config() {
  [ "$#" -ge 3 ] || return 2
  local root="$1" run_id="$2"; shift 2
  local status_file
  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2
  almanac_loop_record_set "$status_file" "$@"
}

almanac_loop_mark_run_status() {
  [ "$#" -ge 3 ] || return 2

  local root="$1"
  local run_id="$2"
  local status="$3"
  local finished_at="${4:-}"
  local reason="${5:-}"
  local status_file index_file tmp

  case "$status" in
    done|failed|aborted) ;;
    *) return 3 ;;
  esac

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  index_file="$(almanac_loop_run_index_file "$root")"

  [ -f "$status_file" ] || return 2
  [ -f "$index_file" ] || return 2

  if [ -z "$finished_at" ]; then
    finished_at="$(almanac_loop_now_utc)"
  fi

  tmp="$(mktemp "${index_file}.XXXXXX")"
  if ! awk -v run_id="$run_id" -v status="$status" '
    BEGIN { FS = OFS = "\t" }
    NR == 1 { print; next }
    $1 == run_id { $7 = status; found = 1 }
    { print }
    END { if (!found) exit 4 }
  ' "$index_file" > "$tmp"; then
    rm -f "$tmp"
    return 2
  fi
  mv "$tmp" "$index_file"

  # Set only the lifecycle fields; record_set round-trips id/type/target/pid/
  # status_file/started_at/round/summary, so the schema is never re-enumerated.
  # An optional 5th arg supplies a one-line failure reason (typically "exit=N"
  # plus a log-tail hint) so the hub can show *why* a run failed, not just that
  # it did. Blank reason → leave the field as-is (running runs start blank).
  local _fields=("status=$status" "finished_at=$finished_at")
  [ -n "$reason" ] && _fields+=("failure_reason=$reason")
  almanac_loop_record_set "$status_file" "${_fields[@]}"
  # Best-effort end-of-run notification (macOS osascript / Linux notify-send /
  # terminal-bell fallback). Opt out via ALMANAC_NO_NOTIFY=1. Notification
  # trouble never sinks the mark — if osascript is missing or notify-send
  # errors, the run is still correctly marked.
  almanac_loop_notify_run_end "$root" "$run_id" >/dev/null 2>&1 || true
}

# Tell the user a run reached a terminal state. Reads the just-written record so
# the notification carries type/status/target (and failure_reason on a failed
# run). Dispatch order: macOS osascript → Linux notify-send → terminal bell
# fallback (so you at least *hear* a finish on a bare server). Opt out entirely
# with ALMANAC_NO_NOTIFY=1. ALMANAC_NOTIFY_TEST_SINK (a file path) replaces the
# OS dispatcher with a write to that file, so tests can assert title+body
# without a desktop environment.
almanac_loop_notify_run_end() {
  [ -z "${ALMANAC_NO_NOTIFY:-}" ] || return 0
  # Skip when there's no terminal attached (tests, daemons, captured output) —
  # nobody to notify. The test sink bypasses this so unit tests can still assert
  # the dispatch path without a TTY.
  if [ -z "${ALMANAC_NOTIFY_TEST_SINK:-}" ]; then
    [ -t 2 ] || return 0
  fi
  local root="$1" run_id="$2"
  local status_file type status target reason title body body_esc title_esc
  status_file="$(almanac_loop_run_status_file "$root" "$run_id" 2>/dev/null)" || return 0
  [ -f "$status_file" ] || return 0
  type="$(almanac_loop_status_field "$status_file" type 2>/dev/null || true)"
  status="$(almanac_loop_status_field "$status_file" status 2>/dev/null || true)"
  target="$(almanac_loop_status_field "$status_file" target 2>/dev/null || true)"
  reason="$(almanac_loop_status_field "$status_file" failure_reason 2>/dev/null || true)"
  case "$status" in done|failed|aborted) ;; *) return 0 ;; esac
  title="almanac · ${type:-run} ${status}"
  body="${target}${reason:+ — $reason}"
  if [ -n "${ALMANAC_NOTIFY_TEST_SINK:-}" ]; then
    printf '%s|%s\n' "$title" "$body" >> "$ALMANAC_NOTIFY_TEST_SINK"
    return 0
  fi
  if command -v osascript >/dev/null 2>&1; then
    body_esc="$(printf '%s' "$body" | tr -d '\n' | sed 's/"/\\"/g')"
    title_esc="$(printf '%s' "$title" | tr -d '\n' | sed 's/"/\\"/g')"
    osascript -e "display notification \"$body_esc\" with title \"$title_esc\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$body" >/dev/null 2>&1 || true
  else
    printf '\a' >&2 || true
  fi
}

# Update a live run's progress mid-flight: rewrite its status.tsv with a new
# round (harden round / ralph iteration) and worker/lens summary, preserving the
# lifecycle status, start, and finish fields. This is the "updated as it
# progresses" half of the run-status contract — the loop calls it each round so
# the hub's read view reflects current progress. Touches only the per-run blob,
# not index.tsv (the index stays the lightweight lifecycle pointer). Returns 2
# when the run has no status file.
almanac_loop_update_run_progress() {
  [ "$#" -ge 2 ] || return 2

  local root="$1"
  local run_id="$2"
  local round="${3:-}"
  local summary="${4:-}"
  local status_file

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  # Set only the live-progress fields; record_set preserves the identity and
  # lifecycle (status/start/finish) fields untouched.
  almanac_loop_record_set "$status_file" "round=$round" "summary=$summary"
}

# Detect a stale registry entry: a run whose recorded status is still `running`
# but whose process is gone (crashed/killed without marking itself), so the hub
# can surface or reap it. Returns 0 (stale) only when status is running AND the
# pid is not alive — a numeric pid that `kill -0` cannot signal, or a missing/
# non-numeric pid that cannot be verified. Returns 1 for a live running pid or
# any terminal status; returns 2 when the run is unknown.
almanac_loop_run_is_stale() {
  local root="$1"
  local run_id="$2"
  local status_file status pid

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  status="$(almanac_loop_status_field "$status_file" "status" || true)"
  [ "$status" = "running" ] || return 1

  pid="$(almanac_loop_status_field "$status_file" "pid" || true)"
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac

  if kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  return 0
}

# List every registered run as index.tsv data rows (id/type/target/pid/status-
# file/start/status), header stripped — the API the hub reads to enumerate runs.
# Returns 1 when there is no registry or no run has been registered yet, so a
# caller can branch on "any runs?" without parsing.
almanac_loop_list_runs() {
  local root="$1"
  local index_file rows

  index_file="$(almanac_loop_run_index_file "$root")"
  [ -f "$index_file" ] || return 1

  rows="$(awk 'NR > 1' "$index_file")"
  [ -n "$rows" ] || return 1

  printf '%s\n' "$rows"
}

# Read a single run's full status.tsv blob — the detail view the hub renders for
# one run (identity plus live round/summary and finish state). Returns 1 when the
# run is unknown.
almanac_loop_read_run() {
  local root="$1"
  local run_id="$2"
  local status_file

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 1

  cat "$status_file"
}

almanac_loop_worker_dir() {
  local root="$1"
  local run_id="$2"
  local worker_id="$3"

  printf '%s/%s/workers/%s\n' \
    "$(almanac_loop_registry_dir "$root")" \
    "$run_id" \
    "$(almanac_loop_slug "$worker_id")"
}

almanac_loop_worker_status_file() {
  local root="$1"
  local run_id="$2"
  local worker_id="$3"

  printf '%s/status.tsv\n' "$(almanac_loop_worker_dir "$root" "$run_id" "$worker_id")"
}

almanac_loop_worker_file() {
  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local filename="$4"

  printf '%s/%s\n' "$(almanac_loop_worker_dir "$root" "$run_id" "$worker_id")" "$filename"
}

# --- Worker health detection ---------------------------------------------------
#
# Classify a worker's health from progress signals so the dashboard can surface a
# reviewer that is stalled (log stopped advancing), idle (running but never
# produced an event), or looping (emitting the same event over and over) rather
# than the operator discovering it by hand. The classifier is a PURE predicate
# over already-gathered numbers, so it is table-testable with no files, clock, or
# terminal; the gather wrapper (almanac_loop_worker_health_of) feeds it real run
# state.

# Pure predicate: (status, log-age-secs, event-count, trailing-repeat-count,
# stall-threshold-secs, loop-repeat-threshold) -> one of
# running|stalled|idle|looping|done|failed. A terminal status passes straight
# through. For a live worker: a trailing run of identical events at/over the loop
# threshold is a loop; otherwise zero events past the stall threshold is idle, any
# log silence past the stall threshold is stalled, and anything else is running.
almanac_loop_worker_health() {
  local status="${1:-running}"
  local age="${2:-0}"
  local count="${3:-0}"
  local repeat="${4:-0}"
  local stall="${5:-120}"
  local loop="${6:-5}"

  case "$status" in
    done)   printf '%s\n' "done";   return 0 ;;
    failed) printf '%s\n' "failed"; return 0 ;;
  esac

  if [ "$loop" -gt 0 ] && [ "$repeat" -ge "$loop" ]; then
    printf '%s\n' "looping"; return 0
  fi
  if [ "$count" -eq 0 ] && [ "$age" -ge "$stall" ]; then
    printf '%s\n' "idle"; return 0
  fi
  if [ "$age" -ge "$stall" ]; then
    printf '%s\n' "stalled"; return 0
  fi
  printf '%s\n' "running"
}

# Seconds since a file was last modified (now - mtime). Prints -1 when the file is
# absent. now-epoch is overridable (tests) so age is deterministic. Handles both
# BSD/macOS (stat -f %m) and GNU/Linux (stat -c %Y).
almanac_loop_file_age_secs() {
  local file="$1"
  local now="${2:-}"
  local mtime

  [ -f "$file" ] || { printf '%s\n' "-1"; return 0; }
  [ -n "$now" ] || now="$(date +%s)"
  mtime="$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || printf '%s' "")"
  [ -n "$mtime" ] || { printf '%s\n' "-1"; return 0; }
  printf '%s\n' "$((now - mtime))"
}

# Count lines in a file (0 when absent). awk NR counts a final unterminated line.
almanac_loop_count_lines() {
  [ -f "$1" ] || { printf '%s\n' "0"; return 0; }
  awk 'END { print NR }' "$1"
}

# Count the trailing run of identical lines at the end of a file (0 when absent or
# empty, 1 when the last line is unique). A long run is the loop signal.
almanac_loop_trailing_repeat() {
  [ -f "$1" ] || { printf '%s\n' "0"; return 0; }
  awk '
    NR == 1 { last = $0; c = 1; next }
    $0 == last { c++; next }
    { last = $0; c = 1 }
    END {
      if (NR == 0) { print 0; exit }
      print c
    }
  ' "$1"
}

# Gather one worker's real run state and classify its health. Reads the worker's
# status.tsv (status + events-log path), measures the log's age/size/trailing
# repeat, and returns the pure predicate's verdict. Prints "unknown" when the
# worker has no status file yet. now/stall/loop are overridable.
almanac_loop_worker_health_of() {
  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local now="${4:-}"
  local stall="${5:-120}"
  local loop="${6:-5}"
  local status_file status events_file age count repeat

  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  [ -f "$status_file" ] || { printf '%s\n' "unknown"; return 0; }

  status="$(almanac_loop_status_field "$status_file" "status" || true)"
  events_file="$(almanac_loop_status_field "$status_file" "events_file" || true)"

  [ -n "$now" ] || now="$(date +%s)"
  age="$(almanac_loop_file_age_secs "$events_file" "$now")"
  count="$(almanac_loop_count_lines "$events_file")"
  repeat="$(almanac_loop_trailing_repeat "$events_file")"
  [ "$age" -ge 0 ] 2>/dev/null || age=0

  almanac_loop_worker_health "${status:-running}" "$age" "$count" "$repeat" "$stall" "$loop"
}

# --- Hub overview --------------------------------------------------------------
#
# The interactive hub (`almanac` in a TTY, or `almanac hub`) is the front door to
# every loop. Its read views are PURE registry projections so they are testable
# off a terminal and degrade to plain text without gum; the interactive menus
# (new-run, per-run watch/stop/steer) layer on top of these.

# Project the run registry into one of the hub's two lists as plain printable
# rows (text only — gum frames them later, so this stays unit-testable off a
# TTY). `which` selects the section:
#   running — every run whose lifecycle status is still `running`, carrying its
#             live round/summary from the run-status blob; a running entry whose
#             pid is gone is surfaced as `stale` (almanac_loop_run_is_stale) so a
#             crashed run is visible rather than silently lost.
#   recent  — the finished runs (done/failed/aborted), newest finish first,
#             capped at `limit` (default 10).
# Each row is "<glyph>  <state>  <type>  <target>  <detail>  [<id>]". Returns 1
# (no rows) when the section is empty so the caller can print an empty-state line.
almanac_loop_hub_render() {
  local root="$1"
  local which="$2"
  local limit="${3:-10}"
  local rows id type target pid status_rel started status
  local blob round summary finished detail glyph live count reason_field display queue

  rows="$(almanac_loop_list_runs "$root")" || return 1
  count=0

  if [ "$which" = "recent" ]; then
    local sortable=""
    while IFS=$'\t' read -r id type target pid status_rel started status; do
      [ -n "$id" ] || continue
      case "$status" in
        done|failed|aborted) ;;
        *) continue ;;
      esac
      blob="$(almanac_loop_run_status_file "$root" "$id")"
      finished="$(almanac_loop_status_field "$blob" "finished_at" 2>/dev/null || true)"
      [ -n "$finished" ] || finished="$started"
      reason_field=""
      if [ "$status" = "failed" ]; then
        reason_field="$(almanac_loop_status_field "$blob" "failure_reason" 2>/dev/null || true)"
      fi
      sortable+="$finished"$'\t'"$id"$'\t'"$type"$'\t'"$target"$'\t'"$status"$'\t'"$reason_field"$'\n'
    done <<< "$rows"
    [ -n "$sortable" ] || return 1
    while IFS=$'\t' read -r finished id type target status reason_field; do
      [ -n "$id" ] || continue
      glyph="$(almanac_loop_ui_status_glyph "$status")"
      display="$finished"
      if [ "$status" = "failed" ] && [ -n "$reason_field" ]; then
        display="$finished — $reason_field"
      fi
      printf '%s  %s  %s  %s  %s  [%s]\n' "$glyph" "$status" "$type" "$target" "$display" "$id"
      count=$((count + 1))
      if [ "$count" -ge "$limit" ]; then break; fi
    done < <(printf '%s' "$sortable" | sort -t$'\t' -k1,1r)
    if [ "$count" -gt 0 ]; then return 0; fi
    return 1
  fi

  # which == running (default)
  while IFS=$'\t' read -r id type target pid status_rel started status; do
    [ -n "$id" ] || continue
    [ "$status" = "running" ] || continue
    blob="$(almanac_loop_run_status_file "$root" "$id")"
    round="$(almanac_loop_status_field "$blob" "round" 2>/dev/null || true)"
    summary="$(almanac_loop_status_field "$blob" "summary" 2>/dev/null || true)"
    queue="$(almanac_loop_status_field "$blob" "queue_progress" 2>/dev/null || true)"
    live="running"
    if almanac_loop_run_is_stale "$root" "$id"; then
      live="stale"
    fi
    glyph="$(almanac_loop_ui_status_glyph "$live")"
    detail=""
    if [ -n "$round" ]; then detail="round $round"; fi
    if [ -n "$summary" ]; then detail="${detail:+$detail  }$summary"; fi
    if [ -n "$queue" ]; then detail="${detail:+$detail  }queue $queue"; fi
    if [ -z "$detail" ]; then detail="—"; fi
    printf '%s  %s  %s  %s  %s  [%s]\n' "$glyph" "$live" "$type" "$target" "$detail" "$id"
    count=$((count + 1))
  done <<< "$rows"
  if [ "$count" -gt 0 ]; then return 0; fi
  return 1
}

# Compose the hub's read-only overview screen: a Running section (live loops from
# the registry) and a Recent section (last finished loops), each framed through
# the shared ui renderer so it shows as a gum panel on a TTY and plain text
# without gum. This is the whole hub output off a TTY and the status screen the
# interactive hub draws around its menu. Each section prints an empty-state line
# when there are no matching runs.
almanac_loop_hub_overview() {
  local root="$1"
  local recent_limit="${2:-10}"
  local running recent

  {
    printf '%s\n' "almanac — loop hub"
    printf '\n'
    printf '%s\n' "Running"
    if running="$(almanac_loop_hub_render "$root" running)"; then
      printf '%s\n' "$running"
    else
      printf '%s\n' "  (no running loops)"
    fi
    printf '\n'
    printf '%s\n' "Recent"
    if recent="$(almanac_loop_hub_render "$root" recent "$recent_limit")"; then
      printf '%s\n' "$recent"
    else
      printf '%s\n' "  (no recent loops)"
    fi
  } | almanac_loop_ui_render
}

# Aggregate finished runs (done/failed/aborted) by (type, provider, model) and
# print a small table: runs + success rate. Reads provider/model from each run's
# blob, so older runs (no recorded config) bucket under `?` for the missing
# fields rather than disappearing. Returns 1 (with no output) when the registry
# has no finished runs, so the caller can print an empty-state line.
#
# Pipeline is `read registry rows → emit (type,provider,model,status) lines →
# awk groups + counts → sort by total runs desc → awk reformats with a header`.
# Pure data + awk so the table is identical with or without gum (the caller
# frames it).
almanac_loop_hub_stats() {
  local root="$1"
  local rows lines id type target pid status_rel started status blob provider model
  rows="$(almanac_loop_list_runs "$root" 2>/dev/null)" || return 1
  [ -n "$rows" ] || return 1

  lines=""
  while IFS=$'\t' read -r id type target pid status_rel started status; do
    [ -n "$id" ] || continue
    case "$status" in done|failed|aborted) ;; *) continue ;; esac
    blob="$(almanac_loop_run_status_file "$root" "$id")"
    provider="$(almanac_loop_status_field "$blob" provider 2>/dev/null || true)"
    model="$(almanac_loop_status_field "$blob" model 2>/dev/null || true)"
    lines+="$type"$'\t'"${provider:-?}"$'\t'"${model:-?}"$'\t'"$status"$'\n'
  done <<< "$rows"
  [ -n "$lines" ] || return 1

  printf '%s' "$lines" | awk -F'\t' '
    {
      key = $1 "|" $2 "|" $3
      total[key]++
      if ($4 == "done") done[key]++
    }
    END {
      for (k in total) {
        n = total[k]; d = (k in done) ? done[k] : 0
        rate = (n > 0) ? (d * 100.0 / n) : 0
        split(k, kk, "|")
        printf "%s\t%s\t%s\t%d\t%.0f\n", kk[1], kk[2], kk[3], n, rate
      }
    }
  ' | sort -t$'\t' -k4,4 -n -r | awk -F'\t' '
    BEGIN { printf "%-8s %-8s %-22s %6s %8s\n", "type", "provider", "model", "runs", "success" }
    { printf "%-8s %-8s %-22s %6d %7d%%\n", $1, $2, $3, $4, $5 }
  '
  return 0
}

# --- Hub per-run actions -------------------------------------------------------
#
# The interactive hub lets the operator act on a selected running loop: watch its
# live status, stop it, or queue a steer directive for its next round. These are
# pure-ish file/signal operations (no gum, no menu), so they are unit-testable and
# also drivable non-interactively (`almanac hub --stop|--steer|--watch <id>`); the
# gum selection menu in cmd/hub.sh is a thin TTY layer over them.

# Map a run type + signal kind to the dot-file basename the loop's runner watches
# for between rounds. The mapping is the loop adapter's control contract — each
# loop owns its own signal files (ralph consumes `.ralph-stop`/`.ralph-steer`,
# harden `.harden-stop`/`.harden-steer`) — so this dispatches to the adapter
# rather than branching on type centrally. Prints the basename; returns 1 for an
# unknown type or kind.
almanac_loop_run_signal_file() {
  local type="$1"
  local kind="$2"

  almanac_loop_adapter_known "$type" || return 1
  almanac_loop_adapter_call "$type" signal_file "$kind" || return 1
}

# Stop a registered running run: write the run type's stop file under root (runs
# register with root = their working dir, so the loop sees it at its next
# between-round check). The registry lives in the project and is not trusted for
# host PID signaling, so hub stop never sends TERM from a recorded pid. Returns 2
# when the run is unknown, 3 when its type has no stop convention, and 4 when the
# run is already terminal/non-running.
almanac_loop_run_stop() {
  local root="$1"
  local run_id="$2"
  local status_file type status stop_file

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  type="$(almanac_loop_status_field "$status_file" "type" || true)"
  status="$(almanac_loop_status_field "$status_file" "status" || true)"
  [ "$status" = "running" ] || return 4

  stop_file="$(almanac_loop_run_signal_file "$type" stop)" || return 3
  printf '%s\n' "stop requested via almanac hub: $run_id" > "$root/$stop_file"
  return 0
}

# Queue a steer directive for a running loop: write the directive to the run type's
# steer file under root, which the loop's next round consumes (ralph reads
# `.ralph-steer`). Returns 2 when the run is unknown, 3 when its type has no steer
# convention, and 4 when the directive is blank.
almanac_loop_run_steer() {
  local root="$1"
  local run_id="$2"
  local directive="$3"
  local status_file type steer_file

  if [ -z "${directive//[[:space:]]/}" ]; then
    return 4
  fi

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  type="$(almanac_loop_status_field "$status_file" "type" || true)"
  steer_file="$(almanac_loop_run_signal_file "$type" steer)" || return 3

  printf '%s\n' "$directive" > "$root/$steer_file"
  return 0
}

# Pure detail view of one run for the hub's per-run screen (selection confirmation
# + watch frame): identity, live status (upgraded to `stale` when a running run's
# pid is gone, like the running list), round/summary, and start/finish. Plain text
# only — gum frames it later. Returns 1 when the run is unknown.
almanac_loop_run_detail() {
  local root="$1"
  local run_id="$2"
  local status_file id type target status round summary started finished live glyph failure_reason
  local provider model effort iterations oversee lenses rounds queue_progress

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 1

  id="$(almanac_loop_status_field "$status_file" "id" || true)"
  type="$(almanac_loop_status_field "$status_file" "type" || true)"
  target="$(almanac_loop_status_field "$status_file" "target" || true)"
  status="$(almanac_loop_status_field "$status_file" "status" || true)"
  round="$(almanac_loop_status_field "$status_file" "round" || true)"
  summary="$(almanac_loop_status_field "$status_file" "summary" || true)"
  started="$(almanac_loop_status_field "$status_file" "started_at" || true)"
  finished="$(almanac_loop_status_field "$status_file" "finished_at" || true)"
  failure_reason="$(almanac_loop_status_field "$status_file" "failure_reason" || true)"
  provider="$(almanac_loop_status_field "$status_file" "provider" || true)"
  model="$(almanac_loop_status_field "$status_file" "model" || true)"
  effort="$(almanac_loop_status_field "$status_file" "effort" || true)"
  iterations="$(almanac_loop_status_field "$status_file" "iterations" || true)"
  oversee="$(almanac_loop_status_field "$status_file" "oversee" || true)"
  lenses="$(almanac_loop_status_field "$status_file" "lenses" || true)"
  rounds="$(almanac_loop_status_field "$status_file" "rounds" || true)"
  queue_progress="$(almanac_loop_status_field "$status_file" "queue_progress" || true)"

  live="$status"
  if [ "$status" = "running" ] && almanac_loop_run_is_stale "$root" "$run_id"; then
    live="stale"
  fi
  glyph="$(almanac_loop_ui_status_glyph "$live")"

  printf '%s  %s  %s  %s\n' "$glyph" "$live" "$type" "$target"
  printf 'id: %s\n' "$id"
  if [ -n "$round" ]; then printf 'round: %s\n' "$round"; fi
  if [ -n "$summary" ]; then printf 'summary: %s\n' "$summary"; fi
  if [ -n "$started" ]; then printf 'started: %s\n' "$started"; fi
  if [ -n "$finished" ]; then printf 'finished: %s\n' "$finished"; fi
  if [ -n "$failure_reason" ]; then printf 'failure: %s\n' "$failure_reason"; fi
  # Launch config (recorded at register so hub --resume can rebuild the command).
  # Each line is conditional so a run without a stored value (older runs / fields
  # that don't apply to this loop type) doesn't print empty placeholders.
  [ -n "$provider" ]   && printf 'provider: %s\n' "$provider"
  [ -n "$model" ]      && printf 'model: %s\n' "$model"
  [ -n "$effort" ]     && printf 'effort: %s\n' "$effort"
  [ -n "$iterations" ] && printf 'iterations: %s\n' "$iterations"
  [ -n "$oversee" ]    && printf 'oversee: %s\n' "$oversee"
  [ -n "$lenses" ]     && printf 'lenses: %s\n' "$lenses"
  [ -n "$rounds" ]     && printf 'rounds: %s\n' "$rounds"
  [ -n "$queue_progress" ] && printf 'queue: %s\n' "$queue_progress"
  return 0
}

# Watch a run from the hub. One-shot (default, and whenever stdout is not a TTY):
# render the run's detail once through the shared UI renderer and return — the
# testable, scripts-safe path piped callers get. Follow (`follow` + a TTY): redraw
# the detail every interval until the run reaches a terminal status, so the
# operator can tail a live loop's status from the hub (ALMANAC_HUB_WATCH_INTERVAL
# overrides the cadence). Returns 1 when the run is unknown.
almanac_loop_run_watch() {
  local root="$1"
  local run_id="$2"
  local mode="${3:-}"
  local interval="${ALMANAC_HUB_WATCH_INTERVAL:-2}"
  local status_file status

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 1

  if [ "$mode" != "follow" ] || [ ! -t 1 ]; then
    almanac_loop_run_detail "$root" "$run_id" | almanac_loop_ui_render
    return 0
  fi

  while :; do
    almanac_loop_ui_clear
    almanac_loop_run_detail "$root" "$run_id" | almanac_loop_ui_render
    status="$(almanac_loop_status_field "$status_file" "status" || true)"
    case "$status" in
      done|failed|aborted) break ;;
    esac
    sleep "$interval"
  done
  return 0
}

# --- New-run composition (hub "New run" flow) -------------------------------
#
# The hub's New-run flow picks a loop type (ralph|harden), gathers config, and
# launches it. The argv/env COMPOSITION is pure (no gum, no exec) so it is unit-
# testable off a terminal and doubles as the seam the gum menu and `almanac hub
# --new … [--dry-run]` both drive: menu choices in, launch tokens out.
#
# Config arrives as `key=value` pairs (the keys the gum menu / --new flags
# collect): ralph takes prd, mode, provider, model, effort, iterations, oversee;
# harden takes target, rounds, lenses, provider, model, effort.

# Compose the launcher argv for a new run, one token per line, starting with the
# `almanac` subcommand. ralph config maps to ralph.sh flags; harden launches the
# convergence loop (`harden <target> --loop [--rounds N]`) — its provider/model/
# effort/lenses are environment, emitted by almanac_loop_new_run_env, not argv.
# converge takes goal + exec + rounds + oversee config on argv (the only required
# pieces of state the runner can't infer); role config (provider/model/effort)
# rides on environment, same shape as harden.
# Returns 1 for an unknown type, 2 when a required field is missing (ralph: prd;
# harden: target; converge: goal+exec).
almanac_loop_new_run_argv() {
  local type="$1"; shift
  local prd="" mode="" provider="" model="" effort="" iterations="" oversee="" target="" rounds=""
  local goal="" exec_cmd="" oversee_every="" kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      prd) prd="$val" ;;
      mode) mode="$val" ;;
      provider) provider="$val" ;;
      model) model="$val" ;;
      effort) effort="$val" ;;
      iterations) iterations="$val" ;;
      oversee) oversee="$val" ;;
      target) target="$val" ;;
      rounds) rounds="$val" ;;
      goal) goal="$val" ;;
      exec) exec_cmd="$val" ;;
      oversee_every) oversee_every="$val" ;;
    esac
  done

  case "$type" in
    ralph)
      [ -n "$prd" ] || return 2
      printf '%s\n' ralph
      printf '%s\n%s\n' --prd "$prd"
      if [ -n "$mode" ]; then printf '%s\n%s\n' --mode "$mode"; fi
      if [ -n "$provider" ]; then printf '%s\n%s\n' --provider "$provider"; fi
      if [ -n "$model" ]; then printf '%s\n%s\n' --model "$model"; fi
      if [ -n "$effort" ]; then printf '%s\n%s\n' --effort "$effort"; fi
      if [ -n "$iterations" ]; then printf '%s\n%s\n' --iterations "$iterations"; fi
      if [ "$oversee" = "off" ]; then printf '%s\n' --no-oversee; fi
      ;;
    harden)
      [ -n "$target" ] || return 2
      printf '%s\n%s\n%s\n' harden "$target" --loop
      if [ -n "$rounds" ]; then printf '%s\n%s\n' --rounds "$rounds"; fi
      ;;
    converge)
      [ -n "$goal" ] || return 2
      [ -n "$exec_cmd" ] || return 2
      # Same split as harden: state the runner needs goes on argv (goal, exec,
      # rounds, oversee flags), role config (provider/model/effort) rides on
      # environment via almanac_loop_new_run_env. The runner is `almanac converge`
      # — cmd/converge.sh; no launcher hop in this code path. The interactive
      # menu uses almanac_loop_launch converge (the launcher) instead.
      printf '%s\n' converge
      printf '%s\n%s\n' --goal "$goal"
      printf '%s\n%s\n' --exec "$exec_cmd"
      if [ -n "$rounds" ]; then printf '%s\n%s\n' --rounds "$rounds"; fi
      if [ "$oversee" = "off" ]; then printf '%s\n' --no-oversee; fi
      if [ -n "$oversee_every" ]; then printf '%s\n%s\n' --oversee-every "$oversee_every"; fi
      ;;
    *) return 1 ;;
  esac
  return 0
}

# Compose the environment assignments (KEY=VALUE, one per line) a new run needs
# beyond its argv. ralph takes all config as flags, so it emits nothing; harden's
# reviewer/role config rides on environment (HARDEN_LENSES / HARDEN_PROVIDER /
# HARDEN_MODEL / HARDEN_EFFORT). Returns 1 for an unknown type.
almanac_loop_new_run_env() {
  local type="$1"; shift
  local provider="" model="" effort="" lenses="" kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      provider) provider="$val" ;;
      model) model="$val" ;;
      effort) effort="$val" ;;
      lenses) lenses="$val" ;;
    esac
  done

  case "$type" in
    ralph) : ;;
    harden)
      if [ -n "$lenses" ]; then printf 'HARDEN_LENSES=%s\n' "$lenses"; fi
      if [ -n "$provider" ]; then printf 'HARDEN_PROVIDER=%s\n' "$provider"; fi
      if [ -n "$model" ]; then printf 'HARDEN_MODEL=%s\n' "$model"; fi
      if [ -n "$effort" ]; then printf 'HARDEN_EFFORT=%s\n' "$effort"; fi
      ;;
    converge)
      if [ -n "$provider" ]; then printf 'CONVERGE_PROVIDER=%s\n' "$provider"; fi
      if [ -n "$model" ]; then printf 'CONVERGE_MODEL=%s\n' "$model"; fi
      if [ -n "$effort" ]; then printf 'CONVERGE_EFFORT=%s\n' "$effort"; fi
      ;;
    *) return 1 ;;
  esac
  return 0
}
