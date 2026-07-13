#!/usr/bin/env bash
# loop-launcher.sh — the single almanac launcher (loop + harden + converge).
#
# almanac_loop_launch <type> [native flags…] interactively configures and starts
# a loop run. It is loop-agnostic: one launcher for every consumer — `almanac
# loop`, `almanac harden`, the hub's New-run flow, and the loop skill launcher
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
# Requires lib/core.sh (_die/_info/_success + _almanac_source_sibling), sourced
# by every entry point before this file. The deps below are each declared
# explicitly through the sibling helper so the launcher's seam dependencies
# aren't borrowed from whatever sourced this file.
_almanac_source_sibling ui.sh    almanac_loop_ui_choose       # gum-or-plain UI seam
_almanac_source_sibling agent.sh almanac_provider_default     # provider-adapter seam (availability/default)
_almanac_source_sibling loops.sh almanac_loop_adapter_call    # loop-adapter dispatch

# --- field collectors ---------------------------------------------------------
#
# Used by every loop adapter's `launch` verb (lib/loops/<name>.sh::almanac_loop_<name>_launch).
# The underscore prefix signals "private to the launching subsystem (this file +
# adapter launch verbs)" — not for callers outside that path.

# Pick + validate a provider into the named-by-$1 variable if it is empty. Lists
# only installed providers (discovered via the seam); dies if none. The chosen
# provider is always run through the known + available checks so launch verbs
# don't repeat the 3-line dance — adding a 4th adapter can't forget either
# check, and the diagnostic for each is the single source of truth.
_almanac_launch_need_provider() {
  local var="$1" current="${2:-}" providers=() p chosen
  if [ -n "$current" ]; then
    chosen="$current"
  else
    for p in $(almanac_provider_list); do
      almanac_provider_available "$p" && providers+=("$p")
    done
    [ "${#providers[@]}" -gt 0 ] || _die "No supported provider found. Install Codex or Claude Code."
    if [ "${#providers[@]}" -eq 1 ]; then
      chosen="${providers[0]}"
    else
      chosen="$(almanac_loop_ui_choose "Provider" "${providers[@]}")" || return 1
    fi
  fi
  almanac_provider_known "$chosen"     || _die "--provider must be a supported provider (e.g. codex or claude)"
  almanac_provider_available "$chosen" || _die "Provider '$chosen' selected but its CLI is not on PATH."
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

# Resolve an OPTIONAL positive integer: a preset flag value is validated; an
# interactive value is prompted with the "(blank = default)" hint, and a blank
# reply is accepted (echoed as empty) so the downstream runner picks its own
# default. Sibling to _almanac_launch_need_positive_int (mandatory); used by
# harden + converge launches for `--rounds` — two adapters sharing the idiom
# verbatim, lifted here so the "(blank = default)" wording and validation
# semantics live in one place. Echoes the resolved value (or empty).
_almanac_launch_need_positive_int_optional() {
  local header="$1" current="$2"
  [ -n "$current" ] || current="$(almanac_loop_ui_input "$header (blank = default)")" || return 1
  [ -z "$current" ] || current="$(_almanac_launch_need_positive_int "$header" "$current")" || return 1
  printf '%s\n' "$current"
}

# Collect the (provider, model, effort) triple — the universal role-config dance
# every loop adapter's launch verb does. Resolves provider first (so the model
# and effort menus can be scoped to that provider's options), then provider-
# conditioned model and effort. Emits the three values one per line on stdout in
# that order; caller reads back with `read` triplet. Returns 1 on any cancel
# (the helper this dispatches to short-circuits, the pipe closes, the caller's
# `read` returns false).
#
# Pre-extraction this 3-line block lived verbatim in loop/harden/converge
# adapters — three sites diverging only in the model+effort label strings
# (loop: "Model"/"Thinking effort", harden: "Reviewer model"/"Reviewer thinking
# effort", converge: "Model"/"Thinking effort"). The dependency between the
# three calls (model+effort menus REQUIRE provider) was structural; encoding
# that rule in one place makes "add a 4th loop adapter" a one-line call to this
# helper instead of a copy-pasted 3-line dance an adapter could subtly mis-order
# (e.g. asking the model menu before the provider is known).
#
# Sibling to _almanac_launch_need_provider/_choice (the primitives this composes);
# any change to the label convention or menu-scoping rule lives here.
_almanac_launch_need_role_triple() {
  local provider="$1" model="$2" effort="$3" model_label="$4" effort_label="$5"
  provider="$(_almanac_launch_need_provider provider "$provider")" || return 1
  model="$(_almanac_launch_need_choice "$model_label" "$model" $(almanac_provider_models "$provider"))" || return 1
  effort="$(_almanac_launch_need_choice "$effort_label" "$effort" $(almanac_provider_efforts "$provider"))" || return 1
  printf '%s\n%s\n%s\n' "$provider" "$model" "$effort"
}

# Export the consumer-wide role config (PROVIDER always, MODEL/EFFORT conditional)
# under PREFIX (e.g. LOOP_, HARDEN_, CONVERGE_). Empty model/effort UNSET the
# var so a stale value inherited from the parent env can't leak into the runner.
# Single source of truth for the export shape — adding a 4th adapter can't
# forget the unset, and the prefix convention lives in exactly one place.
# Sibling to lib/loops.sh::_almanac_loop_emit_role_env (the printf form used by
# `new_run_env` verbs); both helpers share the prefix+field convention but
# differ in output medium (export with unset here vs printf with skip there).
_almanac_launch_export_role() {
  local prefix="$1" provider="$2" model="$3" effort="$4"
  export "${prefix}PROVIDER=$provider"
  if [ -n "$model" ];  then export "${prefix}MODEL=$model";   else unset "${prefix}MODEL";  fi
  if [ -n "$effort" ]; then export "${prefix}EFFORT=$effort"; else unset "${prefix}EFFORT"; fi
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

# Public entry: configure and launch a run of TYPE (loop|harden|converge|…).
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
