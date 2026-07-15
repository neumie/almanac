#!/usr/bin/env bash
# loop-run-registry.sh - Loop launcher run registry helpers.

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

LOOP_RUN_ID="${LOOP_RUN_ID:-}"

loop_register_run() {
  local spec_name="$1"
  local target pid

  # Prefer spec.md; fall back to legacy prd.md so old plan dirs keep working.
  target="docs/plans/${spec_name}/spec.md"
  [ -f "$target" ] || target="docs/plans/${spec_name}/prd.md"
  pid="${BASHPID:-$$}"

  if ! LOOP_RUN_ID="$(almanac_loop_register_run "$PWD" "loop" "$target" "$pid")"; then
    echo "Error: failed to register Loop run." >&2
    return 1
  fi
}

# Emit the live half of the shared run-status contract: record the current
# iteration (as the contract's `round` field) and a one-line summary into the
# run's status.tsv blob, so the almanac hub's read view reflects progress while
# the loop runs. Mirrors the shared per-round almanac_loop_update_run_progress
# call. Best-effort: a missing run id or any registry failure must never break
# the loop, so it is fully guarded.
loop_update_run_progress() {
  local round="$1"
  local summary="$2"
  local qp status_file

  [ -n "$LOOP_RUN_ID" ] || return 0

  almanac_loop_update_run_progress "$PWD" "$LOOP_RUN_ID" "$round" "$summary" >/dev/null 2>&1 || true

  # Best-effort queue progress (closed/total) so the hub also shows task-level
  # progress alongside the iteration count. Skips silently when no queue is
  # detectable, when gh isn't authed, or when the registry write fails.
  if [ -n "${SPEC_NAME:-}" ]; then
    qp="$(loop_queue_progress "$SPEC_NAME" 2>/dev/null || true)"
    if [ -n "$qp" ]; then
      status_file="$(almanac_loop_run_status_file "$PWD" "$LOOP_RUN_ID" 2>/dev/null || true)"
      [ -n "$status_file" ] && [ -f "$status_file" ] && \
        almanac_loop_record_set "$status_file" "queue_progress=$qp" >/dev/null 2>&1 || true
    fi
  fi
}

# Stamp the run's launch config onto its registry blob (after register_run) so
# resume/clone can rebuild the same command. Best-effort: registry trouble must
# never sink the run; absent values stay blank and are simply skipped at resume.
loop_set_run_config() {
  [ -n "$LOOP_RUN_ID" ] || return 0
  almanac_loop_set_run_config "$PWD" "$LOOP_RUN_ID" "$@" >/dev/null 2>&1 || true
}

loop_mark_run_finished() {
  local exit_code="$1"
  local status="" reason=""

  [ -n "$LOOP_RUN_ID" ] || return 0

  if [ "$exit_code" -eq 0 ]; then
    status="done"
  else
    status="failed"
    # Reason makes a failure tell its own story in the hub. exit=N alone is
    # already a win over an unexplained ✘; an opportunistic hint from the
    # latest codex log adds the actual cause when one is grep-able (best
    # effort — a missing/empty log just falls back to the bare exit code).
    reason="exit=$exit_code"
    if [ -n "${SPEC_NAME:-}" ]; then
      local last_log hint
      last_log="$(ls -t "docs/plans/${SPEC_NAME}/loop-codex-"*.log 2>/dev/null | head -1)"
      if [ -n "$last_log" ] && [ -f "$last_log" ]; then
        hint="$(tail -n 30 "$last_log" 2>/dev/null | grep -m1 -E '^Codex failed|^Claude failed|^Error:|fatal error' || true)"
        [ -n "$hint" ] && reason="$reason; ${hint:0:160}"
      fi
    fi
  fi

  almanac_loop_mark_run_status "$PWD" "$LOOP_RUN_ID" "$status" "" "$reason" >/dev/null 2>&1 || true
}

loop_finish_run() {
  local exit_code="$1"

  trap - EXIT
  loop_mark_run_finished "$exit_code"
  exit "$exit_code"
}

# Report "<closed>/<total>" for the loop queue of SPEC_NAME, or print nothing if
# no queue is detectable. Detect order matches the prompt:
#   1) local slice files at docs/plans/<name>/issues/*.md — total = files,
#      done = files whose frontmatter has "status: done"
#   2) GitHub issues labelled loop(<name>) — closed + open via `gh issue list
#      --search` (only when gh is on PATH; network failures fall through silent)
# Best-effort throughout — every helper is guarded so a slow or broken gh / a
# missing issues dir never sinks the calling iteration. Prints nothing on no
# queue, so callers can `[ -n "$qp" ]` cheaply.
loop_queue_progress() {
  local spec_name="$1"
  local issues_dir="docs/plans/${spec_name}/issues"
  local total done_count closed open

  if [ -d "$issues_dir" ]; then
    total=$(find "$issues_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "${total:-0}" -gt 0 ]; then
      done_count=$(grep -l '^status: done' "$issues_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
      printf '%s/%s\n' "${done_count:-0}" "$total"
      return 0
    fi
  fi

  if command -v gh >/dev/null 2>&1; then
    closed=$(gh issue list --search "label:\"loop(${spec_name})\" state:closed" --limit 200 --json number -q 'length' 2>/dev/null || echo "")
    open=$(gh issue list   --search "label:\"loop(${spec_name})\" state:open"   --limit 200 --json number -q 'length' 2>/dev/null || echo "")
    if [ -n "$closed" ] && [ -n "$open" ]; then
      total=$((closed + open))
      if [ "$total" -gt 0 ]; then
        printf '%s/%s\n' "$closed" "$total"
        return 0
      fi
    fi
  fi
  return 0
}
