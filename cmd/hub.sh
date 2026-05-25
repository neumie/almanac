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
#   almanac hub --new <ralph|harden> [config…] [--dry-run]
#                                      launch a new run (dry-run previews the command)

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-core.sh"

ROOT="$PWD"

hub_usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac hub                      open the hub (interactive on a TTY, overview otherwise)"
  printf '%s\n' "  almanac hub --watch <run-id>     tail a run's live status"
  printf '%s\n' "  almanac hub --stop  <run-id>     signal a run to stop"
  printf '%s\n' "  almanac hub --steer <run-id> …   queue a steer directive for the next round"
  printf '%s\n' "  almanac hub --new <ralph|harden> [config…] [--dry-run]"
  printf '%s\n' "                                  launch a new run (--dry-run previews it)"
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

# Interactive gum menu: pick a running loop, then watch / stop / steer it. Only
# entered on a TTY with gum (the caller guards), so the gum calls always resolve.
# Loops until the operator quits or no running loops remain. Each running row ends
# with "[id]"; the chosen line is mapped back to the run id to act on.
# List the repo's PRDs (docs/plans/<name>/prd.md) and let the operator pick one
# via gum. Prints the chosen PRD name; returns 1 when there are none to choose.
almanac_hub_pick_prd() {
  local dir name prds=""
  for dir in docs/plans/*/; do
    [ -f "${dir}prd.md" ] || continue
    name="$(basename "$dir")"
    prds="${prds}${name}"$'\n'
  done
  [ -n "$prds" ] || { _warn "No PRDs found in docs/plans/"; return 1; }
  printf '%s' "$prds" | gum choose --header "Select PRD"
}

# Interactive New-run flow (gum): pick ralph or harden, gather config via gum
# prompts, preview, then launch. Composes the same argv/env the `--new` seam does,
# so the launch path is identical interactive vs. scripted. TTY+gum only (the
# caller guards); returns to the hub menu if the operator cancels.
almanac_hub_new_run() {
  local type opts=() prd mode iters provider model effort lenses rounds target env_raw argv_raw

  type="$(printf 'ralph\nharden\n' | gum choose --header "New run — pick a loop")" || return 0
  case "$type" in
    ralph)
      prd="$(almanac_hub_pick_prd)" || return 0
      [ -n "$prd" ] || return 0
      opts+=("prd=$prd")
      mode="$(printf 'afk\nonce\n' | gum choose --header "Mode")" || return 0
      opts+=("mode=$mode")
      provider="$(printf 'codex\nclaude\n' | gum choose --header "Provider")" || return 0
      opts+=("provider=$provider")
      model="$(gum input --header "Model (blank = provider default)" --placeholder "default")" || return 0
      [ -n "$model" ] && opts+=("model=$model")
      effort="$(gum input --header "Thinking effort (blank = default)" --placeholder "default")" || return 0
      [ -n "$effort" ] && opts+=("effort=$effort")
      if [ "$mode" = "afk" ]; then
        iters="$(gum input --header "Iterations" --value "10")" || return 0
        [ -n "$iters" ] && opts+=("iterations=$iters")
        gum confirm "Run the overseer?" || opts+=("oversee=off")
      fi
      ;;
    harden)
      target="$(gum input --header "Target (file / dir / PR)" --placeholder "src/app.js")" || return 0
      [ -n "$target" ] || { _warn "No target given"; return 0; }
      opts+=("target=$target")
      lenses="$(gum input --header "Lenses (blank = default set)" --placeholder "correctness security perf")" || return 0
      [ -n "$lenses" ] && opts+=("lenses=$lenses")
      provider="$(printf 'claude\ncodex\n' | gum choose --header "Reviewer provider")" || return 0
      opts+=("provider=$provider")
      rounds="$(gum input --header "Round budget (blank = default)" --placeholder "5")" || return 0
      [ -n "$rounds" ] && opts+=("rounds=$rounds")
      ;;
    *) return 0 ;;
  esac

  argv_raw="$(almanac_loop_new_run_argv "$type" "${opts[@]}")" || { _warn "Could not compose the run"; return 0; }
  env_raw="$(almanac_loop_new_run_env "$type" "${opts[@]}")" || env_raw=""

  printf '%s\n' "Will launch:"
  almanac_hub_launch_new 1 "$env_raw" "$argv_raw"
  if gum confirm "Launch this run?"; then
    almanac_hub_launch_new 0 "$env_raw" "$argv_raw"
  fi
}

almanac_hub_menu() {
  local root="$1"
  local running menu choice run_id action directive

  while :; do
    almanac_loop_ui_clear
    almanac_loop_hub_overview "$root"

    running="$(almanac_loop_hub_render "$root" running 2>/dev/null || true)"

    # Top-level menu: New run is always available (even with an empty registry);
    # each running loop is an actionable row carrying its "[id]"; quit exits.
    menu="+ New run"
    [ -n "$running" ] && menu="$menu"$'\n'"$running"
    menu="$menu"$'\n'"quit"

    choice="$(printf '%s\n' "$menu" | gum choose --header "Almanac hub")" || return 0
    case "$choice" in
      "+ New run") almanac_hub_new_run "$root"; continue ;;
      quit) return 0 ;;
    esac
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
      [ "$#" -gt 0 ] || _die "Missing run type for --new (ralph|harden)"
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
esac

# No explicit action: bare hub. On a TTY with gum, open the interactive menu —
# always, even with an empty registry, so New run is reachable with no prior runs.
# Otherwise render the read-only overview (the scripts-safe path tests and pipes
# get, and the gum-absent fallback).
if [ -t 0 ] && [ -t 1 ] && almanac_loop_ui_has_gum; then
  almanac_hub_menu "$ROOT"
else
  almanac_loop_hub_overview "$ROOT"
fi
