#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local plugins_dir="$HOME/.claude/plugins"
  local plugins_file="$plugins_dir/installed_plugins.json"
  local settings_file="$HOME/.claude/settings.json"
  local marketplaces_file="$plugins_dir/known_marketplaces.json"

  if [[ -f "$plugins_file" ]]; then
    python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
for key in ['almanac@almanac', 'almanac@local', 'almanac@claude-plugins-official']:
    data['plugins'].pop(key, None)
with open('$plugins_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

  if [[ -f "$settings_file" ]]; then
    python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
if 'enabledPlugins' in data:
    for key in ['almanac@almanac', 'almanac@local', 'almanac@claude-plugins-official']:
        data['enabledPlugins'].pop(key, None)
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

  # Remove marketplace registration
  if [[ -f "$marketplaces_file" ]]; then
    python3 -c "
import json
with open('$marketplaces_file', 'r') as f:
    data = json.load(f)
data.pop('almanac', None)
with open('$marketplaces_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

  # Clean up cache and marketplace clone
  rm -rf "$plugins_dir/cache/almanac" 2>/dev/null || true
  rm -rf "$plugins_dir/cache/claude-plugins-official/almanac" 2>/dev/null || true
  rm -rf "$plugins_dir/marketplaces/almanac" 2>/dev/null || true

  _success "Uninstalled almanac from Claude Code"
  _info "Restart Claude Code to take effect"
}

# --- main ---

PROVIDER="${1:-}"
[[ -z "$PROVIDER" ]] && _die "Usage: almanac uninstall <provider>"

PROVIDER_DIR="$ALMANAC_HOME/providers/$PROVIDER"
[[ -d "$PROVIDER_DIR" ]] || _die "Unknown provider: $PROVIDER (run 'almanac list')"

case "$PROVIDER" in
  claude-code)
    _uninstall_claude_code
    ;;
  *)
    _warn "No uninstaller for $PROVIDER — remove manually"
    ;;
esac
