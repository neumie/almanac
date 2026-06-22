#!/usr/bin/env bash
# hub.sh — interactive front door to almanac loops.
# summary: Open the loop hub (list / watch / launch loops)
# usage: almanac hub [--watch ID | --stop ID | --steer ID … | --new LOOP … | --resume ID | --clone ID | --stats]
# group: loops
#
# Bare `almanac` routes here on a TTY (and `almanac hub` always does). The hub
# reads the run registry under the caller's repo ($PWD/.almanac/runs) and shows
# the loops it finds: a Running section (live status) and a Recent section (last
# finished). On a TTY it opens an interactive menu — start a new run, or act on a
# running loop (watch its live status, stop it, or queue a steer directive for its
# next round). The menu is gum-styled when gum is present and degrades to a plain
# numbered menu (built on the shared almanac_loop_ui_choose/input/confirm seam)
# when gum is absent, so it works on any TTY. Off a TTY it renders the overview as
# plain text and exits — it never blocks on a menu, so `almanac hub | cat`, scripts
# and tests get a clean read view.
#
# The per-run actions are also drivable non-interactively, the seam the menu and
# scripts/tests share:
#   almanac hub --watch <id>           tail a run's live status (one frame off a TTY)
#   almanac hub --stop  <id>           signal a run to stop (loop stop file)
#   almanac hub --steer <id> <text…>   queue a steer directive for the next round
#   almanac hub --new <loop> [config…] [--dry-run]
#                                      launch a new run (dry-run previews the command)
#   almanac hub --resume <id>          re-launch a finished run with the same config (auto-confirm)
#   almanac hub --clone  <id>          start the launcher pre-filled from a finished run (no auto-confirm)
#   almanac hub --stats                summarise finished runs by (type, provider, model)

set -euo pipefail

# cmd/hub.sh is the parse+dispatch shim; all the composable hub logic lives in
# lib/hub-core.sh (testable in isolation). hub-core sources its own siblings
# (run.sh / ui.sh / loop-launcher.sh) idempotently; core.sh is sourced here too
# since dispatch uses _die/_success directly.
source "$ALMANAC_HOME/lib/core.sh"
source "$ALMANAC_HOME/lib/hub-core.sh"

ROOT="$PWD"

ACTION=""
ACTION_ID=""
STEER_DIRECTIVE=""
ACTION_TYPE=""
NEW_DRY_RUN=0
NEW_OPTS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      almanac_hub_usage
      exit 0
      ;;
    --new)
      shift
      [ "$#" -gt 0 ] || _die "Missing run type for --new ($(almanac_hub_loop_names_inline))"
      ACTION="new"
      ACTION_TYPE="$1"
      shift
      # Remaining args are New-run config flags (mapped to key=value pairs the
      # pure composer consumes), plus --dry-run.
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --dry-run)    NEW_DRY_RUN=1 ;;
          --prd)        shift; [ "$#" -gt 0 ] || _die "Missing value for --prd";        NEW_OPTS+=("prd=$1") ;;
          --mode)       shift; [ "$#" -gt 0 ] || _die "Missing value for --mode";       NEW_OPTS+=("mode=$1") ;;
          --provider)   shift; [ "$#" -gt 0 ] || _die "Missing value for --provider";   NEW_OPTS+=("provider=$1") ;;
          --model)      shift; [ "$#" -gt 0 ] || _die "Missing value for --model";      NEW_OPTS+=("model=$1") ;;
          --effort)     shift; [ "$#" -gt 0 ] || _die "Missing value for --effort";     NEW_OPTS+=("effort=$1") ;;
          --iterations) shift; [ "$#" -gt 0 ] || _die "Missing value for --iterations"; NEW_OPTS+=("iterations=$1") ;;
          --no-oversee) NEW_OPTS+=("oversee=off") ;;
          --target)     shift; [ "$#" -gt 0 ] || _die "Missing value for --target";     NEW_OPTS+=("target=$1") ;;
          --rounds)     shift; [ "$#" -gt 0 ] || _die "Missing value for --rounds";     NEW_OPTS+=("rounds=$1") ;;
          --lenses)     shift; [ "$#" -gt 0 ] || _die "Missing value for --lenses";     NEW_OPTS+=("lenses=$1") ;;
          --goal)       shift; [ "$#" -gt 0 ] || _die "Missing value for --goal";       NEW_OPTS+=("goal=$1") ;;
          --exec)       shift; [ "$#" -gt 0 ] || _die "Missing value for --exec";       NEW_OPTS+=("exec=$1") ;;
          --prompt)     shift; [ "$#" -gt 0 ] || _die "Missing value for --prompt";     NEW_OPTS+=("prompt=$1") ;;
          --oversee-every) shift; [ "$#" -gt 0 ] || _die "Missing value for --oversee-every"; NEW_OPTS+=("oversee_every=$1") ;;
          -*) _die "Unknown hub --new option: $1" ;;
          *)  _die "Unexpected hub --new argument: $1" ;;
        esac
        shift
      done
      break
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
    --resume)
      shift
      [ "$#" -gt 0 ] || _die "Missing run id for --resume"
      ACTION="resume"
      ACTION_ID="$1"
      ;;
    --clone)
      shift
      [ "$#" -gt 0 ] || _die "Missing run id for --clone"
      ACTION="clone"
      ACTION_ID="$1"
      ;;
    --stats)
      ACTION="stats"
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
  new)
    NEW_RC=0
    if [ "${#NEW_OPTS[@]}" -gt 0 ]; then
      NEW_ARGV_RAW="$(almanac_loop_new_run_argv "$ACTION_TYPE" "${NEW_OPTS[@]}")" || NEW_RC="$?"
    else
      NEW_ARGV_RAW="$(almanac_loop_new_run_argv "$ACTION_TYPE")" || NEW_RC="$?"
    fi
    case "$NEW_RC" in
      0) ;;
      1) _die "Unknown run type: $ACTION_TYPE (use $(almanac_hub_loop_names_inline))" ;;
      2) _die "Missing or invalid config for $ACTION_TYPE: $(almanac_hub_new_run_config_hint "$ACTION_TYPE")" ;;
      *) _die "Could not compose $ACTION_TYPE run" ;;
    esac
    if [ "${#NEW_OPTS[@]}" -gt 0 ]; then
      NEW_ENV_RAW="$(almanac_loop_new_run_env "$ACTION_TYPE" "${NEW_OPTS[@]}")" || NEW_ENV_RAW=""
    else
      NEW_ENV_RAW="$(almanac_loop_new_run_env "$ACTION_TYPE")" || NEW_ENV_RAW=""
    fi
    almanac_hub_launch_new "$NEW_DRY_RUN" "$NEW_ENV_RAW" "$NEW_ARGV_RAW"
    exit 0
    ;;
  resume|clone)
    almanac_hub_resume_or_clone "$ACTION" "$ACTION_ID"
    exit 0
    ;;
  stats)
    if STATS_OUT="$(almanac_loop_hub_stats "$ROOT")"; then
      printf '%s\n' "$STATS_OUT" | almanac_loop_ui_render
    else
      printf '%s\n' "(no finished runs to summarise)" | almanac_loop_ui_render
    fi
    exit 0
    ;;
esac

# No explicit action: bare hub. On a TTY, open the interactive menu — always, even
# with an empty registry, so New run is reachable with no prior runs. The menu
# degrades internally: gum-styled when gum is present, plain numbered menus (via
# the shared almanac_loop_ui_* seam) when it is absent. Off a TTY (piped/captured)
# render the read-only overview once — the scripts-safe path tests and pipes get.
if [ -t 0 ] && [ -t 1 ]; then
  almanac_hub_menu "$ROOT"
else
  almanac_loop_hub_overview "$ROOT"
fi
