#!/usr/bin/env bash
# hub.sh — interactive front door to almanac loops (ralph, harden)
#
# Bare `almanac` routes here on a TTY (and `almanac hub` always does). The hub
# reads the run registry under the caller's repo ($PWD/.almanac/runs) and shows
# the loops it finds: a Running section (live status) and a Recent section (last
# finished). On a TTY with gum and at least one run it opens an interactive menu
# to act on a running loop — watch its live status, stop it, or queue a steer
# directive for its next round. Off a TTY / without gum it renders that overview
# as plain text and exits — it never blocks on a menu, so `almanac hub | cat`,
# scripts and tests get a clean read view.
#
# The per-run actions are also drivable non-interactively, the seam the menu and
# scripts/tests share:
#   almanac hub --watch <id>           tail a run's live status (one frame off a TTY)
#   almanac hub --stop  <id>           signal a run to stop (.stop file + TERM)
#   almanac hub --steer <id> <text…>   queue a steer directive for the next round

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-core.sh"

ROOT="$PWD"

hub_usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac hub                      open the hub (interactive on a TTY, overview otherwise)"
  printf '%s\n' "  almanac hub --watch <run-id>     tail a run's live status"
  printf '%s\n' "  almanac hub --stop  <run-id>     signal a run to stop"
  printf '%s\n' "  almanac hub --steer <run-id> …   queue a steer directive for the next round"
}

# Interactive gum menu: pick a running loop, then watch / stop / steer it. Only
# entered on a TTY with gum (the caller guards), so the gum calls always resolve.
# Loops until the operator quits or no running loops remain. Each running row ends
# with "[id]"; the chosen line is mapped back to the run id to act on.
almanac_hub_menu() {
  local root="$1"
  local running choice run_id action directive

  while :; do
    almanac_loop_ui_clear
    almanac_loop_hub_overview "$root"

    running="$(almanac_loop_hub_render "$root" running 2>/dev/null || true)"
    if [ -z "$running" ]; then
      _info "No running loops to act on."
      return 0
    fi

    choice="$(printf '%s\nquit\n' "$running" | gum choose --header "Select a running loop")" || return 0
    [ "$choice" = "quit" ] && return 0
    run_id="$(printf '%s\n' "$choice" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')"
    [ -n "$run_id" ] || continue

    action="$(gum choose --header "Run $run_id" watch stop steer back)" || continue
    case "$action" in
      watch)
        almanac_loop_run_watch "$root" "$run_id" follow || _warn "No status for run: $run_id"
        ;;
      stop)
        if gum confirm "Stop $run_id?"; then
          if almanac_loop_run_stop "$root" "$run_id"; then
            _success "Stop requested for $run_id"
          else
            _warn "Could not stop $run_id"
          fi
        fi
        ;;
      steer)
        directive="$(gum input --header "Steer $run_id" --placeholder "redirect the next round…")" || continue
        if almanac_loop_run_steer "$root" "$run_id" "$directive"; then
          _success "Steer queued for $run_id"
        else
          _warn "Empty or unsupported steer for $run_id"
        fi
        ;;
      back) : ;;
    esac
  done
}

ACTION=""
ACTION_ID=""
STEER_DIRECTIVE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      hub_usage
      exit 0
      ;;
    --watch)
      shift
      [ "$#" -gt 0 ] || _die "Missing run id for --watch"
      ACTION="watch"
      ACTION_ID="$1"
      ;;
    --stop)
      shift
      [ "$#" -gt 0 ] || _die "Missing run id for --stop"
      ACTION="stop"
      ACTION_ID="$1"
      ;;
    --steer)
      shift
      [ "$#" -gt 0 ] || _die "Missing run id for --steer"
      ACTION="steer"
      ACTION_ID="$1"
      shift
      STEER_DIRECTIVE="${*:-}"
      break
      ;;
    -*)
      _die "Unknown hub option: $1"
      ;;
    *)
      _die "Unexpected hub argument: $1"
      ;;
  esac
  shift
done

case "$ACTION" in
  watch)
    almanac_loop_run_watch "$ROOT" "$ACTION_ID" follow || _die "Unknown run: $ACTION_ID"
    exit 0
    ;;
  stop)
    STOP_RC=0
    almanac_loop_run_stop "$ROOT" "$ACTION_ID" || STOP_RC="$?"
    case "$STOP_RC" in
      0) _success "Stop requested for run: $ACTION_ID"; exit 0 ;;
      2) _die "Unknown run: $ACTION_ID" ;;
      3) _die "Run '$ACTION_ID' has no stop convention" ;;
      *) _die "Failed to stop run: $ACTION_ID" ;;
    esac
    ;;
  steer)
    STEER_RC=0
    almanac_loop_run_steer "$ROOT" "$ACTION_ID" "$STEER_DIRECTIVE" || STEER_RC="$?"
    case "$STEER_RC" in
      0) _success "Steer queued for run: $ACTION_ID"; exit 0 ;;
      2) _die "Unknown run: $ACTION_ID" ;;
      3) _die "Run '$ACTION_ID' has no steer convention" ;;
      4) _die "Steer directive is empty" ;;
      *) _die "Failed to steer run: $ACTION_ID" ;;
    esac
    ;;
esac

# No explicit action: bare hub. On a TTY with gum and at least one run, open the
# interactive menu; otherwise render the read-only overview (the scripts-safe path
# tests and pipes get, and the gum-absent fallback).
if [ -t 0 ] && [ -t 1 ] && almanac_loop_ui_has_gum && almanac_loop_list_runs "$ROOT" >/dev/null 2>&1; then
  almanac_hub_menu "$ROOT"
else
  almanac_loop_hub_overview "$ROOT"
fi
