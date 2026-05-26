#!/usr/bin/env bash
# lib/loops/converge.sh - converge loop adapter.
#
# Contract (called as almanac_loop_converge_<verb>):
#   exec_argv   — launch: populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                 for a given goal / exec / rounds / oversee config. Converge's
#                 runner is the CLI itself (`almanac converge --goal … --exec …`),
#                 so the adapter yields that bin/almanac invocation. Mirrors
#                 harden's adapter shape (no standalone runner script).
#   signal_file — control: the between-round dot-file basename for stop|steer.

# Build converge's runner exec command into _ALMANAC_LOOP_ARGV (the launcher
# execs it). Required positional args are GOAL and EXEC; optional positionals
# ROUNDS, NO_OVERSEE (1 or empty), OVERSEE_EVERY tag onto the flags only when
# non-empty / non-zero. The role config (provider/model/effort per CONVERGE_AGENT_*
# / CONVERGE_OVERSEER_*) rides on environment exported by the launcher, not argv —
# the same split ralph and harden use. Requires $ALMANAC_HOME (set by every
# entry point).
almanac_loop_converge_exec_argv() {
  local goal="$1" exec_cmd="$2" rounds="${3:-}" no_oversee="${4:-}" oversee_every="${5:-}"
  _ALMANAC_LOOP_ARGV=(bash "$ALMANAC_HOME/bin/almanac" converge --goal "$goal" --exec "$exec_cmd")
  [ -n "$rounds" ]         && _ALMANAC_LOOP_ARGV+=(--rounds "$rounds")
  [ -n "$no_oversee" ]     && [ "$no_oversee" != "0" ] && _ALMANAC_LOOP_ARGV+=(--no-oversee)
  [ -n "$oversee_every" ]  && _ALMANAC_LOOP_ARGV+=(--oversee-every "$oversee_every")
  return 0
}

# converge's between-round signal files: the loop watches `.converge-stop` to
# halt and consumes `.converge-steer` as a one-shot operator/overseer directive.
# Prints the basename; returns 1 for an unknown kind.
almanac_loop_converge_signal_file() {
  case "$1" in
    stop)  printf '%s\n' ".converge-stop" ;;
    steer) printf '%s\n' ".converge-steer" ;;
    *) return 1 ;;
  esac
}
