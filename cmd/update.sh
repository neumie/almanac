#!/usr/bin/env bash
# update.sh — Self-update almanac from git

if [[ ! -d "$ALMANAC_HOME/.git" ]]; then
  _die "Not a git repo — can't auto-update"
fi

_info "Updating almanac..."
git -C "$ALMANAC_HOME" pull --ff-only
_success "Updated to $(git -C "$ALMANAC_HOME" rev-parse --short HEAD)"
