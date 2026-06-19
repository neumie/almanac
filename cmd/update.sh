#!/usr/bin/env bash
# update.sh — Self-update almanac from git, then re-install for active providers.
# summary: Update almanac (git pull + re-install)
# usage: almanac update
# group: maintenance

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"

case "${1:-}" in
  -h|--help) printf '%s\n' "Usage: almanac update"; exit 0 ;;
  "")        ;;
  *)         _die "Unknown update option: $1" ;;
esac

[[ -d "$ALMANAC_HOME/.git" ]] || _die "Not a git repo — can't auto-update"

_info "Updating almanac..."
git -C "$ALMANAC_HOME" pull --ff-only || _die "git pull failed — resolve manually, then re-run"
_success "Updated to $(git -C "$ALMANAC_HOME" rev-parse --short HEAD)"

# Re-install for any providers that are already set up. One provider failing must
# not abort the rest — tally failures and report them at the end.
failed=0
while IFS= read -r provider; do
  _is_installed "$provider" || continue
  if ! "$ALMANAC_HOME/bin/almanac" install "$provider"; then
    _warn "Re-install failed for $provider"
    failed=$((failed + 1))
  fi
done < <(almanac_providers)

[ "$failed" -eq 0 ] || _die "$failed provider(s) failed to re-install — see warnings above"
