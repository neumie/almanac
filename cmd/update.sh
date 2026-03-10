#!/usr/bin/env bash
# update.sh — Self-update almanac from git

if [[ ! -d "$ALMANAC_HOME/.git" ]]; then
  _die "Not a git repo — can't auto-update"
fi

_info "Updating almanac..."
git -C "$ALMANAC_HOME" pull --ff-only
_success "Updated to $(git -C "$ALMANAC_HOME" rev-parse --short HEAD)"

# Refresh Claude Code marketplace clone and cache if installed
local marketplace_dir="$HOME/.claude/plugins/marketplaces/almanac"
if [[ -d "$marketplace_dir/.git" ]]; then
  _info "Updating marketplace clone..."
  git -C "$marketplace_dir" pull --ff-only --quiet 2>/dev/null || true

  # Refresh cache
  local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
  if [[ -f "$plugins_file" ]]; then
    local version
    version=$(python3 -c "import json; print(json.load(open('$ALMANAC_HOME/providers/claude-code/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
    if [[ -n "$version" ]]; then
      local cache_dir="$HOME/.claude/plugins/cache/almanac/almanac/$version"
      rm -rf "$cache_dir"
      mkdir -p "$cache_dir"
      cp -R "$marketplace_dir/providers/claude-code/." "$cache_dir/"
      _info "Refreshed Claude Code plugin cache"
    fi
  fi
fi
