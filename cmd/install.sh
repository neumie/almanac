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

  # 2. Create shell wrapper that loads almanac as a local plugin
  local wrapper="$HOME/.local/bin/claude-almanac"
  mkdir -p "$(dirname "$wrapper")"
  cat > "$wrapper" <<WRAPPER
#!/usr/bin/env bash
exec claude --plugin-dir "$plugin_dir" "\$@"
WRAPPER
  chmod +x "$wrapper"

  _success "Installed almanac for Claude Code"
  _info "Use 'claude-almanac' to start Claude Code with almanac skills"
  _info "Or: claude --plugin-dir $plugin_dir"
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
