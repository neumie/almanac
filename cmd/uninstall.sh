#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

_uninstall_claude_code() {
  local commands_dir="$HOME/.claude/commands"

  # Remove skill symlinks from ~/.claude/commands/
  local count=0
  for dir in "$ALMANAC_HOME"/skills/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")
    local target="$commands_dir/$name.md"

    if [[ -L "$target" ]]; then
      rm "$target"
      count=$((count + 1))
    fi
  done
  _info "Removed $count skill symlinks from ~/.claude/commands/"

  # Clean up legacy plugin registry entries (from older installs)
  local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"
  local settings="$HOME/.claude/settings.json"

  if [[ -f "$installed_plugins" ]] && grep -q 'almanac@local' "$installed_plugins"; then
    python3 -c "
import json
path = '$installed_plugins'
data = json.load(open(path))
data.get('plugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
"
    _info "Removed legacy almanac@local from installed_plugins.json"
  fi

  if [[ -f "$settings" ]] && grep -q 'almanac@local' "$settings"; then
    python3 -c "
import json
path = '$settings'
data = json.load(open(path))
data.get('enabledPlugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
"
    _info "Removed legacy almanac@local from settings.json"
  fi

  # Clean up legacy alias from shell rc (from older installs)
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
