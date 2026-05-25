#!/usr/bin/env bash
# lib/loops.sh — the loop-adapter seam (discovery + dispatch).
#
# Mirrors the provider-adapter seam (lib/agent.sh): each loop (ralph, harden) is a
# drop-in adapter file at lib/loops/<name>.sh answering one fixed question set, so
# no central code branches on a loop type. This module owns discovery (the loop
# list IS the files present), name-normalising dispatch (the one place a loop type
# becomes a function call), and auto-loads the adapters at source time.
#
# Each adapter (called as almanac_loop_<name>_<verb>) declares two contracts:
#   launch  — exec_argv: how to exec its runner (config in, _ALMANAC_LOOP_ARGV out)
#             — consumed by the launcher (lib/loop-launcher.sh)
#   control — signal_file <stop|steer>: its between-round dot-file basename
#             — consumed by the hub's stop/steer (lib/run.sh control)
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

almanac_loop_adapter_load
