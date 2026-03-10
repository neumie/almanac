#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local commands_dir="$HOME/.claude/commands"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  mkdir -p "$commands_dir"

  # Symlink each skill's SKILL.md into ~/.claude/commands/<name>.md
  local count=0
  for dir in "$ALMANAC_HOME"/skills/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")
    local target="$commands_dir/$name.md"

    # Remove existing (symlink or file)
    [[ -L "$target" || -f "$target" ]] && rm "$target"

    ln -s "$dir/SKILL.md" "$target"
    count=$((count + 1))
  done

  _success "Installed $count skills into ~/.claude/commands/"
  _info "Start claude as usual — almanac skills are loaded automatically"
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
