#!/usr/bin/env bash
# hub.sh — interactive front door to almanac loops (ralph, harden)
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
#   almanac hub --new <ralph|harden|converge> [config…] [--dry-run]
#                                      launch a new run (dry-run previews the command)
#   almanac hub --resume <id>          re-launch a finished run with the same config (auto-confirm)
#   almanac hub --clone  <id>          start the launcher pre-filled from a finished run (no auto-confirm)
#   almanac hub --stats                summarise finished runs by (type, provider, model)

set -euo pipefail

source "$ALMANAC_HOME/lib/ui.sh"
source "$ALMANAC_HOME/lib/run.sh"
source "$ALMANAC_HOME/lib/loop-launcher.sh"

ROOT="$PWD"

hub_usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac hub                      open the hub (interactive on a TTY, overview otherwise)"
  printf '%s\n' "  almanac hub --watch <run-id>     tail a run's live status"
  printf '%s\n' "  almanac hub --stop  <run-id>     signal a run to stop"
  printf '%s\n' "  almanac hub --steer <run-id> …   queue a steer directive for the next round"
  printf '%s\n' "  almanac hub --new <ralph|harden|converge> [config…] [--dry-run]"
  printf '%s\n' "                                  launch a new run (--dry-run previews it)"
  printf '%s\n' "  almanac hub --resume <run-id>    re-launch a finished run with the same config"
  printf '%s\n' "  almanac hub --clone  <run-id>    start the launcher pre-filled from a finished run"
  printf '%s\n' "  almanac hub --stats              summarise finished runs (runs + success rate per provider/model)"
}

# Launch (or, with dry_run=1, preview) a composed new run. env_raw/argv_raw are
# the newline-token streams from almanac_loop_new_run_env / almanac_loop_new_run_argv.
# Dry-run prints the resolved `ENV… almanac <argv>` command and returns — the
# non-interactive, scripts-safe preview tests and the gum confirm both use.
# Otherwise it exports the env lines and execs the launcher, handing over the
# terminal to the new run.
almanac_hub_launch_new() {
  local dry_run="$1" env_raw="$2" argv_raw="$3"
  local line display="" argv=()

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    argv+=("$line")
  done <<< "$argv_raw"
  [ "${#argv[@]}" -gt 0 ] || _die "Nothing to launch"

  if [ "$dry_run" = "1" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      display+="$line "
    done <<< "$env_raw"
    display+="almanac"
    for line in "${argv[@]}"; do
      display+=" $line"
    done
    printf '%s\n' "$display"
    return 0
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    export "$line"
  done <<< "$env_raw"

  exec bash "$ALMANAC_HOME/bin/almanac" "${argv[@]}"
}

# Interactive New-run flow: pick the loop type, then hand off to the shared
# almanac launcher (almanac_loop_launch), which gathers that loop's config
# through the same gum seam, summarises, confirms, and execs the runner. No
# config logic lives here — one launcher, one UX, shared with `almanac ralph`
# and `almanac harden`. On confirm the launcher execs (hands over the terminal);
# if the operator cancels first it returns here and the menu loop continues.
almanac_hub_new_run() {
  local type
  type="$(almanac_loop_ui_choose "New run — pick a loop" ralph harden converge)" || return 0
  almanac_loop_launch "$type"
}

almanac_hub_menu() {
  local root="$1"
  local running line choice run_id action directive
  local options

  while :; do
    almanac_loop_ui_clear
    almanac_loop_hub_overview "$root"

    running="$(almanac_loop_hub_render "$root" running 2>/dev/null || true)"

    # Top-level menu: New run is always available (even with an empty registry);
    # each running loop is an actionable row carrying its "[id]"; quit exits.
    options=("+ New run")
    if [ -n "$running" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        options+=("$line")
      done <<< "$running"
    fi
    options+=("quit")

    choice="$(almanac_loop_ui_choose "Almanac hub" "${options[@]}")" || return 0
    case "$choice" in
      "+ New run") almanac_hub_new_run "$root"; continue ;;
      quit) return 0 ;;
    esac
    run_id="$(printf '%s\n' "$choice" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')"
    [ -n "$run_id" ] || continue

    action="$(almanac_loop_ui_choose "Run $run_id" watch stop steer back)" || continue
    case "$action" in
      watch)
        almanac_loop_run_watch "$root" "$run_id" follow || _warn "No status for run: $run_id"
        ;;
      stop)
        if almanac_loop_ui_confirm "Stop $run_id?"; then
          if almanac_loop_run_stop "$root" "$run_id"; then
            _success "Stop requested for $run_id"
          else
            _warn "Could not stop $run_id"
          fi
        fi
        ;;
      steer)
        directive="$(almanac_loop_ui_input "Steer $run_id")" || continue
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

# Re-build a finished run's launch command from its registry blob and either
# launch it auto-confirmed (resume) or hand it to the launcher for review/edit
# (clone). The composer + exec path is the same one `--new` uses, so a resumed/
# cloned run goes through every layer a fresh launch does. Config fields come
# from the per-run status blob (provider/model/effort/iterations/oversee for
# ralph; target/lenses/provider/model/effort/rounds for harden); ralph's mode is
# inferred from whether `iterations` was recorded (afk) or not (once).
almanac_hub_resume_or_clone() {
  local mode="$1" run_id="$2"
  local status_file run_type target provider model effort iterations oversee lenses rounds
  local goal exec_cmd oversee_every
  local -a opts
  local argv env_raw prd

  status_file="$(almanac_loop_run_status_file "$ROOT" "$run_id")"
  [ -f "$status_file" ] || _die "Unknown run: $run_id"
  run_type="$(almanac_loop_status_field "$status_file" type || true)"
  target="$(almanac_loop_status_field "$status_file" target || true)"
  provider="$(almanac_loop_status_field "$status_file" provider || true)"
  model="$(almanac_loop_status_field "$status_file" model || true)"
  effort="$(almanac_loop_status_field "$status_file" effort || true)"
  iterations="$(almanac_loop_status_field "$status_file" iterations || true)"
  oversee="$(almanac_loop_status_field "$status_file" oversee || true)"
  lenses="$(almanac_loop_status_field "$status_file" lenses || true)"
  rounds="$(almanac_loop_status_field "$status_file" rounds || true)"
  goal="$(almanac_loop_status_field "$status_file" goal || true)"
  exec_cmd="$(almanac_loop_status_field "$status_file" exec || true)"
  oversee_every="$(almanac_loop_status_field "$status_file" oversee_every || true)"

  case "$run_type" in
    ralph)
      prd="$(basename "$(dirname "$target")")"
      opts=("prd=$prd")
      if [ -n "$iterations" ]; then opts+=("mode=afk" "iterations=$iterations"); else opts+=("mode=once"); fi
      [ -n "$provider" ] && opts+=("provider=$provider")
      [ -n "$model" ]    && opts+=("model=$model")
      [ -n "$effort" ]   && opts+=("effort=$effort")
      [ "$oversee" = "off" ] && opts+=("oversee=off")
      ;;
    harden)
      [ -n "$target" ]   && opts+=("target=$target")
      [ -n "$lenses" ]   && opts+=("lenses=$lenses")
      [ -n "$provider" ] && opts+=("provider=$provider")
      [ -n "$model" ]    && opts+=("model=$model")
      [ -n "$effort" ]   && opts+=("effort=$effort")
      [ -n "$rounds" ]   && opts+=("rounds=$rounds")
      ;;
    converge)
      [ -n "$goal" ]          && opts+=("goal=$goal")
      [ -n "$exec_cmd" ]      && opts+=("exec=$exec_cmd")
      [ -n "$rounds" ]        && opts+=("rounds=$rounds")
      [ -n "$provider" ]      && opts+=("provider=$provider")
      [ -n "$model" ]         && opts+=("model=$model")
      [ -n "$effort" ]        && opts+=("effort=$effort")
      [ "$oversee" = "off" ]  && opts+=("oversee=off")
      [ -n "$oversee_every" ] && opts+=("oversee_every=$oversee_every")
      ;;
    *) _die "Cannot $mode run of unknown type: $run_type" ;;
  esac

  argv="$(almanac_loop_new_run_argv "$run_type" "${opts[@]}")" \
    || _die "Could not compose $mode for $run_id"
  env_raw="$(almanac_loop_new_run_env "$run_type" "${opts[@]}")" || env_raw=""

  # resume auto-confirms launcher-backed runs via --yes; harden + converge argv
  # is already the direct runner (`almanac harden|converge …`) and rejects the
  # launcher-only --yes flag. clone leaves confirm in place where a launcher is
  # used.
  if [ "$mode" = "resume" ] && [ "$run_type" != "harden" ] && [ "$run_type" != "converge" ]; then
    argv="${argv}"$'\n''--yes'
  fi
  almanac_hub_launch_new 0 "$env_raw" "$argv"
}

ACTION=""
ACTION_ID=""
STEER_DIRECTIVE=""
ACTION_TYPE=""
NEW_DRY_RUN=0
NEW_OPTS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      hub_usage
      exit 0
      ;;
    --new)
      shift
      [ "$#" -gt 0 ] || _die "Missing run type for --new (ralph|harden|converge)"
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
      1) _die "Unknown run type: $ACTION_TYPE (use ralph or harden)" ;;
      2) _die "Missing required config for $ACTION_TYPE (ralph needs --prd, harden needs --target)" ;;
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
