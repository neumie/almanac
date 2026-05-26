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
#   signal_file — control: the between-round dot-file basename for stop|steer.

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

# ralph's between-round signal files: the afk runner watches `.ralph-stop` to halt
# and consumes `.ralph-steer` as a one-shot operator/overseer directive. Prints
# the basename; returns 1 for an unknown kind.
almanac_loop_ralph_signal_file() {
  case "$1" in
    stop)  printf '%s\n' ".ralph-stop" ;;
    steer) printf '%s\n' ".ralph-steer" ;;
    *) return 1 ;;
  esac
}
