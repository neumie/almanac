#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local plugin_dir="$ALMANAC_HOME/providers/claude-code"
  local skills_link="$plugin_dir/skills"
  local plugins_dir="$HOME/.claude/plugins"
  local cache_dir="$plugins_dir/cache/claude-plugins-official/almanac/0.1.0"
  local plugins_file="$plugins_dir/installed_plugins.json"
  local settings_file="$HOME/.claude/settings.json"
  local plugin_key="almanac@claude-plugins-official"

  local manifest="$plugins_dir/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  [[ -f "$manifest" ]] || _die "Official marketplace not found — install a plugin from Claude Code first"

  # 1. Add almanac to the local marketplace manifest
  python3 -c "
import json
with open('$manifest', 'r') as f:
    data = json.load(f)
if not any(p.get('name') == 'almanac' for p in data.get('plugins', [])):
    data['plugins'].append({
        'name': 'almanac',
        'description': 'Personal agent toolkit — skills, prompts, and patterns',
        'version': '0.1.0',
        'author': {'name': 'neumie'},
        'source': './plugins/almanac',
        'category': 'development'
    })
    with open('$manifest', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
"

  # 2. Symlink skills into the plugin directory (so they're in the plugin dir)
  if [[ -L "$skills_link" ]]; then
    rm "$skills_link"
  elif [[ -d "$skills_link" ]]; then
    rm -rf "$skills_link"
  fi
  ln -s "$ALMANAC_HOME/skills" "$skills_link"

  # 2. Symlink plugin into the Claude Code cache
  mkdir -p "$(dirname "$cache_dir")"
  if [[ -L "$cache_dir" ]]; then
    rm "$cache_dir"
  elif [[ -d "$cache_dir" ]]; then
    rm -rf "$cache_dir"
  fi
  ln -s "$plugin_dir" "$cache_dir"

  # 3. Register in installed_plugins.json
  [[ -f "$plugins_file" ]] || echo '{"version":2,"plugins":{}}' > "$plugins_file"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
data['plugins']['$plugin_key'] = [{
    'scope': 'user',
    'installPath': '$cache_dir',
    'version': '0.1.0',
    'installedAt': '$now',
    'lastUpdated': '$now'
}]
with open('$plugins_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  # 4. Enable in settings.json
  [[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

  python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
ep = data.setdefault('enabledPlugins', {})
ep['$plugin_key'] = True
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
