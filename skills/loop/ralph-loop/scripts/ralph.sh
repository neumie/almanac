#!/usr/bin/env bash
# ralph.sh — interactive Ralph launcher (direct entry point).
#
# Thin delegate to the shared almanac launcher (lib/loop-launcher.sh) so a direct
# `bash ralph.sh` and `almanac ralph` share one config UX — no second launcher to
# keep in sync. pwd -P resolves the install symlink
# (~/.claude/skills/almanac/ralph-loop -> repo) to the real ALMANAC_HOME, so this
# works whether launched from the repo or an installed provider path.

set -euo pipefail

# ALMANAC_HOME bootstrap — prefer an exported value, else self-resolve
# symlink-safe (pwd -P) at this file's known depth. Mirrors almanac_resolve_home
# in lib/core.sh; keep the two in sync.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)}"

for _lib in core loop-launcher; do
  if [ ! -f "$ALMANAC_HOME/lib/${_lib}.sh" ]; then
    echo "Error: lib/${_lib}.sh not found at $ALMANAC_HOME/lib/${_lib}.sh" >&2
    exit 1
  fi
  source "$ALMANAC_HOME/lib/${_lib}.sh"
done

almanac_loop_launch ralph "$@"
