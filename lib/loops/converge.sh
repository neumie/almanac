#!/usr/bin/env bash
# lib/loops/converge.sh - converge loop adapter.
#
# Contract (called as almanac_loop_converge_<verb>):
#   exec_argv   — launch: populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                 for a given goal / exec / rounds / oversee config. Converge's
#                 runner is the CLI itself (`almanac converge --goal … --exec …`),
#                 so the adapter yields that bin/almanac invocation. Mirrors
#                 harden's adapter shape (no standalone runner script).
#
# Control contract (signal_file) inherits the default `.converge-stop` /
# `.converge-steer` convention from lib/loops.sh — no adapter override needed.

# Build converge's runner exec command into _ALMANAC_LOOP_ARGV (the launcher
# execs it). Positional args:
#   $1  goal           (required)
#   $2  action_mode    "prompt" | "exec" (required) — picks the flag $3 maps to
#   $3  action         the prompt text OR shell command (required)
#   $4  rounds         (optional) numeric budget
#   $5  no_oversee     (optional) "1" / "true" enables, anything else is off
#   $6  oversee_every  (optional) cadence
# The role config (provider/model/effort per CONVERGE_AGENT_* / CONVERGE_OVERSEER_*)
# rides on environment exported by the launcher, not argv — same split ralph and
# harden use. Requires $ALMANAC_HOME (set by every entry point).
# Returns 2 on an unknown action_mode.
almanac_loop_converge_exec_argv() {
  local goal="$1" mode="$2" action="$3" rounds="${4:-}" no_oversee="${5:-}" oversee_every="${6:-}"
  local action_flag
  case "$mode" in
    prompt) action_flag="--prompt" ;;
    exec)   action_flag="--exec" ;;
    *) return 2 ;;
  esac
  _ALMANAC_LOOP_ARGV=(bash "$ALMANAC_HOME/bin/almanac" converge --goal "$goal" "$action_flag" "$action")
  [ -n "$rounds" ]         && _ALMANAC_LOOP_ARGV+=(--rounds "$rounds")
  [ -n "$no_oversee" ]     && [ "$no_oversee" != "0" ] && _ALMANAC_LOOP_ARGV+=(--no-oversee)
  [ -n "$oversee_every" ]  && _ALMANAC_LOOP_ARGV+=(--oversee-every "$oversee_every")
  return 0
}
