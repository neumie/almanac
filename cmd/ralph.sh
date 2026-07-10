#!/usr/bin/env bash
# ralph.sh — `almanac ralph`: configure and launch a Ralph loop through the
# shared almanac launcher (lib/loop-launcher.sh). Flags pre-fill; any missing
# field is prompted. One launcher backs `almanac ralph`, the ralph skill
# launcher, and the hub's New-run flow — so the config UX is identical.
# summary: Launch a Ralph spec-slice loop (interactive)
# usage: almanac ralph [--spec N] [--mode once|afk] [--provider P] [--model M] [--effort L] [--iterations N] [--no-oversee] [--yes]
# group: loops

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-launcher.sh"

almanac_loop_launch ralph "$@"
