#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local plugin_dir="$ALMANAC_HOME/providers/claude-code"
  local skills_link="$plugin_dir/skills"
  local wrapper="$HOME/.local/bin/claude-almanac"

  # Remove skills symlink
  [[ -L "$skills_link" ]] && rm "$skills_link"

  # Remove shell wrapper
  [[ -f "$wrapper" ]] && rm "$wrapper"

  # Remove almanac hook from settings.json if present
  local settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    python3 -c "
import json

with open('$settings_file', 'r') as f:
    data = json.load(f)

hooks = data.get('hooks', {})
session_hooks = hooks.get('SessionStart', [])

# Remove any hook whose command contains 'almanac'
hooks['SessionStart'] = [
    h for h in session_hooks
    if not any('almanac' in hh.get('command', '') for hh in h.get('hooks', []))
]

# Clean up empty arrays
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
