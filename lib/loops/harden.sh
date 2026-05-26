#!/usr/bin/env bash
# lib/loops/harden.sh — the harden loop adapter.
#
# One file owns everything the engine needs to know about how to launch and
# control the harden loop. Auto-discovered by lib/loops.sh from lib/loops/*.sh.
#
# Contract (called as almanac_loop_harden_<verb>):
#   exec_argv   — launch: populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                 for a given target/rounds. harden's runner is the convergence
#                 loop reached via `almanac harden <target> --loop`.
#
# Control contract (signal_file) inherits the default `.harden-stop` /
# `.harden-steer` convention from lib/loops.sh — no adapter override needed.

# Build harden's runner exec command into _ALMANAC_LOOP_ARGV (the launcher execs
# it). harden has no standalone runner script — its convergence loop runs through
# the CLI (`almanac harden <target> --loop [--rounds N]`), so the adapter yields
# that bin/almanac invocation. The reviewer/role config rides on environment
# exported by the launcher, not argv. Requires $ALMANAC_HOME (set by every entry
# point).
almanac_loop_harden_exec_argv() {
  local target="$1" rounds="${2:-}"
  _ALMANAC_LOOP_ARGV=(bash "$ALMANAC_HOME/bin/almanac" harden "$target" --loop)
  [ -n "$rounds" ] && _ALMANAC_LOOP_ARGV+=(--rounds "$rounds")
  return 0
}
