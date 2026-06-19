#!/usr/bin/env bash
# list.sh — List available providers and their install status.
# summary: List available providers + install status
# usage: almanac list
# group: providers

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"

case "${1:-}" in
  -h|--help) printf '%s\n' "Usage: almanac list"; exit 0 ;;
  "")        ;;
  *)         _die "Unknown list option: $1" ;;
esac

_heading "Available providers"
while IFS= read -r provider; do
  if _is_installed "$provider"; then
    printf '  %b%s%b  (installed)\n' "$_GREEN" "$provider" "$_RESET"
  else
    printf '  %s\n' "$provider"
  fi
done < <(almanac_providers)
