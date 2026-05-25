#!/usr/bin/env bash
# loop-core.sh - Shared loop orchestration helpers

# Output helpers (_die/_info/_error/...) live in lib/core.sh. Source it
# idempotently so loop-core's direct consumers — Ralph scripts and tests that
# source this file without going through bin/almanac — still get them. pwd -P
# resolves the install symlink so the sibling core.sh is found from either path.
if ! declare -F _error >/dev/null 2>&1; then
  __loop_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__loop_core_dir/core.sh"
  unset __loop_core_dir
fi

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

# Write a run's status.tsv blob — the per-run detail view the hub reads. The
# index.tsv is the lightweight list pointer (id/type/target/pid/status-file/
# start/status); this blob carries the same identity PLUS the live progress the
# index does not: `round` (harden round / ralph iteration) and `summary` (a
# worker/lens summary line). round/summary are optional trailing args (default
# empty) so existing 9-arg callers stay correct and every blob still carries the
# keys, blank until a progress update fills them. The contract is identical for
# harden and ralph — both write this same shape.
almanac_loop_write_run_status() {
  local status_file="$1"
  local run_id="$2"
  local type="$3"
  local target="$4"
  local pid="$5"
  local status_rel="$6"
  local started_at="$7"
  local status="$8"
  local finished_at="$9"
  local round="${10:-}"
  local summary="${11:-}"

  {
    printf 'id\t%s\n' "$run_id"
    printf 'type\t%s\n' "$type"
    printf 'target\t%s\n' "$target"
    printf 'pid\t%s\n' "$pid"
    printf 'status_file\t%s\n' "$status_rel"
    printf 'started_at\t%s\n' "$started_at"
    printf 'status\t%s\n' "$status"
    printf 'finished_at\t%s\n' "$finished_at"
    printf 'round\t%s\n' "$round"
    printf 'summary\t%s\n' "$summary"
  } > "$status_file"
}

almanac_loop_status_field() {
  local status_file="$1"
  local wanted="$2"
  local key value rest

  while IFS=$'\t' read -r key value rest; do
    if [ "$key" = "$wanted" ]; then
      if [ -n "${rest:-}" ]; then
        value="${value}"$'\t'"${rest}"
      fi
      printf '%s\n' "$value"
      return 0
    fi
  done < "$status_file"

  return 1
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

  almanac_loop_write_run_status "$status_file" "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "running" ""
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "running" >> "$index_file"
  printf '%s\n' "$run_id"
}

almanac_loop_mark_run_status() {
  [ "$#" -ge 3 ] || return 2

  local root="$1"
  local run_id="$2"
  local status="$3"
  local finished_at="${4:-}"
  local status_file index_file tmp type target pid status_rel started_at round summary

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

  type="$(almanac_loop_status_field "$status_file" "type")"
  target="$(almanac_loop_status_field "$status_file" "target")"
  pid="$(almanac_loop_status_field "$status_file" "pid")"
  status_rel="$(almanac_loop_status_field "$status_file" "status_file")"
  started_at="$(almanac_loop_status_field "$status_file" "started_at")"
  round="$(almanac_loop_status_field "$status_file" "round" || true)"
  summary="$(almanac_loop_status_field "$status_file" "summary" || true)"

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

  almanac_loop_write_run_status "$status_file" "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "$status" "$finished_at" "$round" "$summary"
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
  local status_file type target pid status_rel started_at status finished_at

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  type="$(almanac_loop_status_field "$status_file" "type")"
  target="$(almanac_loop_status_field "$status_file" "target")"
  pid="$(almanac_loop_status_field "$status_file" "pid")"
  status_rel="$(almanac_loop_status_field "$status_file" "status_file")"
  started_at="$(almanac_loop_status_field "$status_file" "started_at")"
  status="$(almanac_loop_status_field "$status_file" "status")"
  finished_at="$(almanac_loop_status_field "$status_file" "finished_at" || true)"

  almanac_loop_write_run_status "$status_file" "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "$status" "$finished_at" "$round" "$summary"
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

almanac_loop_env_key_part() {
  printf '%s' "$1" \
    | tr '[:lower:]' '[:upper:]' \
    | sed 's/[^A-Z0-9][^A-Z0-9]*/_/g; s/^_//; s/_$//'
}

almanac_loop_env_value() {
  local name="$1"

  if [ "${!name+x}" ]; then
    printf '%s\n' "${!name}"
    return 0
  fi

  return 1
}

almanac_loop_role_field() {
  [ "$#" -ge 5 ] || return 2

  local prefix="$1"
  local role="$2"
  local lens="$3"
  local field="$4"
  local default_value="$5"
  local prefix_key role_key lens_key field_key candidate value

  prefix_key="$(almanac_loop_env_key_part "$prefix")"
  role_key="$(almanac_loop_env_key_part "$role")"
  lens_key="$(almanac_loop_env_key_part "$lens")"
  field_key="$(almanac_loop_env_key_part "$field")"

  if [ -n "$lens_key" ]; then
    candidate="${prefix_key}_${role_key}_${lens_key}_${field_key}"
    if value="$(almanac_loop_env_value "$candidate")"; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  candidate="${prefix_key}_${role_key}_${field_key}"
  if value="$(almanac_loop_env_value "$candidate")"; then
    printf '%s\n' "$value"
    return 0
  fi

  candidate="${prefix_key}_${field_key}"
  if value="$(almanac_loop_env_value "$candidate")"; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '%s\n' "$default_value"
}

almanac_loop_role_config() {
  [ "$#" -ge 2 ] || return 2

  local prefix="$1"
  local role="$2"
  local lens="${3:-}"
  local default_provider="${4:-}"
  local default_model="${5:-}"
  local default_effort="${6:-}"

  printf 'provider\t%s\n' "$(almanac_loop_role_field "$prefix" "$role" "$lens" "provider" "$default_provider")"
  printf 'model\t%s\n' "$(almanac_loop_role_field "$prefix" "$role" "$lens" "model" "$default_model")"
  printf 'effort\t%s\n' "$(almanac_loop_role_field "$prefix" "$role" "$lens" "effort" "$default_effort")"
}

almanac_loop_agent_provider_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Map a sandbox value to claude's --permission-mode. read-only review runs in
# `plan` (no writes); the `default` sentinel returns an empty mode so the seam
# OMITS --permission-mode entirely, letting claude fall back to its own default
# mode — ralph afk.sh's iteration agent has never set a permission mode, so
# routing it through the seam must preserve that; everything else
# (workspace-write, danger-full-access) maps to `acceptEdits`. The `default`
# sentinel only governs claude's permission flag; codex callers do not use it.
almanac_loop_agent_claude_permission() {
  case "$1" in
    read-only) printf '%s\n' "plan" ;;
    default)   printf '%s\n' "" ;;
    *)         printf '%s\n' "acceptEdits" ;;
  esac
}

almanac_loop_agent_extract_claude_result() {
  local stream_file="$1"
  local result_file="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.type == "result").result // empty' "$stream_file" | tail -n 1 > "$result_file"
    return 0
  fi

  awk '
    /"type"[[:space:]]*:[[:space:]]*"result"/ && /"result"[[:space:]]*:/ {
      line = $0
      sub(/^.*"result"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      result = line
    }
    END {
      if (result != "") print result
    }
  ' "$stream_file" > "$result_file"
}

# jq filter turning claude --output-format stream-json events into the live
# assistant text the console shows: the init model line, then each assistant
# text block, CRLF-normalised so it renders cleanly in a terminal. Identical to
# ralph once.sh/afk.sh's stream_text so routing ralph through this seam keeps
# its console output byte-for-byte.
almanac_loop_agent_claude_stream_filter() {
  cat <<'JQ'
  if .type == "system" and .subtype == "init" and (.model // "") != "" then
    "Claude model: \(.model)\r\n\n"
  elif .type == "assistant" then
    .message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"
  else
    empty
  end
JQ
}

# jq filter turning codex --json events into the live agent-message text the
# console shows. Identical to ralph's codex_stream_text.
almanac_loop_agent_codex_stream_filter() {
  cat <<'JQ'
  if .type == "item.completed" and .item.type == "agent_message" then
    .item.text | . + "\n\n"
  else
    empty
  end
JQ
}

# Run a provider command, optionally merging its stderr into stdout (2>&1) when
# $1 is "1". Used as the producer at the head of the stream pipeline below so the
# merge can be toggled without duplicating the whole pipeline. The function's
# exit code is the provider's, so PIPESTATUS[0] in the calling pipeline still
# reflects the producer rather than this wrapper.
almanac_loop_agent_producer() {
  local merge="$1"; shift
  if [ "$merge" = "1" ]; then
    "$@" 2>&1
  else
    "$@"
  fi
}

# Run a provider command live: tee its raw event stream to $events_file AND pipe
# it through the provider's jq filter to stdout, so the caller sees progress as
# it happens. Crucially, the PRODUCER's exit code wins (via PIPESTATUS), not the
# jq filter's — a provider failure must propagate even though it is piped. errexit
# is suspended around the pipeline (a no-match grep / empty filter must not abort
# a set -e caller) and restored afterwards. Degrades to a raw tee when jq is
# absent so output is never silently dropped. When $merge_stderr requests it, the
# provider's stderr is folded into the captured/streamed output (2>&1) —
# preserving ralph once.sh's `codex ... 2>&1 | tee` log capture; default leaves
# stderr on the terminal.
# Usage: almanac_loop_agent_stream <provider> <events_file> <merge_stderr> <cmd> [args...]
almanac_loop_agent_stream() {
  local provider="$1"; shift
  local events_file="$1"; shift
  local merge_stderr="$1"; shift

  local filter prefilter=0 rc had_e=0 merge=0
  case "$merge_stderr" in
    merge-stderr|stderr|on|1) merge=1 ;;
  esac

  case "$(almanac_loop_agent_provider_key "$provider")" in
    claude|claude-code) filter="$(almanac_loop_agent_claude_stream_filter)"; prefilter=1 ;;
    codex)              filter="$(almanac_loop_agent_codex_stream_filter)" ;;
    *)                  filter="" ;;
  esac

  case $- in *e*) had_e=1 ;; esac
  set +e
  if command -v jq >/dev/null 2>&1 && [ -n "$filter" ]; then
    if [ "$prefilter" -eq 1 ]; then
      almanac_loop_agent_producer "$merge" "$@" | tee "$events_file" | grep --line-buffered '^{' \
        | jq -Rj --unbuffered "fromjson? // empty | objects | ( $filter )"
    else
      almanac_loop_agent_producer "$merge" "$@" | tee "$events_file" \
        | jq -Rj --unbuffered "fromjson? // empty | objects | ( $filter )"
    fi
  else
    almanac_loop_agent_producer "$merge" "$@" | tee "$events_file"
  fi
  rc=${PIPESTATUS[0]}
  [ "$had_e" -eq 1 ] && set -e
  return "$rc"
}

almanac_loop_agent_run() {
  [ "$#" -ge 6 ] || return 2

  local provider="$1"
  local model="$2"
  local effort="$3"
  local sandbox="$4"
  local prompt_file="$5"
  local result_file="$6"
  local events_file="${7:-}"
  local stream_mode="${8:-}"
  local merge_stderr="${9:-}"
  local provider_key prompt stream=0 raw=0 rc

  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2

  # stream tees live assistant text to stdout (jq-filtered); raw is codex's native
  # passthrough (no --json, no filter, no events capture) — ralph's
  # RALPH_CODEX_VERBOSE path; default captures the raw event stream to the log.
  case "$stream_mode" in
    stream|live|on|1) stream=1 ;;
    raw|passthrough)  raw=1 ;;
  esac

  provider_key="$(almanac_loop_agent_provider_key "$provider")"
  prompt="$(cat "$prompt_file")"
  sandbox="${sandbox:-danger-full-access}"

  # Raw mode is codex-specific (it omits --json); any other provider falls back to
  # its normal non-stream path so events capture still works.
  [ "$provider_key" = "codex" ] || raw=0

  # Raw provider events stream to a JSONL log. The caller may pass its own path
  # (per-run events.jsonl); otherwise we allocate one. Either way the path is
  # echoed back at the end so the caller can locate the stream. Raw mode captures
  # no events log (codex's native output goes straight to the terminal), so it
  # never allocates one.
  if [ "$raw" -ne 1 ] && [ -z "$events_file" ]; then
    events_file="$(mktemp "${TMPDIR:-/tmp}/almanac-loop-events.XXXXXX")"
  fi

  case "$provider_key" in
    codex)
      if ! command -v codex >/dev/null 2>&1; then
        _error "provider 'codex' is not on PATH."
        return 4
      fi

      local codex_args=(
        --ask-for-approval never
        exec
        --cd "$PWD"
        --sandbox "$sandbox"
        --color never
      )

      # Raw mode wants codex's NATIVE output (ralph's RALPH_CODEX_VERBOSE); every
      # other mode parses the structured --json event stream.
      if [ "$raw" -ne 1 ]; then
        codex_args+=(--json)
      fi
      codex_args+=(--output-last-message "$result_file")

      if [ -n "$model" ]; then
        codex_args+=(--model "$model")
      fi

      if [ -n "$effort" ]; then
        codex_args+=(-c "model_reasoning_effort=\"$effort\"")
      fi

      if [ "$raw" -eq 1 ]; then
        # No --json, no filter, no events capture: codex's native output streams
        # straight to the terminal; --output-last-message still writes the result.
        # The direct exec keeps $? as codex's exit so a failure propagates.
        codex "${codex_args[@]}" "$prompt" || return "$?"
        return 0
      elif [ "$stream" -eq 1 ]; then
        rc=0
        almanac_loop_agent_stream "codex" "$events_file" "$merge_stderr" \
          codex "${codex_args[@]}" "$prompt" || rc=$?
        [ "$rc" -eq 0 ] || return "$rc"
      else
        codex "${codex_args[@]}" "$prompt" > "$events_file" || return "$?"
      fi
      ;;
    claude|claude-code)
      if ! command -v claude >/dev/null 2>&1; then
        _error "provider 'claude' is not on PATH."
        return 4
      fi

      local claude_args=(
        --print
        --output-format stream-json
        --verbose
      )

      # Permission mode is derived from the sandbox; the `default` sentinel maps
      # to an empty mode so the flag is omitted (claude's own default) —
      # preserving afk.sh's iteration agent, which has never set --permission-mode.
      local claude_perm
      claude_perm="$(almanac_loop_agent_claude_permission "$sandbox")"
      if [ -n "$claude_perm" ]; then
        claude_args+=(--permission-mode "$claude_perm")
      fi

      if [ -n "$model" ]; then
        claude_args+=(--model "$model")
      fi

      if [ -n "$effort" ]; then
        claude_args+=(--effort "$effort")
      fi

      if [ "$stream" -eq 1 ]; then
        # Stream mode tees live assistant text to stdout; the helper preserves
        # claude's exit via PIPESTATUS so a failure still propagates past the pipe.
        rc=0
        almanac_loop_agent_stream "claude" "$events_file" "$merge_stderr" \
          claude "${claude_args[@]}" "$prompt" || rc=$?
        [ "$rc" -eq 0 ] || return "$rc"
      else
        # No pipe: a direct redirect keeps $? as claude's exit so a provider
        # failure propagates instead of being masked by a downstream tee.
        claude "${claude_args[@]}" "$prompt" > "$events_file" || return "$?"
      fi
      almanac_loop_agent_extract_claude_result "$events_file" "$result_file"
      ;;
    *)
      _error "unsupported provider: $provider"
      return 3
      ;;
  esac

  # In stream mode stdout already carries the live assistant text, so do not
  # append the events-file path (it would corrupt the stream). The caller passes
  # its own events_file in stream mode and already knows the path.
  [ "$stream" -eq 1 ] && return 0

  printf '%s\n' "$events_file"
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

almanac_loop_write_worker_status() {
  local status_file="$1"
  local worker_id="$2"
  local run_id="$3"
  local pid="$4"
  local provider="$5"
  local model="$6"
  local effort="$7"
  local sandbox="$8"
  local prompt_file="$9"
  local events_file="${10}"
  local result_file="${11}"
  local stderr_file="${12}"
  local started_at="${13}"
  local status="${14}"
  local finished_at="${15}"
  local exit_code="${16}"

  {
    printf 'id\t%s\n' "$worker_id"
    printf 'run_id\t%s\n' "$run_id"
    printf 'pid\t%s\n' "$pid"
    printf 'provider\t%s\n' "$provider"
    printf 'model\t%s\n' "$model"
    printf 'effort\t%s\n' "$effort"
    printf 'sandbox\t%s\n' "$sandbox"
    printf 'prompt_file\t%s\n' "$prompt_file"
    printf 'events_file\t%s\n' "$events_file"
    printf 'result_file\t%s\n' "$result_file"
    printf 'stderr_file\t%s\n' "$stderr_file"
    printf 'started_at\t%s\n' "$started_at"
    printf 'status\t%s\n' "$status"
    printf 'finished_at\t%s\n' "$finished_at"
    printf 'exit_code\t%s\n' "$exit_code"
  } > "$status_file"
}

almanac_loop_mark_worker_status() {
  [ "$#" -ge 5 ] || return 2

  local root="$1"
  local run_id="$2"
  local worker_id="$3"
  local status="$4"
  local exit_code="$5"
  local finished_at="${6:-}"
  local status_file pid provider model effort sandbox prompt_file events_file result_file stderr_file started_at

  case "$status" in
    done|failed) ;;
    *) return 3 ;;
  esac

  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  [ -f "$status_file" ] || return 2

  if [ -z "$finished_at" ]; then
    finished_at="$(almanac_loop_now_utc)"
  fi

  pid="$(almanac_loop_status_field "$status_file" "pid")"
  provider="$(almanac_loop_status_field "$status_file" "provider")"
  model="$(almanac_loop_status_field "$status_file" "model")"
  effort="$(almanac_loop_status_field "$status_file" "effort")"
  sandbox="$(almanac_loop_status_field "$status_file" "sandbox")"
  prompt_file="$(almanac_loop_status_field "$status_file" "prompt_file")"
  events_file="$(almanac_loop_status_field "$status_file" "events_file")"
  result_file="$(almanac_loop_status_field "$status_file" "result_file")"
  stderr_file="$(almanac_loop_status_field "$status_file" "stderr_file")"
  started_at="$(almanac_loop_status_field "$status_file" "started_at")"

  almanac_loop_write_worker_status \
    "$status_file" \
    "$worker_id" \
    "$run_id" \
    "$pid" \
    "$provider" \
    "$model" \
    "$effort" \
    "$sandbox" \
    "$prompt_file" \
    "$events_file" \
    "$result_file" \
    "$stderr_file" \
    "$started_at" \
    "$status" \
    "$finished_at" \
    "$exit_code"
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

    if almanac_loop_agent_run "$provider" "$model" "$effort" "$sandbox" "$prompt_file" "$result_file" "$events_file" >/dev/null 2> "$stderr_file"; then
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

  almanac_loop_write_worker_status \
    "$status_file" \
    "$worker_id" \
    "$run_id" \
    "$worker_pid" \
    "$provider" \
    "$model" \
    "$effort" \
    "${sandbox:-danger-full-access}" \
    "$prompt_file" \
    "$events_file" \
    "$result_file" \
    "$stderr_file" \
    "$started_at" \
    "running" \
    "" \
    ""

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

almanac_loop_feedback_commands() {
  local root="${1:-.}"

  if [ -f "$root/package.json" ]; then
    printf '%s\n' "npm run test"
    printf '%s\n' "npm run typecheck"
    printf '%s\n' "npm run lint"
  fi

  if [ -f "$root/Makefile" ]; then
    printf '%s\n' "make test"
    printf '%s\n' "make check"
  fi

  if [ -f "$root/Cargo.toml" ]; then
    printf '%s\n' "cargo test"
    printf '%s\n' "cargo check"
  fi

  if [ -f "$root/go.mod" ]; then
    printf '%s\n' "go test ./..."
    printf '%s\n' "go vet ./..."
  fi

  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ]; then
    printf '%s\n' "pytest"
    printf '%s\n' "mypy"
  fi

  if [ -f "$root/tests/test-skills.sh" ]; then
    printf '%s\n' "bash tests/test-skills.sh"
  fi

  if [ -f "$root/tests/test-structure.sh" ]; then
    printf '%s\n' "bash tests/test-structure.sh"
  fi
}

almanac_loop_feedback_command_description() {
  case "$1" in
    "npm run test") printf '%s\n' "run npm tests" ;;
    "npm run typecheck") printf '%s\n' "run TypeScript type checks" ;;
    "npm run lint") printf '%s\n' "run lint checks" ;;
    "make test") printf '%s\n' "run Makefile test target" ;;
    "make check") printf '%s\n' "run Makefile check target" ;;
    "cargo test") printf '%s\n' "run Rust tests" ;;
    "cargo check") printf '%s\n' "run Rust compiler checks" ;;
    "go test ./...") printf '%s\n' "run Go tests" ;;
    "go vet ./...") printf '%s\n' "run Go vet checks" ;;
    "pytest") printf '%s\n' "run Python tests" ;;
    "mypy") printf '%s\n' "run Python type checks" ;;
    "bash tests/test-skills.sh") printf '%s\n' "validate skill format/content" ;;
    "bash tests/test-structure.sh") printf '%s\n' "validate repo layout" ;;
    *) printf '%s\n' "run feedback loop" ;;
  esac
}

almanac_loop_feedback_markdown() {
  local root="${1:-.}"
  local command description found
  found=0

  while IFS= read -r command; do
    [ -n "$command" ] || continue
    description="$(almanac_loop_feedback_command_description "$command")"
    printf -- '- `%s` to %s\n' "$command" "$description"
    found=1
  done < <(almanac_loop_feedback_commands "$root")

  if [ "$found" -eq 0 ]; then
    printf '%s\n' "- (none detected)"
  fi
}

# Run every detected feedback loop for the project at $root and emit one TSV
# verdict row per loop: <command>\t<pass|fail>. Each command runs from $root
# (combined output captured to $log_dir/<slug>.log when a log dir is given,
# else discarded). Returns 0 only when every loop passed and non-zero when any
# failed, so a caller can gate on the aggregate while still reading the per-loop
# verdicts. This is the runner half of the shared feedback engine; detection is
# almanac_loop_feedback_commands, shared with Ralph, so both consumers run the
# same objective gate without per-project config.
almanac_loop_feedback_run() {
  local root="${1:-.}"
  local log_dir="${2:-}"
  local command verdict log_file slug
  local any_fail=0

  if [ -n "$log_dir" ]; then
    mkdir -p "$log_dir"
  fi

  while IFS= read -r command; do
    [ -n "$command" ] || continue

    if [ -n "$log_dir" ]; then
      slug="$(printf '%s' "$command" | tr -cs 'A-Za-z0-9' '-')"
      log_file="$log_dir/${slug}.log"
    else
      log_file="/dev/null"
    fi

    if ( cd "$root" && eval "$command" ) > "$log_file" 2>&1; then
      verdict="pass"
    else
      verdict="fail"
      any_fail=1
    fi

    printf '%s\t%s\n' "$command" "$verdict"
  done < <(almanac_loop_feedback_commands "$root")

  return "$any_fail"
}

# --- UI primitives (shared) ----------------------------------------------------
#
# The supervision dashboard is a gum-styled redraw loop (PRD: bash + gum, no true
# TUI). Render LOGIC is kept pure (state -> printable rows) so it is unit-testable
# without a terminal; gum is only a styling layer wrapped around that text, and the
# CLI degrades to plain output when gum is absent — keeping almanac's near-zero-dep
# promise. Set ALMANAC_NO_GUM=1 to force plain output (tests, CI, scripts).

# True (0) only when gum styling should be used: gum is installed, stdout is a
# terminal, and the operator has not opted out via ALMANAC_NO_GUM. Piped/captured
# output is never styled, so callers and tests can assert on plain content.
almanac_loop_ui_has_gum() {
  [ -z "${ALMANAC_NO_GUM:-}" ] || return 1
  command -v gum >/dev/null 2>&1 || return 1
  [ -t 1 ] || return 1
  return 0
}

# Style a block of text read from stdin: a rounded gum panel when gum styling is
# available, otherwise the text passed straight through. Presentation only; the
# content is identical either way, so the dashboard degrades gracefully and stays
# assertable.
almanac_loop_ui_render() {
  if almanac_loop_ui_has_gum; then
    gum style --border rounded --padding "0 1" "$(cat)"
  else
    cat
  fi
}

# Clear the terminal between redraw-loop frames — but ONLY when stdout is a TTY,
# so piped/captured output (tests, scripts, the hub reading a tail) is never
# polluted with clear escape sequences. A no-op off a terminal. Uses clear(1)
# when present, else the ANSI clear+home sequence.
almanac_loop_ui_clear() {
  [ -t 1 ] || return 0
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
  fi
}

# Pure state -> glyph mapping for a worker-health OR run-lifecycle state. Plain
# unicode, no color, no gum, so the dashboard/hub composer that calls it stays
# deterministic. Worker health: running/stalled/idle/looping/done/failed. Run
# lifecycle adds `stale` (a running entry whose pid is gone) and `aborted`.
almanac_loop_ui_status_glyph() {
  case "$1" in
    running) printf '%s\n' "●" ;;
    stalled) printf '%s\n' "◐" ;;
    stale)   printf '%s\n' "◌" ;;
    idle)    printf '%s\n' "○" ;;
    looping) printf '%s\n' "↻" ;;
    done)    printf '%s\n' "✔" ;;
    failed)  printf '%s\n' "✘" ;;
    aborted) printf '%s\n' "■" ;;
    *)       printf '%s\n' "•" ;;
  esac
}

# --- Interactive selection primitives (gum-or-plain) ---------------------------
#
# The interactive hub (and any other menu-driven flow) picks from a list, reads a
# free-text value, and asks yes/no. With gum those are gum choose/input/confirm;
# without gum they degrade to a plain numbered menu + `read`, so the menus work on
# any TTY — keeping almanac's near-zero-dep promise (PRD: "degrade gracefully when
# gum is absent"). The selection LOGIC is split into pure functions (menu_render,
# menu_pick) that are unit-testable off a terminal; the choose/input/confirm
# wrappers add only the gum-or-`read` I/O around them. Set ALMANAC_NO_GUM=1 to
# force the plain path (tests, CI, scripts).

# Pure: render OPTIONS as a 1-based numbered menu, one per line, to stdout. The
# plain-mode selector prints this; tests assert on it directly. No gum, no read.
almanac_loop_ui_menu_render() {
  local i=1 opt
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt"
    i=$((i + 1))
  done
}

# Pure: map a 1-based selection number to the chosen OPTION, echoed on stdout.
# Returns 1 for a blank, non-numeric, or out-of-range selection so the caller can
# treat it like a cancel. No gum, no read — the testable core of the plain chooser.
almanac_loop_ui_menu_pick() {
  local sel="$1"
  shift
  case "$sel" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$sel" -ge 1 ] && [ "$sel" -le "$#" ] || return 1
  shift "$((sel - 1))"
  printf '%s\n' "$1"
}

# Choose one of OPTIONS under HEADER. With gum styling available: `gum choose`.
# Without it: print the header + numbered menu to stderr, read a number from
# stdin, and map it to the option via the pure pick. Either way the chosen option
# is the ONLY thing on stdout (the prompt goes to stderr), so callers capture just
# the choice. Returns nonzero on cancel / EOF / bad input, mirroring gum choose's
# cancel exit so callers can `|| return` to go back.
almanac_loop_ui_choose() {
  local header="$1"
  shift
  local reply
  if almanac_loop_ui_has_gum; then
    printf '%s\n' "$@" | gum choose --header "$header"
    return
  fi
  printf '%s\n' "$header" >&2
  almanac_loop_ui_menu_render "$@" >&2
  printf 'Select [1-%d]: ' "$#" >&2
  read -r reply || return 1
  almanac_loop_ui_menu_pick "$reply" "$@"
}

# Prompt for a free-text value under HEADER, with an optional DEFAULT ($2). With
# gum: `gum input`. Without it: a plain `read` (empty input falls back to the
# default). The value is echoed on stdout; the prompt goes to stderr.
almanac_loop_ui_input() {
  local header="$1"
  local default="${2:-}"
  local reply
  if almanac_loop_ui_has_gum; then
    if [ -n "$default" ]; then
      gum input --header "$header" --value "$default"
    else
      gum input --header "$header"
    fi
    return
  fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$header" "$default" >&2
  else
    printf '%s: ' "$header" >&2
  fi
  read -r reply || reply=""
  [ -n "$reply" ] || reply="$default"
  printf '%s\n' "$reply"
}

# Yes/no confirm of PROMPT. With gum: `gum confirm`. Without it: a plain `read`,
# defaulting to yes on empty input to match gum confirm's affirmative-default
# button. Returns 0 for yes, 1 for no (gum confirm's exit semantics), so callers
# keep `gum confirm … || fallback` shape unchanged. Prompt goes to stderr.
almanac_loop_ui_confirm() {
  local prompt="$1"
  local reply
  if almanac_loop_ui_has_gum; then
    gum confirm "$prompt"
    return
  fi
  printf '%s [Y/n]: ' "$prompt" >&2
  read -r reply || reply=""
  case "$reply" in
    n|N|no|NO|No) return 1 ;;
    *) return 0 ;;
  esac
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
    { lines[NR] = $0 }
    END {
      if (NR == 0) { print 0; exit }
      last = lines[NR]; c = 1
      for (i = NR - 1; i >= 1; i--) {
        if (lines[i] == last) c++; else break
      }
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
  local blob round summary finished detail glyph live count

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
      sortable+="$finished"$'\t'"$id"$'\t'"$type"$'\t'"$target"$'\t'"$status"$'\n'
    done <<< "$rows"
    [ -n "$sortable" ] || return 1
    while IFS=$'\t' read -r finished id type target status; do
      [ -n "$id" ] || continue
      glyph="$(almanac_loop_ui_status_glyph "$status")"
      printf '%s  %s  %s  %s  %s  [%s]\n' "$glyph" "$status" "$type" "$target" "$finished" "$id"
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
    live="running"
    if almanac_loop_run_is_stale "$root" "$id"; then
      live="stale"
    fi
    glyph="$(almanac_loop_ui_status_glyph "$live")"
    detail=""
    if [ -n "$round" ]; then detail="round $round"; fi
    if [ -n "$summary" ]; then detail="${detail:+$detail  }$summary"; fi
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

# --- Hub per-run actions -------------------------------------------------------
#
# The interactive hub lets the operator act on a selected running loop: watch its
# live status, stop it, or queue a steer directive for its next round. These are
# pure-ish file/signal operations (no gum, no menu), so they are unit-testable and
# also drivable non-interactively (`almanac hub --stop|--steer|--watch <id>`); the
# gum selection menu in cmd/hub.sh is a thin TTY layer over them.

# Map a run type + signal kind to the dot-file basename the loop's runner watches
# for between rounds. ralph already consumes `.ralph-stop` (afk stop signal) and
# `.ralph-steer` (one-shot operator/overseer directive the next iteration reads);
# harden's files follow its prefix. Prints the basename; returns 1 for an unknown
# type or kind.
almanac_loop_run_signal_file() {
  local type="$1"
  local kind="$2"
  local base

  case "$type" in
    ralph)  base=".ralph" ;;
    harden) base=".harden" ;;
    *) return 1 ;;
  esac
  case "$kind" in
    stop)  printf '%s\n' "${base}-stop" ;;
    steer) printf '%s\n' "${base}-steer" ;;
    *) return 1 ;;
  esac
}

# Stop a registered run: write the run type's stop file under root (runs register
# with root = their working dir, so the loop sees it at its next between-round
# check) AND best-effort signal the live pid with TERM so a run blocked mid-round
# also tears down. The pid is only signalled when it is numeric and currently
# alive, so a dead/finished run is never killed. Returns 2 when the run is unknown
# and 3 when its type has no stop convention.
almanac_loop_run_stop() {
  local root="$1"
  local run_id="$2"
  local status_file type pid stop_file

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || return 2

  type="$(almanac_loop_status_field "$status_file" "type" || true)"
  pid="$(almanac_loop_status_field "$status_file" "pid" || true)"

  stop_file="$(almanac_loop_run_signal_file "$type" stop)" || return 3
  printf '%s\n' "stop requested via almanac hub: $run_id" > "$root/$stop_file"

  case "$pid" in
    ''|*[!0-9]*) ;;
    *) if kill -0 "$pid" 2>/dev/null; then kill -TERM "$pid" 2>/dev/null || true; fi ;;
  esac
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
  local status_file id type target status round summary started finished live glyph

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
# Returns 1 for an unknown type, 2 when a required field is missing (ralph: prd;
# harden: target).
almanac_loop_new_run_argv() {
  local type="$1"; shift
  local prd="" mode="" provider="" model="" effort="" iterations="" oversee="" target="" rounds="" kv key val
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
    *) return 1 ;;
  esac
  return 0
}
