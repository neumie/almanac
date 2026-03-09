#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local claude_dir="$HOME/.claude"
  local plugins_file="$claude_dir/plugins/installed_plugins.json"
  local settings_file="$claude_dir/settings.json"
  local plugin_key="almanac@local"

  [[ -d "$claude_dir" ]] || _die "~/.claude not found — is Claude Code installed?"
  [[ -f "$PROVIDER_DIR/.claude-plugin/plugin.json" ]] || _die ".claude-plugin/plugin.json not found"

  # Create skills symlink if missing
  if [[ ! -e "$PROVIDER_DIR/skills" ]]; then
    ln -s ../../skills "$PROVIDER_DIR/skills"
  fi

  # Read version
  local version
  version=$(python3 -c "import json; print(json.load(open('$PROVIDER_DIR/.claude-plugin/plugin.json'))['version'])")
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  # Register plugin
  mkdir -p "$claude_dir/plugins"
  [[ -f "$plugins_file" ]] || echo '{"version":2,"plugins":{}}' > "$plugins_file"

  python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
data['plugins']['$plugin_key'] = [{
    'scope': 'user',
    'installPath': '$PROVIDER_DIR',
    'version': '$version',
    'installedAt': '$now',
    'lastUpdated': '$now',
    'gitCommitSha': '0000000000000000000000000000000000000000'
}]
with open('$plugins_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  # Enable in settings
  [[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

  python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
data.setdefault('enabledPlugins', {})['$plugin_key'] = True
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  _success "Installed almanac for Claude Code"
  _info "Restart Claude Code to activate"
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
