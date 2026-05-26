#!/usr/bin/env bash
# ralph-run-registry.sh - Ralph launcher run registry helpers.

# ALMANAC_HOME bootstrap — prefer an exported value, else self-resolve
# symlink-safe (pwd -P) at this file's known depth. Mirrors almanac_resolve_home
# in lib/core.sh; keep the two in sync. pwd -P resolves the install dir-symlink
# (~/.claude/skills/almanac/<name> -> repo), so this points at the real repo
# whether launched from the repo or the install path.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)}"

if [ ! -f "$ALMANAC_HOME/lib/run.sh" ]; then
  echo "Error: lib/run.sh not found at $ALMANAC_HOME/lib/run.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# The run registry (register/update/mark) lives in lib/run.sh — source it
# directly rather than the deleted loop-core barrel.
source "$ALMANAC_HOME/lib/run.sh"

RALPH_RUN_ID="${RALPH_RUN_ID:-}"

ralph_register_run() {
  local prd_name="$1"
  local target pid

  target="docs/plans/${prd_name}/prd.md"
  pid="${BASHPID:-$$}"

  if ! RALPH_RUN_ID="$(almanac_loop_register_run "$PWD" "ralph" "$target" "$pid")"; then
    echo "Error: failed to register Ralph run." >&2
    return 1
  fi
}

# Emit the live half of the shared run-status contract: record the current
# iteration (as the contract's `round` field) and a one-line summary into the
# run's status.tsv blob, so the almanac hub's read view reflects progress while
# the loop runs. Mirrors harden's per-round almanac_loop_update_run_progress
# call. Best-effort: a missing run id or any registry failure must never break
# the loop, so it is fully guarded.
ralph_update_run_progress() {
  local round="$1"
  local summary="$2"

  [ -n "$RALPH_RUN_ID" ] || return 0

  almanac_loop_update_run_progress "$PWD" "$RALPH_RUN_ID" "$round" "$summary" >/dev/null 2>&1 || true
}

ralph_mark_run_finished() {
  local exit_code="$1"
  local status="" reason=""

  [ -n "$RALPH_RUN_ID" ] || return 0

  if [ "$exit_code" -eq 0 ]; then
    status="done"
  else
    status="failed"
    # Reason makes a failure tell its own story in the hub. exit=N alone is
    # already a win over an unexplained ✘; an opportunistic hint from the
    # latest codex log adds the actual cause when one is grep-able (best
    # effort — a missing/empty log just falls back to the bare exit code).
    reason="exit=$exit_code"
    if [ -n "${PRD_NAME:-}" ]; then
      local last_log hint
      last_log="$(ls -t "docs/plans/${PRD_NAME}/ralph-codex-"*.log 2>/dev/null | head -1)"
      if [ -n "$last_log" ] && [ -f "$last_log" ]; then
        hint="$(tail -n 30 "$last_log" 2>/dev/null | grep -m1 -E '^Codex failed|^Claude failed|^Error:|fatal error' || true)"
        [ -n "$hint" ] && reason="$reason; ${hint:0:160}"
      fi
    fi
  fi

  almanac_loop_mark_run_status "$PWD" "$RALPH_RUN_ID" "$status" "" "$reason" >/dev/null 2>&1 || true
}

ralph_finish_run() {
  local exit_code="$1"

  trap - EXIT
  ralph_mark_run_finished "$exit_code"
  exit "$exit_code"
}
