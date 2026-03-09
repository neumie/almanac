#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
  local settings_file="$HOME/.claude/settings.json"
  local plugin_key="almanac@local"

  if [[ -f "$plugins_file" ]]; then
    python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
data['plugins'].pop('$plugin_key', None)
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
    data['enabledPlugins'].pop('$plugin_key', None)
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

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
