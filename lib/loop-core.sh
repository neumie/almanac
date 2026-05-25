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

  {
    printf 'id\t%s\n' "$run_id"
    printf 'type\t%s\n' "$type"
    printf 'target\t%s\n' "$target"
    printf 'pid\t%s\n' "$pid"
    printf 'status_file\t%s\n' "$status_rel"
    printf 'started_at\t%s\n' "$started_at"
    printf 'status\t%s\n' "$status"
    printf 'finished_at\t%s\n' "$finished_at"
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
  local status_file index_file tmp type target pid status_rel started_at

  case "$status" in
    done|failed) ;;
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

  almanac_loop_write_run_status "$status_file" "$run_id" "$type" "$target" "$pid" "$status_rel" "$started_at" "$status" "$finished_at"
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

almanac_loop_agent_claude_permission() {
  case "$1" in
    read-only) printf '%s\n' "plan" ;;
    *) printf '%s\n' "acceptEdits" ;;
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

almanac_loop_agent_run() {
  [ "$#" -ge 6 ] || return 2

  local provider="$1"
  local model="$2"
  local effort="$3"
  local sandbox="$4"
  local prompt_file="$5"
  local result_file="$6"
  local events_file="${7:-}"
  local provider_key prompt

  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2

  provider_key="$(almanac_loop_agent_provider_key "$provider")"
  prompt="$(cat "$prompt_file")"
  sandbox="${sandbox:-danger-full-access}"

  # Raw provider events stream to a JSONL log. The caller may pass its own path
  # (per-run events.jsonl); otherwise we allocate one. Either way the path is
  # echoed back at the end so the caller can locate the stream.
  if [ -z "$events_file" ]; then
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
        --json
        --output-last-message "$result_file"
      )

      if [ -n "$model" ]; then
        codex_args+=(--model "$model")
      fi

      if [ -n "$effort" ]; then
        codex_args+=(-c "model_reasoning_effort=\"$effort\"")
      fi

      codex "${codex_args[@]}" "$prompt" > "$events_file" || return "$?"
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
        --permission-mode "$(almanac_loop_agent_claude_permission "$sandbox")"
      )

      if [ -n "$model" ]; then
        claude_args+=(--model "$model")
      fi

      if [ -n "$effort" ]; then
        claude_args+=(--effort "$effort")
      fi

      # No pipe: a direct redirect keeps $? as claude's exit so a provider
      # failure propagates instead of being masked by a downstream tee.
      claude "${claude_args[@]}" "$prompt" > "$events_file" || return "$?"
      almanac_loop_agent_extract_claude_result "$events_file" "$result_file"
      ;;
    *)
      _error "unsupported provider: $provider"
      return 3
      ;;
  esac

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
