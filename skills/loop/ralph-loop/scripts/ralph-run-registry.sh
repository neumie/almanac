#!/usr/bin/env bash
# ralph-run-registry.sh - Ralph launcher run registry helpers.

# pwd -P resolves the install symlink (~/.claude/skills/almanac/<name> -> repo),
# so ALMANAC_HOME points at the real repo whether launched from repo or install path.
RALPH_REGISTRY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ALMANAC_HOME="${ALMANAC_HOME:-$(cd "$RALPH_REGISTRY_SCRIPT_DIR/../../../.." && pwd -P)}"

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
