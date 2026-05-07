#!/usr/bin/env bash
# ralph.sh — Launch the interactive Ralph loop CLI

set -euo pipefail

RALPH_SCRIPT="$ALMANAC_HOME/skills/loop/ralph-loop/scripts/ralph.sh"

[[ -f "$RALPH_SCRIPT" ]] || _die "Ralph launcher not found at $RALPH_SCRIPT"

exec bash "$RALPH_SCRIPT" "$@"
