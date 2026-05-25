#!/usr/bin/env bash
# lib/agent.sh — the agent/provider seam.
#
# This slice (loop-engine-split 03) hosts the provider-adapter seam: discovery
# of lib/providers/<name>.sh, contract dispatch (callers never branch on provider
# name), and the single default-selection policy. A later slice (04) adds the
# three agent shapes (agent_capture/agent_stream/agent_raw) here too — per the
# module map, lib/agent.sh owns "the three shapes + provider dispatch".
#
# Self-contained: like lib/ui.sh, the seam uses only printf / command -v / source
# and has NO dependency on lib/core.sh, so any caller can source it directly.
# Provider adapters are auto-loaded at source time (almanac_provider_load below).

__almanac_agent_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Normalise a provider name to its adapter key (lowercase; claude-code → claude).
almanac_provider_key() {
  local k
  k="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$k" in
    claude-code) k="claude" ;;
  esac
  printf '%s' "$k"
}

# Source every provider adapter (idempotent — adapters only define functions).
almanac_provider_load() {
  local f
  for f in "$__almanac_agent_dir"/providers/*.sh; do
    [ -f "$f" ] || continue
    # shellcheck source=/dev/null
    source "$f"
  done
  return 0
}

# List discovered provider names — the provider list IS the files present, so
# there is no second place to update. Sorted by the glob (alphabetical).
almanac_provider_list() {
  local f name
  for f in "$__almanac_agent_dir"/providers/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    printf '%s\n' "$name"
  done
  return 0
}

# Is NAME a discovered provider?
almanac_provider_known() {
  local want target
  want="$(almanac_provider_key "$1")"
  while IFS= read -r target; do
    [ "$target" = "$want" ] && return 0
  done <<EOF
$(almanac_provider_list)
EOF
  return 1
}

# Dispatch a contract verb to NAME's adapter: almanac_provider_call <name> <verb>
# [args…]. Returns 2 if the adapter doesn't implement the verb. This is the one
# place that turns (provider, verb) into a function call, so no caller anywhere
# branches on provider name.
almanac_provider_call() {
  local key verb fn
  key="$(almanac_provider_key "$1")"
  verb="$2"
  shift 2
  fn="almanac_provider_${key}_${verb}"
  declare -F "$fn" >/dev/null 2>&1 || return 2
  "$fn" "$@"
}

# Thin public wrappers over the contract verbs.
almanac_provider_available()  { almanac_provider_call "$1" available; }
almanac_provider_active_env() { almanac_provider_call "$1" active_env; }
almanac_provider_models()     { almanac_provider_call "$1" models; }
almanac_provider_efforts()    { almanac_provider_call "$1" efforts; }
almanac_provider_display()    { almanac_provider_call "$1" display; }
almanac_provider_filter()     { almanac_provider_call "$1" filter; }
# argv populates the global _ALMANAC_AGENT_ARGV; callers use almanac_provider_call
# "<name>" argv <model> <effort> <sandbox> <result_file> <shape> directly.

# The single central default-selection policy (the one provider remainder that is
# not in an adapter, by design): the active-env provider if it is installed, else
# the first installed provider in preference order (claude → codex). Echoes the
# chosen name, or "" if no provider is installed.
almanac_provider_default() {
  local p
  # Phase 1 — the provider whose resumable session we are inside.
  for p in $(almanac_provider_list); do
    if almanac_provider_active_env "$p" && almanac_provider_available "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  # Phase 2 — preference order.
  for p in claude codex; do
    if almanac_provider_available "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  printf '%s\n' ""
  return 0
}

almanac_provider_load
