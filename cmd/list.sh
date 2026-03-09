#!/usr/bin/env bash
# list.sh — List available providers

echo "Available providers:"
for provider in $(almanac_providers); do
  echo "  $provider"
done
