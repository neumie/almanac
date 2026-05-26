#!/usr/bin/env bash
# list.sh — List available providers

source "$ALMANAC_HOME/lib/core.sh"

echo "Available providers:"
for provider in $(almanac_providers); do
  if _is_installed "$provider"; then
    echo -e "  ${_GREEN}$provider${_RESET}  (installed)"
  else
    echo "  $provider"
  fi
done
