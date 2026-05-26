#!/usr/bin/env bash
# lib/loops/ralph.sh — the ralph loop adapter.
#
# One file owns everything the engine needs to know about how to launch and
# control the ralph loop. Auto-discovered by lib/loops.sh from lib/loops/*.sh.
#
# Contract (called as almanac_loop_ralph_<verb>):
#   exec_argv   — launch: populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                 for a given mode/prd/iterations. The ralph runner path lives
#                 HERE now (not hard-coded in the launcher).
#
# Control contract (signal_file) inherits the default `.ralph-stop` / `.ralph-steer`
# convention from lib/loops.sh — no adapter override needed.

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
