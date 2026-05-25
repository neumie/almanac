#!/usr/bin/env bash
# ralph-run-registry.sh - Ralph launcher run registry helpers.

# ALMANAC_HOME bootstrap — prefer an exported value, else self-resolve
# symlink-safe (pwd -P) at this file's known depth. Mirrors almanac_resolve_home
# in lib/core.sh; keep the two in sync. pwd -P resolves the install dir-symlink
# (~/.claude/skills/almanac/<name> -> repo), so this points at the real repo
# whether launched from the repo or the install path.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)}"

if [ ! -f "$ALMANAC_HOME/lib/loop-core.sh" ]; then
  echo "Error: lib/loop-core.sh not found at $ALMANAC_HOME/lib/loop-core.sh" >&2
  return 1 2>/dev/null || exit 1
fi

source "$ALMANAC_HOME/lib/loop-core.sh"

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
  local status

  [ -n "$RALPH_RUN_ID" ] || return 0

  if [ "$exit_code" -eq 0 ]; then
    status="done"
  else
    status="failed"
  fi

  almanac_loop_mark_run_status "$PWD" "$RALPH_RUN_ID" "$status" >/dev/null 2>&1 || true
}

ralph_finish_run() {
  local exit_code="$1"

  trap - EXIT
  ralph_mark_run_finished "$exit_code"
  exit "$exit_code"
}
