#!/usr/bin/env bash
# doctor.sh — Report almanac's optional-dependency status.
# summary: Report optional-dependency status (gum, gh, jq)
# usage: almanac doctor
# group: maintenance

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"

case "${1:-}" in
  -h|--help) printf '%s\n' "Usage: almanac doctor"; exit 0 ;;
  "")        ;;
  *)         _die "Unknown doctor option: $1" ;;
esac

_heading "almanac doctor — environment check"
printf '\n'

# gum (Charm) — optional, styles loop dashboards + HITL prompts.
# Absent is fine: the CLI degrades to plain output (near-zero-dependency promise).
almanac_report_gum

# gh + jq are used by the loop engine (ralph overseer / issue queues; findings
# parsing). Optional too, but worth surfacing so users know what's missing.
if command -v gh >/dev/null 2>&1; then
  _success "gh: installed ($(command -v gh)) — issue queues + CI watch available"
else
  _warn "gh: not found — GitHub issue queues and CI watch are unavailable"
fi

if command -v jq >/dev/null 2>&1; then
  _success "jq: installed ($(command -v jq)) — findings parsed via jq"
else
  _warn "jq: not found — findings parsing falls back to awk"
fi
