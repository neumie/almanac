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

almanac_converge_commit_round() {
  local root="$1"
  local plan_dir="$2"
  local slug="$3"
  local round="$4"
  local rel_plan status

  status="$(almanac_converge_git_user_status "$root" "$plan_dir" 2>/dev/null || true)"
  [ -n "$status" ] || return 0

  rel_plan="${plan_dir#"$root"/}"
  if [ "$rel_plan" = "$plan_dir" ]; then
    if ! git -C "$root" add -A -- . ':!.almanac' >/dev/null 2>&1; then
      _warn "Converge round $round: git add failed; continuing without commit"
      return 0
    fi
  else
    if ! git -C "$root" add -A -- . ':!.almanac' ":!$rel_plan" >/dev/null 2>&1; then
      _warn "Converge round $round: git add failed; continuing without commit"
      return 0
    fi
  fi

  if git -C "$root" diff --cached --quiet --exit-code >/dev/null 2>&1; then
    return 0
  fi

  if ! git -C "$root" commit -m "CONVERGE($slug): round $round" --no-verify >/dev/null 2>&1; then
    _warn "Converge round $round: git commit failed; continuing"
  fi
}

almanac_converge_run() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local rounds="${4:-${CONVERGE_ROUND_BUDGET:-10}}"
  local slug plan_dir reports run_id pid exec_rc ts round

  case "$rounds" in
    ''|*[!0-9]*) _die "--rounds must be a positive integer: $rounds" ;;
  esac
  [ "$rounds" -ge 1 ] || _die "--rounds must be at least 1: $rounds"

  slug="$(almanac_converge_slug "$goal")"
  pid="${BASHPID:-$$}"
  run_id="$(almanac_loop_register_run "$root" "converge" "$slug" "$pid")" \
    || _die "Could not register converge run"

  local _converge_run_finalize_cmd
  printf -v _converge_run_finalize_cmd 'almanac_converge_run_finalize %q %q aborted' "$root" "$run_id"
  trap "${_converge_run_finalize_cmd}; exit 130" INT TERM
  trap "${_converge_run_finalize_cmd}" EXIT

  almanac_loop_set_run_config "$root" "$run_id" "rounds=$rounds" >/dev/null 2>&1 || true

  almanac_converge_scaffold "$root" "$goal"
  plan_dir="$(almanac_converge_plan_dir "$root" "$goal")"
  reports="$plan_dir/agent-reports.log"

  round=0
  while [ "$round" -lt "$rounds" ]; do
    round=$((round + 1))
    if (cd "$root" && bash -c "$exec_cmd"); then
      exec_rc=0
    else
      exec_rc=$?
    fi

    almanac_converge_commit_round "$root" "$plan_dir" "$slug" "$round"

    if [ "$exec_rc" -ne 0 ]; then
      if [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
        _warn "Converge round $round exec exited $exec_rc; stopping"
      else
        _warn "Converge round $round exec exited $exec_rc; continuing"
      fi
    fi

    ts="$(almanac_loop_now_utc)"
    printf '===== tick=%s ts=%s exit=%s =====\n' "$round" "$ts" "$exec_rc" >> "$reports" \
      || _die "Could not append converge report: ${reports#"$root"/}"

    almanac_loop_update_run_progress "$root" "$run_id" "$round" "goal=$slug" >/dev/null 2>&1 || true

    if [ "$exec_rc" -ne 0 ] && [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
      almanac_converge_run_finalize "$root" "$run_id" "failed" "exec exit=$exec_rc round=$round"
      return "$exec_rc"
    fi
  done

  almanac_converge_run_finalize "$root" "$run_id" "done"
}
