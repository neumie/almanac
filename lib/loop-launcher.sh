#!/usr/bin/env bash
# loop-launcher.sh — the single almanac launcher (ralph + harden).
#
# almanac_loop_launch <type> [native flags…] interactively configures and starts
# a loop run. It is loop-agnostic: one launcher for every consumer — `almanac
# ralph`, `almanac harden`, the hub's New-run flow, and the ralph skill launcher
# all route here, so the config UX is identical everywhere (the PRD's "almanac
# launcher, not per-loop reimplementations").
#
# Each type parses its own native flags; any field a flag did not supply is asked
# once, through the shared gum-or-plain seam (almanac_loop_ui_*). Numeric fields
# validate and RE-PROMPT on a TTY rather than hard-dying (so a stray keystroke is
# a retry, not a crash); a bad value passed as a flag still errors. After a
# summary + confirm it execs the underlying runner — it never reimplements the
# run, only the configuration.
#
# Requires lib/core.sh (_die/_info/_success), sourced by every entry point before
# this file. The gum-or-plain UI seam (almanac_loop_ui_*) lives in lib/ui.sh and
# is pulled in directly below, so the launcher's dependency on it is explicit.

# The launcher drives the whole config UX through the gum-or-plain seam
# (choose/input/confirm/render). Source it directly and idempotently so the
# dependency is the launcher's own, not borrowed from whatever sourced this file.
if ! declare -F almanac_loop_ui_choose >/dev/null 2>&1; then
  __loop_launcher_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/ui.sh
  source "$__loop_launcher_dir/ui.sh"
  unset __loop_launcher_dir
fi

# Provider knowledge (availability, the model/effort menus, default-selection,
# the provider list) lives in the provider-adapter seam (lib/agent.sh →
# almanac_provider_*). The launcher consumes it rather than branching on provider
# name. Source it directly and idempotently so the dependency is the launcher's
# own, not borrowed from whatever sourced this file.
if ! declare -F almanac_provider_default >/dev/null 2>&1; then
  __loop_launcher_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/agent.sh
  source "$__loop_launcher_dir/agent.sh"
  unset __loop_launcher_dir
fi

# --- field collectors ---------------------------------------------------------

# Pick a provider into the named-by-$1 variable if it is empty. Lists only
# installed providers (discovered via the seam); dies if none.
_almanac_launch_need_provider() {
  local var="$1" current="${2:-}" providers=() p chosen
  if [ -n "$current" ]; then printf '%s\n' "$current"; return 0; fi
  for p in $(almanac_provider_list); do
    almanac_provider_available "$p" && providers+=("$p")
  done
  [ "${#providers[@]}" -gt 0 ] || _die "No supported provider found. Install Codex or Claude Code."
  if [ "${#providers[@]}" -eq 1 ]; then printf '%s\n' "${providers[0]}"; return 0; fi
  chosen="$(almanac_loop_ui_choose "Provider" "${providers[@]}")" || return 1
  printf '%s\n' "$chosen"
}

# Resolve a model/effort value: if empty, show the provider menu; map "default"
# to empty and "custom" to a free-text prompt. Echoes the resolved value.
_almanac_launch_need_choice() {
  local header="$1" current="$2" picked
  shift 2
  if [ -n "$current" ]; then
    [ "$current" = "default" ] && current=""
    printf '%s\n' "$current"; return 0
  fi
  picked="$(almanac_loop_ui_choose "$header" "$@")" || return 1
  if [ "$picked" = "custom" ]; then
    picked="$(almanac_loop_ui_input "$header (custom)")" || return 1
  fi
  [ "$picked" = "default" ] && picked=""
  printf '%s\n' "$picked"
}

# Resolve a positive integer. A preset (flag) value is validated once and dies on
# failure; an interactive value re-prompts until valid. Echoes the integer.
_almanac_launch_need_positive_int() {
  local header="$1" current="$2" default="${3:-}" reply
  if [ -n "$current" ]; then
    case "$current" in ''|*[!0-9]*) _die "$header must be a positive integer (got: $current)";; esac
    [ "$current" -gt 0 ] || _die "$header must be a positive integer (got: $current)"
    printf '%s\n' "$current"; return 0
  fi
  while :; do
    reply="$(almanac_loop_ui_input "$header" "$default")" || return 1
    case "$reply" in ''|*[!0-9]*) _warn "Enter a positive integer." >&2; continue;; esac
    [ "$reply" -gt 0 ] && { printf '%s\n' "$reply"; return 0; }
    _warn "Enter a positive integer." >&2
  done
}

# --- ralph ---------------------------------------------------------------------

_almanac_launch_ralph() {
  local prd="" mode="" provider="" model="" effort="" iterations="" no_oversee=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --prd)        shift; prd="${1:-}";        [ -n "$prd" ] || _die "--prd requires a value" ;;
      --mode)       shift; mode="${1:-}";       [ -n "$mode" ] || _die "--mode requires a value" ;;
      --provider)   shift; provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"; [ -n "$provider" ] || _die "--provider requires a value" ;;
      --model)      shift; model="${1:-}";      [ -n "$model" ] || _die "--model requires a value" ;;
      --effort|--thinking) shift; effort="${1:-}"; [ -n "$effort" ] || _die "$1 requires a value" ;;
      --iterations) shift; iterations="${1:-}"; [ -n "$iterations" ] || _die "--iterations requires a value" ;;
      --no-oversee) no_oversee=1 ;;
      --help|-h) almanac_loop_launch_usage ralph; return 0 ;;
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
  almanac_loop_ui_confirm "Launch this run?" || { _info "Cancelled."; return 0; }

  # Export role config + exec the runner (no re-launch through `almanac ralph`).
  export RALPH_PROVIDER="$provider"
  [ -n "$model" ]  && export RALPH_MODEL="$model"   || unset RALPH_MODEL
  [ -n "$effort" ] && export RALPH_EFFORT="$effort" || unset RALPH_EFFORT
  [ -n "$no_oversee" ] && export RALPH_NO_OVERSEE=1

  local scripts="$ALMANAC_HOME/skills/loop/ralph-loop/scripts"
  case "$mode" in
    once) exec bash "$scripts/once.sh" "$prd" ;;
    afk)  exec bash "$scripts/afk.sh" "$prd" "$iterations" ;;
  esac
}

# --- harden --------------------------------------------------------------------

_almanac_launch_harden() {
  local target="" lenses="" provider="" model="" effort="" rounds=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lenses)   shift; lenses="${1:-}";   [ -n "$lenses" ] || _die "--lenses requires a value" ;;
      --provider) shift; provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"; [ -n "$provider" ] || _die "--provider requires a value" ;;
      --model)    shift; model="${1:-}";    [ -n "$model" ] || _die "--model requires a value" ;;
      --effort|--thinking) shift; effort="${1:-}"; [ -n "$effort" ] || _die "$1 requires a value" ;;
      --rounds)   shift; rounds="${1:-}";   [ -n "$rounds" ] || _die "--rounds requires a value" ;;
      --help|-h) almanac_loop_launch_usage harden; return 0 ;;
      -*) _die "Unknown harden launch option: $1" ;;
      *)  [ -z "$target" ] && target="$1" || _die "Unexpected harden argument: $1" ;;
    esac
    shift
  done

  [ -n "$target" ] || target="$(almanac_loop_ui_input "Target (file / dir / PR)")" || return 1
  [ -n "$target" ] || _die "A harden target is required."

  lenses="$(test -n "$lenses" && printf '%s' "$lenses" || almanac_loop_ui_input "Lenses (blank = default set)")" || return 1
  provider="$(_almanac_launch_need_provider provider "$provider")" || return 1
  almanac_provider_known "$provider" || _die "--provider must be a supported provider (e.g. codex or claude)"
  almanac_provider_available "$provider" || _die "Provider '$provider' selected but its CLI is not on PATH."
  model="$(_almanac_launch_need_choice "Reviewer model" "$model" $(almanac_provider_models "$provider"))" || return 1
  effort="$(_almanac_launch_need_choice "Reviewer thinking effort" "$effort" $(almanac_provider_efforts "$provider"))" || return 1
  [ -n "$rounds" ] || rounds="$(almanac_loop_ui_input "Round budget (blank = default)")" || return 1
  [ -z "$rounds" ] || rounds="$(_almanac_launch_need_positive_int "Round budget" "$rounds")" || return 1

  almanac_loop_launch_summary "harden" \
    "Target:$target" "Lenses:${lenses:-default set}" "Provider:$provider" \
    "Model:${model:-provider default}" "Thinking:${effort:-provider default}" \
    "Rounds:${rounds:-default budget}"
  almanac_loop_ui_confirm "Launch this run?" || { _info "Cancelled."; return 0; }

  [ -n "$lenses" ]   && export HARDEN_LENSES="$lenses"
  export HARDEN_PROVIDER="$provider"
  [ -n "$model" ]    && export HARDEN_MODEL="$model"   || unset HARDEN_MODEL
  [ -n "$effort" ]   && export HARDEN_EFFORT="$effort" || unset HARDEN_EFFORT

  local argv=(harden "$target" --loop)
  [ -n "$rounds" ] && argv+=(--rounds "$rounds")
  exec bash "$ALMANAC_HOME/bin/almanac" "${argv[@]}"
}

# --- summary + dispatch --------------------------------------------------------

# Render a "LABEL:value" config summary as a gum-styled (or plain) panel. Each
# remaining arg is one "Field:value" line. Presentation only.
almanac_loop_launch_summary() {
  local type="$1"; shift
  local line
  {
    printf '%s\n' "$(printf '%s' "$type" | tr '[:lower:]' '[:upper:]') run"
    printf '%s\n' "──────────────────"
    for line in "$@"; do
      printf '  %-11s %s\n' "${line%%:*}" "${line#*:}"
    done
  } | almanac_loop_ui_render >&2
}

# Per-type usage, printed for --help. Goes to stderr (stdout stays capture-clean).
almanac_loop_launch_usage() {
  case "$1" in
    ralph) cat >&2 <<'EOF'
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
      ;;
    harden) cat >&2 <<'EOF'
Usage (loop launch): <target> [options]
  <target>            file / dir / PR to harden
  --lenses <list>     reviewer lenses (blank = default set)
  --provider <p>      codex | claude
  --model <m>         reviewer model
  --effort <l>        reviewer thinking level
  --rounds <n>        round budget
Any option not given is prompted interactively.
EOF
      ;;
  esac
}

# Public entry: configure and launch a run of TYPE (ralph|harden). Remaining args
# are that type's native flags; missing fields are prompted. Execs the runner.
almanac_loop_launch() {
  local type="${1:-}"; shift || true
  case "$type" in
    ralph)  _almanac_launch_ralph "$@" ;;
    harden) _almanac_launch_harden "$@" ;;
    "")     _die "Usage: almanac_loop_launch <ralph|harden> [options]" ;;
    *)      _die "Unknown loop type: $type (use ralph or harden)" ;;
  esac
}
