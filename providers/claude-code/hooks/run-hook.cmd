#!/usr/bin/env bash
# run-hook.cmd — Generic hook runner for almanac
# Usage: run-hook.cmd <hook-name> [args...]

set -euo pipefail

ALMANAC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_NAME="${1:?Usage: run-hook.cmd <hook-name>}"
shift

HOOK_SCRIPT="$(dirname "$0")/$HOOK_NAME"

if [ ! -f "$HOOK_SCRIPT" ]; then
  echo "almanac: hook '$HOOK_NAME' not found" >&2
  exit 1
fi

export ALMANAC_ROOT
exec "$HOOK_SCRIPT" "$@"
