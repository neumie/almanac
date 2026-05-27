#!/usr/bin/env bash
# lib/loops.sh — the loop-adapter seam (discovery + dispatch).
#
# Mirrors the provider-adapter seam (lib/agent.sh): each loop adapter is a
# drop-in adapter file at lib/loops/<name>.sh answering one fixed question set, so
# no central code branches on a loop type. This module owns discovery (the loop
# list IS the files present), name-normalising dispatch (the one place a loop type
# becomes a function call), and auto-loads the adapters at source time.
#
# Each adapter (called as almanac_loop_<name>_<verb>) declares these contracts:
#   launch     — launch / launch_usage / exec_argv, consumed by the launcher.
#   new-run    — new_run_argv / new_run_env / new_run_usage, consumed by the hub.
#   resume     — status_to_opts, plus optional launch_backed.
#   control    — signal_file <stop|steer>, optional when using the standard
#                `.${name}-${kind}` convention.
#
# Self-contained: uses only printf / tr / basename / source — no lib/core.sh
# dependency — so the seam (and the adapters) are their own test surface and
# tests/test-loops.sh sources this file directly.

__almanac_loops_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Normalise a loop name to its adapter key (lowercase).
almanac_loop_adapter_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Source every loop adapter (idempotent — adapters only define functions).
almanac_loop_adapter_load() {
  local f
  for f in "$__almanac_loops_dir"/loops/*.sh; do
    [ -f "$f" ] || continue
    # shellcheck source=/dev/null
    source "$f"
  done
  return 0
}

# List discovered loop names — the loop list IS the files present, so there is no
# second place to update. Sorted by the glob (alphabetical).
almanac_loop_adapter_list() {
  local f name
  for f in "$__almanac_loops_dir"/loops/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    printf '%s\n' "$name"
  done
  return 0
}

# Is NAME a discovered loop?
almanac_loop_adapter_known() {
  local want target
  want="$(almanac_loop_adapter_key "$1")"
  while IFS= read -r target; do
    [ "$target" = "$want" ] && return 0
  done <<EOF
$(almanac_loop_adapter_list)
EOF
  return 1
}

# Dispatch a contract verb to NAME's adapter: almanac_loop_adapter_call <name>
# <verb> [args…]. Returns 2 if the adapter doesn't implement the verb. This is the
# one place that turns (loop, verb) into a function call, so no caller branches on
# loop type.
almanac_loop_adapter_call() {
  local key verb fn
  key="$(almanac_loop_adapter_key "$1")"
  verb="$2"
  shift 2
  fn="almanac_loop_${key}_${verb}"
  declare -F "$fn" >/dev/null 2>&1 || return 2
  "$fn" "$@"
}

# Look up the value for KEY in a stream of `key=value` PAIRS (the lingua franca
# the hub speaks to a loop adapter's new_run_argv / new_run_env verbs). Echoes
# the value (which may itself contain `=`, e.g. `--prompt /foo bar=baz`) and
# returns 0; echoes nothing when KEY is absent. Later pairs win, matching the
# `case "$key" in foo) v="$val" ;; esac` semantics each adapter used to inline.
# Lives in the loop-adapter seam (lib/loops.sh) because every adapter's
# composer is its only caller — keeps the lookup pattern in one place so a
# fourth loop is a single-file addition instead of a fourth copy of the loop.
_almanac_loop_kv_get() {
  local want="$1"; shift
  local pair value=""
  for pair in "$@"; do
    case "$pair" in
      "$want="*) value="${pair#*=}" ;;
    esac
  done
  printf '%s\n' "$value"
}

# Emit the consumer-wide role triple as KEY=VALUE lines under PREFIX (the
# `<PREFIX>PROVIDER` / `<PREFIX>MODEL` / `<PREFIX>EFFORT` env keys role.sh's
# resolver layers under). Empty fields drop their key. Used by every loop
# adapter's `new_run_env` verb (harden, converge — ralph rides on argv only) so
# the key-name convention lives in exactly one printf — adding a 4th adapter
# costs zero new spellings, and renaming a field key only changes this helper.
# Sibling to lib/loop-launcher.sh::_almanac_launch_export_role (the export form
# used by launch verbs); both helpers share the prefix+field convention but
# differ in output medium (export with unset vs printf with skip).
_almanac_loop_emit_role_env() {
  local prefix="$1" provider="$2" model="$3" effort="$4"
  [ -n "$provider" ] && printf '%sPROVIDER=%s\n' "$prefix" "$provider"
  [ -n "$model" ]    && printf '%sMODEL=%s\n' "$prefix" "$model"
  [ -n "$effort" ]   && printf '%sEFFORT=%s\n' "$prefix" "$effort"
  return 0
}

# Default signal-file basename for a loop's between-round control. Every loop uses
# the same `.${name}-${kind}` convention (`.ralph-stop`, `.harden-steer`, …) so the
# pattern lives once here instead of being copy-pasted into each adapter. A loop
# only needs to define its own `signal_file` if its convention diverges; this is
# the deepening that turns three identical stop|steer case-statements into none.
# Returns 1 for an unknown kind.
almanac_loop_default_signal_file() {
  local name="$1" kind="$2"
  case "$kind" in
    stop|steer) printf '.%s-%s\n' "$name" "$kind" ;;
    *) return 1 ;;
  esac
}

# Resolve a loop's signal-file basename: the adapter's override if it defines
# `signal_file`, else the standard `.${name}-${kind}` default. This is the
# control-contract public surface — callers (lib/run.sh, harden-core, converge-core)
# go through here instead of dispatching to the adapter directly, so adding a new
# loop costs zero signal_file code unless the loop is non-standard. Returns 1 for
# an unknown kind or an unknown loop name.
almanac_loop_signal_file() {
  local key fn
  key="$(almanac_loop_adapter_key "$1")"
  almanac_loop_adapter_known "$key" || return 1
  fn="almanac_loop_${key}_signal_file"
  if declare -F "$fn" >/dev/null 2>&1; then
    "$fn" "$2"
  else
    almanac_loop_default_signal_file "$key" "$2"
  fi
}

# Resolve the DIRECTORY a loop's signal file lives in.
#
# Default: $root — ralph and harden both drop `.ralph-stop` / `.harden-stop`
# at the repo root because their loops watch root.
#
# Override: a loop's adapter can define `almanac_loop_<name>_signal_dir
# <root> <target>` to scope signals to a per-run directory instead. Converge
# does this — its signal files live under the run's plan dir so a CONVERGED
# verdict's `.converge-stop` cannot poison a subsequent unrelated converge
# run (the bug observed: previous CONVERGED run wrote $root/.converge-stop,
# next launch aborted at round 0 because that root-level stop file was still
# there). Returns 1 for an unknown loop name.
almanac_loop_signal_dir() {
  local key fn
  key="$(almanac_loop_adapter_key "$1")"
  almanac_loop_adapter_known "$key" || return 1
  local root="$2" target="${3:-}"
  fn="almanac_loop_${key}_signal_dir"
  if declare -F "$fn" >/dev/null 2>&1; then
    "$fn" "$root" "$target"
  else
    printf '%s\n' "$root"
  fi
}

almanac_loop_adapter_load
