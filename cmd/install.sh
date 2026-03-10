#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local plugin_dir="$ALMANAC_HOME/providers/claude-code"
  local skills_link="$plugin_dir/skills"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"

  # 1. Symlink skills into the plugin directory
  if [[ -L "$skills_link" ]]; then
    rm "$skills_link"
  elif [[ -d "$skills_link" ]]; then
    rm -rf "$skills_link"
  fi
  ln -s "$ALMANAC_HOME/skills" "$skills_link"

  # 2. Register plugin in Claude Code's plugin registry
  local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"
  local settings="$HOME/.claude/settings.json"
  local version
  version=$(python3 -c "import json; print(json.load(open('$plugin_dir/.claude-plugin/plugin.json'))['version'])")
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  # Add to installed_plugins.json
  python3 -c "
import json, os
path = '$installed_plugins'
if os.path.exists(path):
    data = json.load(open(path))
else:
    data = {'version': 2, 'plugins': {}}
data['plugins']['almanac@local'] = [{
    'scope': 'user',
    'installPath': '$plugin_dir',
    'version': '$version',
    'installedAt': '$now',
    'lastUpdated': '$now'
}]
json.dump(data, open(path, 'w'), indent=2)
"
  _info "Registered plugin in installed_plugins.json"

  # Enable in settings.json
  python3 -c "
import json
path = '$settings'
data = json.load(open(path))
if 'enabledPlugins' not in data:
    data['enabledPlugins'] = {}
data['enabledPlugins']['almanac@local'] = True
json.dump(data, open(path, 'w'), indent=2)
"
  _info "Enabled plugin in settings.json"

  # 3. Add shell alias for terminal use (--plugin-dir is the primary loading mechanism)
  local alias_line="alias claude='claude --plugin-dir \"$plugin_dir\"'"
  local shell_rc="$HOME/.zshrc"
  [[ -f "$shell_rc" ]] || shell_rc="$HOME/.bashrc"

  if [[ -f "$shell_rc" ]] && grep -q 'plugin-dir.*almanac' "$shell_rc" 2>/dev/null; then
    _info "Alias already in $shell_rc"
  elif [[ -f "$shell_rc" ]]; then
    echo "" >> "$shell_rc"
    echo "# Almanac — load skills into Claude Code" >> "$shell_rc"
    echo "$alias_line" >> "$shell_rc"
    _info "Added alias to $shell_rc"
  fi

  _success "Installed almanac for Claude Code"
  _info "Run: source $shell_rc"
  _info "Then start claude as usual — almanac skills are loaded automatically"
}

_install_symlink() {
  local provider="$1"
  local readme="$ALMANAC_HOME/providers/$provider/README.md"
  if [[ -f "$readme" ]]; then
    _info "Follow the setup instructions:"
    echo ""
    cat "$readme"
  else
    _warn "No setup instructions for $provider"
  fi
}

# --- main ---

PROVIDER="${1:-}"
[[ -z "$PROVIDER" ]] && _die "Usage: almanac install <provider>"

PROVIDER_DIR="$ALMANAC_HOME/providers/$PROVIDER"
[[ -d "$PROVIDER_DIR" ]] || _die "Unknown provider: $PROVIDER (run 'almanac list')"

case "$PROVIDER" in
  claude-code)
    _install_claude_code
    ;;
  opencode|cursor|codex)
    _install_symlink "$PROVIDER"
    ;;
  *)
    _die "No installer for provider: $PROVIDER"
    ;;
esac
