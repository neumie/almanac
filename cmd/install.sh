#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local claude_dir="$HOME/.claude"
  local plugins_dir="$claude_dir/plugins"
  local marketplaces_file="$plugins_dir/known_marketplaces.json"
  local plugins_file="$plugins_dir/installed_plugins.json"
  local settings_file="$claude_dir/settings.json"
  local marketplace_name="almanac"
  local plugin_key="almanac@almanac"
  local marketplace_dir="$plugins_dir/marketplaces/almanac"
  local repo_url="https://github.com/neumie/almanac.git"

  [[ -d "$claude_dir" ]] || _die "~/.claude not found — is Claude Code installed?"
  [[ -f "$PROVIDER_DIR/.claude-plugin/plugin.json" ]] || _die ".claude-plugin/plugin.json not found"

  # 1. Register almanac as a custom marketplace
  mkdir -p "$plugins_dir"
  [[ -f "$marketplaces_file" ]] || echo '{}' > "$marketplaces_file"

  python3 -c "
import json
with open('$marketplaces_file', 'r') as f:
    data = json.load(f)
data['$marketplace_name'] = {
    'source': {
        'source': 'github',
        'repo': 'neumie/almanac'
    },
    'installLocation': '$marketplace_dir'
}
with open('$marketplaces_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  # 2. Clone or update the marketplace repo
  if [[ -d "$marketplace_dir/.git" ]]; then
    _info "Updating marketplace clone..."
    git -C "$marketplace_dir" pull --ff-only --quiet 2>/dev/null || true
  else
    _info "Cloning marketplace..."
    rm -rf "$marketplace_dir"
    git clone --quiet "$repo_url" "$marketplace_dir" 2>/dev/null || \
      _die "Failed to clone $repo_url — check your network connection"
  fi

  # 3. Read version and copy plugin to cache
  local version
  version=$(python3 -c "import json; print(json.load(open('$PROVIDER_DIR/.claude-plugin/plugin.json'))['version'])")
  local cache_dir="$plugins_dir/cache/almanac/almanac/$version"
  rm -rf "$cache_dir"
  mkdir -p "$cache_dir"
  cp -R "$marketplace_dir/providers/claude-code/." "$cache_dir/"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  local sha
  sha=$(git -C "$marketplace_dir" rev-parse HEAD 2>/dev/null || echo "0000000000000000000000000000000000000000")

  # 4. Register plugin in installed_plugins.json
  [[ -f "$plugins_file" ]] || echo '{"version":2,"plugins":{}}' > "$plugins_file"

  python3 -c "
import json
with open('$plugins_file', 'r') as f:
    data = json.load(f)
# Clean up stale entries
for old_key in ['almanac@local', 'almanac@claude-plugins-official']:
    data['plugins'].pop(old_key, None)
data['plugins']['$plugin_key'] = [{
    'scope': 'user',
    'installPath': '$cache_dir',
    'version': '$version',
    'installedAt': '$now',
    'lastUpdated': '$now',
    'gitCommitSha': '$sha'
}]
with open('$plugins_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  # 5. Enable in settings
  [[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

  python3 -c "
import json
with open('$settings_file', 'r') as f:
    data = json.load(f)
ep = data.setdefault('enabledPlugins', {})
# Clean up stale entries
for old_key in ['almanac@local', 'almanac@claude-plugins-official']:
    ep.pop(old_key, None)
ep['$plugin_key'] = True
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  # 6. Clean up old cache dirs
  rm -rf "$plugins_dir/cache/claude-plugins-official/almanac" 2>/dev/null || true

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
