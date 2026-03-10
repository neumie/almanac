#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local commands_dir="$HOME/.claude/commands/almanac"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  mkdir -p "$commands_dir"

  # Symlink each skill's SKILL.md into ~/.claude/commands/almanac/<name>.md
  local count=0
  for dir in "$ALMANAC_HOME"/skills/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")
    local target="$commands_dir/$name.md"

    # Remove existing (symlink or file)
    [[ -L "$target" || -f "$target" ]] && rm "$target"

    # Clean up legacy flat symlink from older installs
    local legacy="$HOME/.claude/commands/$name.md"
    [[ -L "$legacy" ]] && rm "$legacy"

    ln -s "$dir/SKILL.md" "$target"
    count=$((count + 1))
  done

  _success "Installed $count skills into ~/.claude/commands/almanac/"
  _info "Skills appear as almanac:<name> — start claude as usual"
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
