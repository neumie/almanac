#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local plugin_dir="$ALMANAC_HOME/providers/claude-code"
  local skills_link="$plugin_dir/skills"
  local cache_dir="$HOME/.claude/plugins/cache/claude-plugins-official/almanac"
  local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
  local settings_file="$HOME/.claude/settings.json"

  # Remove skills symlink
  [[ -L "$skills_link" ]] && rm "$skills_link"

  # Remove cache symlink
  [[ -L "$cache_dir/0.1.0" ]] && rm "$cache_dir/0.1.0"
  [[ -d "$cache_dir" ]] && rmdir "$cache_dir" 2>/dev/null || true

  # Remove from installed_plugins.json
  if [[ -f "$plugins_file" ]]; then
    python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
data['plugins'].pop('almanac@claude-plugins-official', None)
with open('$plugins_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

  # Remove from settings.json
  if [[ -f "$settings_file" ]]; then
    python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
data.get('enabledPlugins', {}).pop('almanac@claude-plugins-official', None)
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi

  # Clean up almanac hook from settings.json if present
  if [[ -f "$settings_file" ]]; then
    python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
sh = hooks.get('SessionStart', [])
hooks['SessionStart'] = [
    h for h in sh
    if not any('almanac' in hh.get('command', '') for hh in h.get('hooks', []))
]
if not hooks.get('SessionStart'):
    hooks.pop('SessionStart', None)
if not hooks:
    data.pop('hooks', None)
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
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
