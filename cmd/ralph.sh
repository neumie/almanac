#!/usr/bin/env bash
# ralph.sh — `almanac ralph`: configure and launch a Ralph loop through the
# shared almanac launcher (lib/loop-launcher.sh). Flags pre-fill; any missing
# field is prompted. One launcher backs `almanac ralph`, the ralph skill
# launcher, and the hub's New-run flow — so the config UX is identical.

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-launcher.sh"

almanac_loop_launch ralph "$@"
