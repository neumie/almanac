#!/usr/bin/env bash
# loop-launcher.sh — the single almanac launcher (ralph + harden + converge).
#
# almanac_loop_launch <type> [native flags…] interactively configures and starts
# a loop run. It is loop-agnostic: one launcher for every consumer — `almanac
# ralph`, `almanac harden`, the hub's New-run flow, and the ralph skill launcher
# all route here, so the config UX is identical everywhere (the PRD's "almanac
# launcher, not per-loop reimplementations").
#
# Each loop's flag parsing, prompts, env-export, and runner exec live in its
# adapter (lib/loops/<name>.sh) as the `launch` verb, and its --help text as the
# `launch_usage` verb. The launcher dispatches via the loop-adapter seam — no
# central case-statement branches on loop type, so adding a 4th loop is a
# single new file in lib/loops/.
#
# The shared bits — field collectors (provider / choice / positive-int) and the
# summary panel — stay here because every adapter uses them identically. They
# are sourced once at launcher boot, so any adapter dispatched through
# `almanac_loop_launch` finds them in scope.
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

# The loop-adapter seam (almanac_loop_adapter_*) lives in lib/loops.sh. The
# launcher dispatches the `launch` verb through it (each loop adapter owns its
# own config UI + exec). Source it directly and idempotently so the dependency
# is the launcher's own, not borrowed from whatever sourced this file.
if ! declare -F almanac_loop_adapter_call >/dev/null 2>&1; then
  __loop_launcher_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/loops.sh
  source "$__loop_launcher_dir/loops.sh"
  unset __loop_launcher_dir
fi

# --- field collectors ---------------------------------------------------------
#
# Used by every loop adapter's `launch` verb (lib/loops/<name>.sh::almanac_loop_<name>_launch).
# The underscore prefix signals "private to the launching subsystem (this file +
# adapter launch verbs)" — not for callers outside that path.

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
# Dispatched to the loop adapter's `launch_usage` verb — no central case-statement
# on loop type. Adding a new loop puts its usage text in lib/loops/<name>.sh
# alongside its launch verb. A missing adapter or missing verb is a no-op so
# `--help` for an unknown loop fails through to the launcher's usage error
# rather than crashing.
almanac_loop_launch_usage() {
  local type="${1:-}"
  [ -n "$type" ] || return 0
  almanac_loop_adapter_known "$type" || return 0
  local fn
  fn="almanac_loop_$(almanac_loop_adapter_key "$type")_launch_usage"
  declare -F "$fn" >/dev/null 2>&1 && "$fn"
}

# Public entry: configure and launch a run of TYPE (ralph|harden|converge|…).
# Remaining args are that type's native flags; missing fields are prompted by
# the adapter's `launch` verb, which also execs the runner. The launcher does
# not enumerate loop types — discovery is via the loop-adapter seam, so adding
# a new loop is a single new file in lib/loops/. We resolve the launch verb's
# function name and invoke it directly (rather than going through
# almanac_loop_adapter_call) so a missing verb is a hard die — the launch
# function itself may legitimately exit non-zero (user cancelled / validation
# error), and adapter_call's "verb missing" rc=2 would collide with those.
almanac_loop_launch() {
  local type="${1:-}"; shift || true
  [ -n "$type" ] || _die "Usage: almanac_loop_launch <loop> [options] (loops: $(almanac_loop_adapter_list | tr '\n' ' '))"
  almanac_loop_adapter_known "$type" || _die "Unknown loop type: $type (loops: $(almanac_loop_adapter_list | tr '\n' ' '))"
  local fn
  fn="almanac_loop_$(almanac_loop_adapter_key "$type")_launch"
  declare -F "$fn" >/dev/null 2>&1 || _die "Loop adapter '$type' does not implement the launch verb"
  "$fn" "$@"
}
