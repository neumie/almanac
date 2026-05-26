#!/usr/bin/env bash
# converge-core.sh - Generic convergence loop core

# Source focused deps idempotently so tests can source this file directly.
if ! declare -F _error >/dev/null 2>&1; then
  __converge_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__converge_core_dir/core.sh"
  unset __converge_core_dir
fi

if ! declare -F almanac_loop_register_run >/dev/null 2>&1; then
  __converge_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/run.sh
  source "$__converge_core_dir/run.sh"
  unset __converge_core_dir
fi

if ! declare -F almanac_loop_agent_capture >/dev/null 2>&1; then
  __converge_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/agent.sh
  source "$__converge_core_dir/agent.sh"
  unset __converge_core_dir
fi

if ! declare -F almanac_loop_role_config >/dev/null 2>&1; then
  __converge_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/role.sh
  source "$__converge_core_dir/role.sh"
  unset __converge_core_dir
fi

almanac_converge_slug() {
  almanac_loop_slug "$1"
}

almanac_converge_plan_dir() {
  local root="$1"
  local goal="$2"
  local slug

  slug="$(almanac_converge_slug "$goal")"
  printf '%s/docs/plans/converge/%s\n' "$root" "$slug"
}

almanac_converge_scaffold() {
  local root="$1"
  local goal="$2"
  local plan_dir

  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"

  if ! mkdir -p "$plan_dir"; then
    _die "Could not create converge plan dir: ${plan_dir#"$root"/}"
  fi
  if ! printf '%s\n' "$goal" > "$plan_dir/goal.md"; then
    _die "Could not write converge goal: ${plan_dir#"$root"/}/goal.md"
  fi
  if ! : > "$plan_dir/agent-reports.log"; then
    _die "Could not write converge report log: ${plan_dir#"$root"/}/agent-reports.log"
  fi
  if ! : > "$plan_dir/goal.history.log"; then
    _die "Could not write converge goal history: ${plan_dir#"$root"/}/goal.history.log"
  fi
}

almanac_converge_role() {
  local role="$1"

  case "$role" in
    agent|overseer) ;;
    *) return 2 ;;
  esac

  almanac_loop_role_config "converge" "$role" "" "$(almanac_provider_default)" "" ""
}

almanac_converge_role_field() {
  local role="$1"
  local field="$2"

  almanac_converge_role "$role" | awk -F'\t' -v k="$field" '$1 == k { v = $2 } END { print v }'
}

almanac_converge_ensure_prompt_template() {
  local root="$1"
  local goal="$2"
  local plan_dir prompt_file

  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  prompt_file="$plan_dir/prompt.md"
  [ -f "$prompt_file" ] && return 0

  cat > "$prompt_file" <<'EOF'
# Converge Worker

You are one worker round in a generic convergence loop.

Read current goal, follow one-shot steer directive if present, run exact exec
command, then leave clear evidence in git history and agent-reports.log.

Do not edit the goal unless explicitly asked by the exec command. Do not commit
.almanac or converge state files under docs/plans/converge/.
EOF
}

almanac_converge_worker_prompt() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local round="$4"
  local slug plan_dir rel_plan steer_file

  slug="$(almanac_converge_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  rel_plan="${plan_dir#"$root"/}"
  steer_file="$root/.converge-steer"

  almanac_converge_ensure_prompt_template "$root" "$goal"

  cat "$plan_dir/prompt.md"
  cat <<EOF

CONVERGE_TICK=$round
CONVERGE_SLUG=$slug
CONVERGE_PLAN_DIR=$rel_plan
CONVERGE_REPORT_LOG=$rel_plan/agent-reports.log

Commit user-visible worktree changes, excluding .almanac and $rel_plan, with:
CONVERGE($slug): <one-line summary>

Append one structured self-report to $rel_plan/agent-reports.log. Use this exact
header shape and these exact section labels:

===== tick=<N> ts=<ISO> =====
summary:
concerns:
next:

For this round, N is $round.

===== GOAL.md =====
EOF
  cat "$plan_dir/goal.md"
  cat <<EOF
===== END GOAL.md =====

===== EXEC COMMAND =====
$exec_cmd
===== END EXEC COMMAND =====
EOF

  if [ -f "$steer_file" ]; then
    cat <<'EOF'

===== STEER =====
EOF
    cat "$steer_file"
    cat <<'EOF'
===== END STEER =====
EOF
    rm -f "$steer_file"
  fi
}

almanac_converge_report_log_has_structured_block() {
  local file="$1"

  [ -f "$file" ] || return 1
  awk '
    /^===== tick=[0-9][0-9]* ts=.* =====$/ {
      seen = 1
      summary = 0
      concerns = 0
      next_seen = 0
      next
    }
    seen && /^summary:$/ { summary = 1; next }
    seen && /^concerns:$/ { concerns = 1; next }
    seen && /^next:$/ { next_seen = 1; ok = summary && concerns && next_seen; next }
    END { exit ok ? 0 : 1 }
  ' "$file"
}

almanac_converge_trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

almanac_converge_overseer_prompt() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local slug plan_dir rel_plan reports_file reports commits

  slug="$(almanac_converge_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  rel_plan="${plan_dir#"$root"/}"
  reports_file="$plan_dir/agent-reports.log"

  if [ -f "$reports_file" ]; then
    reports="$(tail -c 8192 "$reports_file")"
  else
    reports="(no agent reports yet)"
  fi

  commits="$(git -C "$root" log --fixed-strings --grep="CONVERGE($slug):" -n 10 \
    --format='%H%n%ad%n%B%n---' --date=short 2>/dev/null || true)"
  [ -n "$commits" ] || commits="No CONVERGE commits yet"

  cat <<EOF
You are the overseer for converge($slug), a synchronous convergence loop.

CONVERGE_TICK=$round
CONVERGE_SLUG=$slug
CONVERGE_PLAN_DIR=$rel_plan

Judge whether the current goal is satisfied, whether the next worker needs a
one-shot steering directive, or whether the loop should stop.

===== GOAL.md =====
EOF
  cat "$plan_dir/goal.md"
  cat <<EOF
===== END GOAL.md =====

===== RECENT AGENT SELF-REPORTS (last ~8KB) =====
$reports
===== END RECENT AGENT SELF-REPORTS =====

===== RECENT CONVERGE COMMITS (last 10) =====
$commits
===== END RECENT CONVERGE COMMITS =====

Output these fields in order with no preamble:
VERDICT: <CONVERGED|CONTINUE|STEER|STOP>
REASON: <one paragraph>
STEER: <one paragraph, or 'none'>
GOAL_UPDATE: <new goal.md content, or 'unchanged'>

Be conservative. Malformed output is treated as CONTINUE with no steering and no
goal update. GOAL_UPDATE may span multiple lines because it is the final field.
EOF
}

almanac_converge_overseer_parse() {
  local input="${1:-}"
  local content line key_line raw_verdict="" raw_reason="" raw_steer="" raw_goal=""
  local found_verdict=0 found_reason=0 found_steer=0 found_goal=0

  if [ -f "$input" ]; then
    content="$(cat "$input")"
  else
    content="$input"
  fi

  ALMANAC_CONVERGE_VERDICT="CONTINUE"
  ALMANAC_CONVERGE_REASON=""
  ALMANAC_CONVERGE_STEER="none"
  ALMANAC_CONVERGE_GOAL_UPDATE="unchanged"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$found_goal" -eq 1 ]; then
      raw_goal="${raw_goal}"$'\n'"${line}"
      continue
    fi

    key_line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    case "$key_line" in
      VERDICT:*) found_verdict=1; raw_verdict="${key_line#VERDICT:}" ;;
      REASON:*) found_reason=1; raw_reason="${key_line#REASON:}" ;;
      STEER:*) found_steer=1; raw_steer="${key_line#STEER:}" ;;
      GOAL_UPDATE:*)
        found_goal=1
        raw_goal="${key_line#GOAL_UPDATE:}"
        case "$raw_goal" in
          " "*) raw_goal="${raw_goal# }" ;;
        esac
        ;;
    esac
  done <<< "$content"

  if [ "$found_verdict" -ne 1 ] || [ "$found_reason" -ne 1 ] || \
    [ "$found_steer" -ne 1 ] || [ "$found_goal" -ne 1 ]; then
    return 0
  fi

  raw_verdict="$(almanac_converge_trim "$raw_verdict")"
  case "$raw_verdict" in
    CONVERGED|CONTINUE|STEER|STOP) ALMANAC_CONVERGE_VERDICT="$raw_verdict" ;;
    *)
      ALMANAC_CONVERGE_VERDICT="CONTINUE"
      ALMANAC_CONVERGE_STEER="none"
      ALMANAC_CONVERGE_GOAL_UPDATE="unchanged"
      return 0
      ;;
  esac

  ALMANAC_CONVERGE_REASON="$(almanac_converge_trim "$raw_reason")"

  raw_steer="$(almanac_converge_trim "$raw_steer")"
  if [ -n "$raw_steer" ] && ! printf '%s\n' "$raw_steer" | grep -qiE '^none[[:space:]]*$'; then
    ALMANAC_CONVERGE_STEER="$raw_steer"
  fi

  if [ "$found_goal" -eq 1 ]; then
    local goal_check
    goal_check="$(almanac_converge_trim "$raw_goal")"
    if [ -n "$goal_check" ] && ! printf '%s\n' "$goal_check" | grep -qiE '^unchanged[[:space:]]*$'; then
      ALMANAC_CONVERGE_GOAL_UPDATE="$raw_goal"
    fi
  fi
}

almanac_converge_write_convergence() {
  local root="$1"
  local goal="$2"
  local verdict="$3"
  local tick="$4"
  local started_epoch="${5:-}"
  local reason="${6:-}"
  local plan_dir now_epoch elapsed

  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  now_epoch="$(date +%s)"
  elapsed=""
  case "$started_epoch" in
    ''|*[!0-9]*) ;;
    *) elapsed="$((now_epoch - started_epoch))s" ;;
  esac

  {
    printf '# Convergence\n\n'
    printf '## Final verdict\n\n%s\n\n' "$verdict"
    printf '## Tick count\n\n%s\n\n' "$tick"
    printf '## Time elapsed\n\n%s\n\n' "${elapsed:-unknown}"
    printf '## Final goal\n\n'
    if [ -f "$plan_dir/goal.md" ]; then
      cat "$plan_dir/goal.md"
    fi
    printf '\n\n## Final reason\n\n%s\n' "${reason:-none}"
  } > "$plan_dir/convergence.md"
}

almanac_converge_goal_summary() {
  printf '%s' "$1" | tr '\n' ' ' | cut -c 1-80
}

almanac_converge_apply_goal_update() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local provider="$4"
  local reason="$5"
  local new_goal="$6"
  local plan_dir goal_file history_file log_file ts old_goal old_file new_file diff_output diff_status summary

  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  goal_file="$plan_dir/goal.md"
  history_file="$plan_dir/goal.history.log"
  log_file="$plan_dir/overseer.log"
  ts="$(almanac_loop_now_utc)"
  old_goal=""
  [ -f "$goal_file" ] && old_goal="$(cat "$goal_file")"

  old_file="$plan_dir/.goal.old.$$"
  new_file="$plan_dir/.goal.new.$$"
  printf '%s\n' "$old_goal" > "$old_file"
  printf '%s\n' "$new_goal" > "$new_file"

  diff_output=""
  diff_status=127
  if command -v diff >/dev/null 2>&1; then
    if diff_output="$(diff -u "$old_file" "$new_file" 2>/dev/null)"; then
      diff_status=0
    else
      diff_status=$?
    fi
  fi

  {
    printf '===== tick=%s ts=%s overseer=%s =====\n' "$round" "$ts" "$provider"
    printf 'REASON: %s\n' "$reason"
    if [ "$diff_status" -le 1 ]; then
      printf -- '--- DIFF ---\n'
      printf '%s\n' "$diff_output"
    else
      printf -- '--- AFTER ---\n'
      printf '%s\n' "$new_goal"
    fi
  } >> "$history_file"

  printf '%s\n' "$new_goal" > "$goal_file"
  rm -f "$old_file" "$new_file"

  summary="$(almanac_converge_goal_summary "$new_goal")"
  printf '[tick=%s] goal updated: %s\n' "$round" "$summary" >> "$log_file"
}

almanac_converge_run_finalize() {
  local root="$1"
  local run_id="$2"
  local status="$3"
  local reason="${4:-}"

  trap - EXIT INT TERM
  [ -n "$run_id" ] || return 0
  almanac_loop_mark_run_status "$root" "$run_id" "$status" "" "$reason" >/dev/null 2>&1 || true
}

almanac_converge_git_user_status() {
  local root="$1"
  local plan_dir="$2"
  local rel_plan

  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  rel_plan="${plan_dir#"$root"/}"

  if [ "$rel_plan" = "$plan_dir" ]; then
    git -C "$root" status --porcelain -- . ':!.almanac'
  else
    git -C "$root" status --porcelain -- . ':!.almanac' ":!$rel_plan"
  fi
}

almanac_converge_run_worker() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local round="$4"
  local provider model effort prompt_file result_file events_file rc

  provider="$(almanac_converge_role_field "agent" "provider")"
  model="$(almanac_converge_role_field "agent" "model")"
  effort="$(almanac_converge_role_field "agent" "effort")"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-worker-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-worker-result.XXXXXX")"
  events_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-worker-events.XXXXXX")"

  almanac_converge_worker_prompt "$root" "$goal" "$exec_cmd" "$round" > "$prompt_file"

  rc=0
  almanac_loop_agent_capture "$provider" "$model" "$effort" "workspace-write" \
    "$prompt_file" "$result_file" "$events_file" >/dev/null || rc=$?

  rm -f "$prompt_file" "$result_file" "$events_file"
  return "$rc"
}

almanac_converge_run_overseer() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local provider model effort prompt_file result_file events_file result rc plan_dir log_file ts

  provider="$(almanac_converge_role_field "overseer" "provider")"
  model="$(almanac_converge_role_field "overseer" "model")"
  effort="$(almanac_converge_role_field "overseer" "effort")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  log_file="$plan_dir/overseer.log"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-result.XXXXXX")"
  events_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-events.XXXXXX")"

  almanac_converge_overseer_prompt "$root" "$goal" "$round" > "$prompt_file"

  rc=0
  (cd "$root" && almanac_loop_agent_capture "$provider" "$model" "$effort" "read-only" \
    "$prompt_file" "$result_file" "$events_file") >/dev/null || rc=$?

  result=""
  [ -s "$result_file" ] && result="$(cat "$result_file")"
  rm -f "$prompt_file" "$result_file" "$events_file"

  [ "$rc" -eq 0 ] || _warn "Converge overseer tick $round exited $rc; continuing"
  almanac_converge_overseer_parse "$result"

  ts="$(almanac_loop_now_utc)"
  {
    printf '\n===== tick=%s ts=%s overseer=%s exit=%s =====\n' "$round" "$ts" "$provider" "$rc"
    printf 'VERDICT: %s\n' "$ALMANAC_CONVERGE_VERDICT"
    printf 'REASON: %s\n' "$ALMANAC_CONVERGE_REASON"
    printf 'STEER: %s\n' "$ALMANAC_CONVERGE_STEER"
    printf 'GOAL_UPDATE: %s\n' "$ALMANAC_CONVERGE_GOAL_UPDATE"
  } >> "$log_file"

  if [ "$ALMANAC_CONVERGE_GOAL_UPDATE" != "unchanged" ]; then
    almanac_converge_apply_goal_update "$root" "$goal" "$round" "$provider" \
      "$ALMANAC_CONVERGE_REASON" "$ALMANAC_CONVERGE_GOAL_UPDATE"
  fi

  case "$ALMANAC_CONVERGE_VERDICT" in
    CONVERGED|STOP)
      : > "$root/.converge-stop"
      ;;
    STEER)
      if [ "$ALMANAC_CONVERGE_STEER" != "none" ]; then
        printf '%s\n' "$ALMANAC_CONVERGE_STEER" > "$root/.converge-steer"
      fi
      ;;
    CONTINUE) ;;
  esac
}

almanac_converge_run() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local rounds="${4:-${CONVERGE_ROUND_BUDGET:-10}}"
  local no_oversee="${5:-0}"
  local oversee_every="${6:-1}"
  local slug plan_dir run_id pid exec_rc round started_epoch final_status final_verdict final_reason

  case "$rounds" in
    ''|*[!0-9]*) _die "--rounds must be a positive integer: $rounds" ;;
  esac
  [ "$rounds" -ge 1 ] || _die "--rounds must be at least 1: $rounds"

  case "$oversee_every" in
    ''|*[!0-9]*) _die "--oversee-every must be a positive integer: $oversee_every" ;;
  esac
  [ "$oversee_every" -ge 1 ] || _die "--oversee-every must be at least 1: $oversee_every"

  case "$no_oversee" in
    1|true|yes|on) no_oversee=1 ;;
    *) no_oversee=0 ;;
  esac

  slug="$(almanac_converge_slug "$goal")"
  pid="${BASHPID:-$$}"
  started_epoch="$(date +%s)"
  run_id="$(almanac_loop_register_run "$root" "converge" "$slug" "$pid")" \
    || _die "Could not register converge run"

  local _converge_run_finalize_cmd
  printf -v _converge_run_finalize_cmd 'almanac_converge_run_finalize %q %q aborted' "$root" "$run_id"
  trap "${_converge_run_finalize_cmd}; exit 130" INT TERM
  trap "${_converge_run_finalize_cmd}" EXIT

  almanac_loop_set_run_config "$root" "$run_id" \
    "rounds=$rounds" \
    "oversee=$([ "$no_oversee" -eq 1 ] && printf off || printf 'every-%s' "$oversee_every")" \
    >/dev/null 2>&1 || true

  almanac_converge_scaffold "$root" "$goal"
  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"

  final_status="done"
  if [ "$no_oversee" -eq 1 ]; then
    final_verdict="NO_OVERSEE"
    final_reason="overseer disabled; round budget exhausted"
  else
    final_verdict="CONTINUE"
    final_reason="round budget exhausted"
  fi

  round=0
  while [ "$round" -lt "$rounds" ]; do
    if [ -f "$root/.converge-stop" ]; then
      final_status="aborted"
      final_verdict="STOP"
      final_reason="stop signal present before round $((round + 1))"
      break
    fi

    round=$((round + 1))
    if (cd "$root" && almanac_converge_run_worker "$root" "$goal" "$exec_cmd" "$round"); then
      exec_rc=0
    else
      exec_rc=$?
    fi

    if [ -n "$(almanac_converge_git_user_status "$root" "$plan_dir" 2>/dev/null || true)" ]; then
      _warn "Converge round $round: worker left uncommitted changes; driver will not commit"
    fi

    if [ "$exec_rc" -ne 0 ]; then
      if [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
        _warn "Converge round $round exec exited $exec_rc; stopping"
      else
        _warn "Converge round $round exec exited $exec_rc; continuing"
      fi
    fi

    almanac_loop_update_run_progress "$root" "$run_id" "$round" "goal=$slug" >/dev/null 2>&1 || true

    if [ "$exec_rc" -ne 0 ] && [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
      almanac_converge_write_convergence "$root" "$goal" "FAILED" "$round" "$started_epoch" "exec exit=$exec_rc round=$round"
      almanac_converge_run_finalize "$root" "$run_id" "failed" "exec exit=$exec_rc round=$round"
      return "$exec_rc"
    fi

    if [ "$no_oversee" -eq 0 ] && [ $((round % oversee_every)) -eq 0 ]; then
      almanac_converge_run_overseer "$root" "$goal" "$round"
      final_verdict="$ALMANAC_CONVERGE_VERDICT"
      final_reason="$ALMANAC_CONVERGE_REASON"
      case "$ALMANAC_CONVERGE_VERDICT" in
        CONVERGED)
          final_status="done"
          break
          ;;
        STOP)
          final_status="aborted"
          break
          ;;
      esac
    fi
  done

  almanac_converge_write_convergence "$root" "$goal" "$final_verdict" "$round" "$started_epoch" "$final_reason"
  almanac_converge_run_finalize "$root" "$run_id" "$final_status"
}
