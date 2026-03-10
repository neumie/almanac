#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local plugin_dir="$ALMANAC_HOME/providers/claude-code"
  local skills_link="$plugin_dir/skills"

  # Remove skills symlink
  [[ -L "$skills_link" ]] && rm "$skills_link"

  # Remove plugin from registry
  local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"
  local settings="$HOME/.claude/settings.json"

  if [[ -f "$installed_plugins" ]]; then
    python3 -c "
import json
path = '$installed_plugins'
data = json.load(open(path))
data.get('plugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
"
    _info "Removed from installed_plugins.json"
  fi

  if [[ -f "$settings" ]]; then
    python3 -c "
import json
path = '$settings'
data = json.load(open(path))
data.get('enabledPlugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
"
    _info "Removed from settings.json"
  fi

  # Clean up legacy alias from shell rc (if present from older installs)
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]] && grep -q 'plugin-dir.*almanac' "$rc"; then
      python3 -c "
lines = open('$rc').readlines()
out = []
skip_next = False
for line in lines:
    if '# Almanac' in line and 'Claude Code' in line:
        skip_next = True
        continue
    if skip_next and 'plugin-dir' in line:
        skip_next = False
        continue
    skip_next = False
    out.append(line)
while out and out[-1].strip() == '':
    out.pop()
out.append('\n')
open('$rc', 'w').write(''.join(out))
"
      _info "Removed legacy alias from $rc"
    fi
  done

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
