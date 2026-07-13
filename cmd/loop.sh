#!/usr/bin/env bash
# loop.sh — `almanac loop`: configure and launch a Loop through the
# shared almanac launcher (lib/loop-launcher.sh). Flags pre-fill; any missing
# field is prompted. One launcher backs `almanac loop`, the loop skill
# launcher, and the hub's New-run flow — so the config UX is identical.
# summary: Launch a Loop spec-slice loop (interactive)
# usage: almanac loop [--spec N] [--mode once|afk] [--provider P] [--model M] [--effort L] [--iterations N] [--no-oversee] [--yes]
# group: loops

set -euo pipefail

source "$ALMANAC_HOME/lib/loop-launcher.sh"

almanac_loop_launch loop "$@"
