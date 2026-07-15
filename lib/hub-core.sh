#!/usr/bin/env bash
# hub-core.sh — the hub's composable logic, split out from cmd/hub.sh so it is
# unit-testable in isolation (cmd/hub.sh is a self-executing parse+dispatch
# shim). Mirrors the converge-core split: the cmd file owns argv
# and terminal handover; this file owns the loop-listing, new-run composer, the
# interactive menu, and the resume/clone status inverter.
#
# Dependencies (sourced idempotently): lib/core.sh (_die/_info/_success/_warn +
# the _almanac_source_sibling helper used below), lib/run.sh (run registry +
# status reads + new_run composers), lib/ui.sh (the gum/plain UI seam),
# lib/loop-launcher.sh (almanac_loop_launch). core.sh loads first via the literal
# snippet so the sibling helper is in scope.
if ! declare -F _die >/dev/null 2>&1; then
  __hub_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__hub_dir/core.sh"
  unset __hub_dir
fi

_almanac_source_sibling run.sh          almanac_loop_run_status_file
_almanac_source_sibling ui.sh           almanac_loop_ui_choose
_almanac_source_sibling loop-launcher.sh almanac_loop_launch

# Pipe-joined list of known loop names (e.g. "loop|converge"), for usage
# strings — discovered from the loop-adapter seam, never hard-coded.
almanac_hub_loop_names_inline() {
  local names=() name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    names+=("$name")
  done < <(almanac_loop_adapter_list)
  (IFS='|'; printf '%s\n' "${names[*]}")
}

# One-line "what config this loop needs" hint, dispatched to the loop adapter's
# new_run_usage verb — used in hub --new error messages.
almanac_hub_new_run_config_hint() {
  local type="$1" hint
  hint="$(almanac_loop_adapter_call "$type" new_run_usage 2>/dev/null || true)"
  if [ -n "$hint" ]; then
    printf '%s\n' "$hint"
  else
    printf '%s\n' "check this loop adapter's required config"
  fi
}

almanac_hub_usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac hub                      open the hub (interactive on a TTY, overview otherwise)"
  printf '%s\n' "  almanac hub --watch <run-id>     tail a run's live status"
  printf '%s\n' "  almanac hub --stop  <run-id>     signal a run to stop"
  printf '%s\n' "  almanac hub --steer <run-id> …   queue a steer directive for the next round"
  printf '%s\n' "  almanac hub --new <$(almanac_hub_loop_names_inline)> [config…] [--dry-run]"
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
# config logic lives here — one launcher, one UX, shared with direct loop CLIs.
# On confirm the launcher execs (hands over the terminal);
# if the operator cancels first it returns here and the menu loop continues.
almanac_hub_new_run() {
  local type loop loops=()
  while IFS= read -r loop; do
    [ -n "$loop" ] || continue
    loops+=("$loop")
  done < <(almanac_loop_adapter_list)
  [ "${#loops[@]}" -gt 0 ] || _die "No loop adapters found"
  type="$(almanac_loop_ui_choose "New run — pick a loop" "${loops[@]}")" || return 0
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
# cloned run goes through every layer a fresh launch does. The hub is fully
# loop-agnostic: the adapter's `status_to_opts` verb inverts its own status
# schema into key=val pairs the new_run composers consume; the `launch_backed`
# verb signals whether `--yes` (a launcher-only flag) is safe to append on
# resume — the direct-runner loop (converge) leaves it undefined and never
# gets the suffix. Reads $ROOT from the caller (cmd/hub.sh) for the run lookup.
almanac_hub_resume_or_clone() {
  local mode="$1" run_id="$2"
  local status_file run_type argv env_raw opts_raw
  local -a opts=()
  local line

  status_file="$(almanac_loop_run_status_file "$ROOT" "$run_id")"
  [ -f "$status_file" ] || _die "Unknown run: $run_id"
  run_type="$(almanac_loop_status_field "$status_file" type || true)"
  [ -n "$run_type" ] || _die "Run '$run_id' has no recorded type"

  opts_raw="$(almanac_loop_adapter_call "$run_type" status_to_opts "$status_file")" \
    || _die "Cannot $mode run of unknown type: $run_type"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opts+=("$line")
  done <<< "$opts_raw"

  argv="$(almanac_loop_new_run_argv "$run_type" "${opts[@]}")" \
    || _die "Could not compose $mode for $run_id"
  env_raw="$(almanac_loop_new_run_env "$run_type" "${opts[@]}")" || env_raw=""

  # resume auto-confirms launcher-backed loops (loop) via --yes; loops whose
  # adapter doesn't implement `launch_backed` exec their direct runner and would
  # reject the launcher-only flag, so they get no suffix. clone leaves confirm
  # in place where a launcher is used.
  if [ "$mode" = "resume" ] && almanac_loop_adapter_call "$run_type" launch_backed 2>/dev/null; then
    argv="${argv}"$'\n''--yes'
  fi
  almanac_hub_launch_new 0 "$env_raw" "$argv"
}
