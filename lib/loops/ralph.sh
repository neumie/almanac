#!/usr/bin/env bash
# lib/loops/ralph.sh — the ralph loop adapter.
#
# One file owns everything the engine needs to know about how to launch and
# control the ralph loop. Auto-discovered by lib/loops.sh from lib/loops/*.sh.
#
# Contract (called as almanac_loop_ralph_<verb>):
#   launch        — interactive config + exec. Used by lib/loop-launcher.sh's
#                   dispatch (no central case-statement on loop type).
#   launch_usage  — the --help text printed for this loop's launcher.
#   exec_argv     — populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                   for a given mode/prd/iterations. The ralph runner path lives
#                   HERE (not hard-coded in the launcher).
#
# Control contract (signal_file) inherits the default `.ralph-stop` / `.ralph-steer`
# convention from lib/loops.sh — no adapter override needed.
#
# The launch verb uses helpers defined in lib/loop-launcher.sh
# (_almanac_launch_need_provider/_choice/_positive_int, almanac_loop_launch_summary)
# and the shared UI / provider seams. The launcher sources those before
# dispatching, so the adapter need not source them itself.

# Build ralph's runner exec command into _ALMANAC_LOOP_ARGV (the launcher execs
# it). MODE selects the runner: `once` runs a single iteration (once.sh PRD),
# `afk` runs autonomously (afk.sh PRD ITERATIONS). The ralph runner scripts live
# under the ralph-loop skill — this adapter is the single place that path is
# named, so the launcher no longer hard-codes …/ralph-loop/scripts/…. Returns 2
# for an unknown mode. Requires $ALMANAC_HOME (set by every entry point).
almanac_loop_ralph_exec_argv() {
  local mode="$1" prd="$2" iterations="${3:-}"
  local scripts="$ALMANAC_HOME/skills/loop/ralph-loop/scripts"
  case "$mode" in
    once) _ALMANAC_LOOP_ARGV=(bash "$scripts/once.sh" "$prd") ;;
    afk)  _ALMANAC_LOOP_ARGV=(bash "$scripts/afk.sh" "$prd" "$iterations") ;;
    *) return 2 ;;
  esac
  return 0
}

# Interactive config + exec for the ralph loop. Parses native flags, prompts for
# any missing field via the gum-or-plain UI seam, exports the role-config env,
# and execs the runner via the exec_argv verb. Called by lib/loop-launcher.sh's
# adapter dispatch — no central code branches on loop type.
almanac_loop_ralph_launch() {
  local prd="" mode="" provider="" model="" effort="" iterations="" no_oversee="" yes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --prd)        shift; prd="${1:-}";        [ -n "$prd" ] || _die "--prd requires a value" ;;
      --mode)       shift; mode="${1:-}";       [ -n "$mode" ] || _die "--mode requires a value" ;;
      --provider)   shift; provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"; [ -n "$provider" ] || _die "--provider requires a value" ;;
      --model)      shift; model="${1:-}";      [ -n "$model" ] || _die "--model requires a value" ;;
      --effort|--thinking) shift; effort="${1:-}"; [ -n "$effort" ] || _die "$1 requires a value" ;;
      --iterations) shift; iterations="${1:-}"; [ -n "$iterations" ] || _die "--iterations requires a value" ;;
      --no-oversee) no_oversee=1 ;;
      --yes|-y) yes=1 ;;
      --help|-h) almanac_loop_ralph_launch_usage; return 0 ;;
      *) _die "Unknown ralph launch option: $1" ;;
    esac
    shift
  done

  [ -d docs/plans ] || _die "docs/plans/ not found. Run from the project root."

  # PRD
  if [ -z "$prd" ]; then
    local prds=() dir
    for dir in docs/plans/*/; do
      [ -f "${dir}prd.md" ] && prds+=("$(basename "$dir")")
    done
    [ "${#prds[@]}" -gt 0 ] || _die "No PRDs in docs/plans/. Run /prd-create first."
    if [ "${#prds[@]}" -eq 1 ]; then prd="${prds[0]}"; else prd="$(almanac_loop_ui_choose "Select PRD" "${prds[@]}")" || return 1; fi
  fi
  [ -f "docs/plans/${prd}/prd.md" ]    || _die "docs/plans/${prd}/prd.md not found."
  [ -f "docs/plans/${prd}/prompt.md" ] || _die "docs/plans/${prd}/prompt.md not found. Run /ralph-loop ${prd} first."

  # Mode
  [ -n "$mode" ] || mode="$(almanac_loop_ui_choose "Mode" once afk)" || return 1
  case "$mode" in once|afk) ;; *) _die "--mode must be once or afk" ;; esac

  # Provider / model / effort
  provider="$(_almanac_launch_need_provider provider "$provider")" || return 1
  almanac_provider_known "$provider" || _die "--provider must be a supported provider (e.g. codex or claude)"
  almanac_provider_available "$provider" || _die "Provider '$provider' selected but its CLI is not on PATH."
  model="$(_almanac_launch_need_choice "Model" "$model" $(almanac_provider_models "$provider"))" || return 1
  effort="$(_almanac_launch_need_choice "Thinking effort" "$effort" $(almanac_provider_efforts "$provider"))" || return 1

  # Iterations + overseer (afk only)
  if [ "$mode" = "afk" ]; then
    iterations="$(_almanac_launch_need_positive_int "Iterations" "$iterations" "10")" || return 1
    if [ -z "$no_oversee" ]; then
      almanac_loop_ui_confirm "Run the overseer?" || no_oversee=1
    fi
  fi

  # Summary + confirm
  almanac_loop_launch_summary "ralph" \
    "PRD:$prd" "Mode:$mode" "Provider:$provider" \
    "Model:${model:-provider default}" "Thinking:${effort:-provider default}" \
    $([ "$mode" = "afk" ] && printf '%s\n%s' "Iterations:$iterations" "Overseer:$([ -n "$no_oversee" ] && echo off || echo on)")
  [ -n "$yes" ] || almanac_loop_ui_confirm "Launch this run?" || { _info "Cancelled."; return 0; }

  # Export role config + exec the runner (no re-launch through `almanac ralph`).
  export RALPH_PROVIDER="$provider"
  [ -n "$model" ]  && export RALPH_MODEL="$model"   || unset RALPH_MODEL
  [ -n "$effort" ] && export RALPH_EFFORT="$effort" || unset RALPH_EFFORT
  [ -n "$no_oversee" ] && export RALPH_NO_OVERSEE=1

  # Exec the runner via the ralph adapter (no hard-coded …/ralph-loop/scripts/…
  # path lives here any more — the adapter owns it).
  almanac_loop_adapter_call ralph exec_argv "$mode" "$prd" "$iterations" \
    || _die "ralph adapter could not build a runner for mode: $mode"
  exec "${_ALMANAC_LOOP_ARGV[@]}"
}

# --help text for `almanac ralph` / `almanac_loop_launch ralph`. Stays inside
# the adapter so adding a loop is a one-file change.
almanac_loop_ralph_launch_usage() {
  cat >&2 <<'EOF'
Usage: almanac ralph [options]   (also: bash ralph.sh [options])
  --prd <name>        PRD under docs/plans/<name>/
  --mode <once|afk>   one iteration, or autonomous
  --provider <p>      codex | claude
  --model <m>         model name ("default" = provider default)
  --effort <l>        thinking level ("default" = provider default)
  --iterations <n>    afk iteration count
  --no-oversee        disable the afk overseer
Any option not given is prompted interactively.
EOF
}
