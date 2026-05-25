#!/usr/bin/env bash
# hub.sh — interactive front door to almanac loops (ralph, harden)
#
# Bare `almanac` routes here on a TTY (and `almanac hub` always does). The hub
# reads the run registry under the caller's repo ($PWD/.almanac/runs) and shows
# the loops it finds: a Running section (live status) and a Recent section (last
# finished). Off a TTY / without gum it renders that overview as plain text and
# exits — it never blocks on an interactive menu, so `almanac hub | cat`, scripts
# and tests get a clean read view. The interactive new-run / per-run menus layer
# on top of this read view (later increments).

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-core.sh"

ROOT="$PWD"

almanac_loop_hub_overview "$ROOT"
