#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local commands_dir="$HOME/.claude/commands/almanac"
  local skills_link="$HOME/.claude/skills/almanac"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  mkdir -p "$commands_dir"
  mkdir -p "$HOME/.claude/skills"

  # Symlink each skill's SKILL.md into ~/.claude/commands/almanac/<name>.md
  # (Provides slash invocation under the almanac: namespace.)
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

  # Clean up dangling symlinks (from deleted skills)
  for link in "$commands_dir"/*.md; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] || rm "$link"
  done

  # Directory symlink so skills resolve their own scripts/ and references/
  # subdirectories (the file-only commands/ symlink hides them from
  # ${CLAUDE_SKILL_DIR}-relative paths).
  if [[ -L "$skills_link" ]]; then
    rm "$skills_link"
  elif [[ -e "$skills_link" ]]; then
    _die "$skills_link exists and is not a symlink — refusing to overwrite"
  fi
  ln -s "$ALMANAC_HOME/skills" "$skills_link"

  # Symlink global CLAUDE.md (only if no custom one exists)
  local claude_md="$ALMANAC_HOME/providers/claude-code/CLAUDE.md"
  local claude_target="$HOME/.claude/CLAUDE.md"
  if [[ -f "$claude_md" ]]; then
    if [[ ! -e "$claude_target" && ! -L "$claude_target" ]]; then
      ln -s "$claude_md" "$claude_target"
      _success "Installed global CLAUDE.md -> ~/.claude/CLAUDE.md"
    elif [[ -L "$claude_target" ]] && readlink "$claude_target" | grep -q "almanac"; then
      rm "$claude_target"
      ln -s "$claude_md" "$claude_target"
      _success "Updated global CLAUDE.md -> ~/.claude/CLAUDE.md"
    elif [[ "$GLOBAL_CONFIG" == true ]]; then
      [[ -f "$claude_target" ]] && _warn "Replacing custom ~/.claude/CLAUDE.md with almanac version"
      [[ -L "$claude_target" || -f "$claude_target" ]] && rm "$claude_target"
      ln -s "$claude_md" "$claude_target"
      _success "Installed global CLAUDE.md -> ~/.claude/CLAUDE.md"
    else
      _info "Skipped ~/.claude/CLAUDE.md — custom file exists (use --global-config to override)"
    fi
  fi

  _success "Installed $count skills into ~/.claude/commands/almanac/"
  _success "Linked skill resources at ~/.claude/skills/almanac -> $ALMANAC_HOME/skills"
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

GLOBAL_CONFIG=false
PROVIDER=""
for arg in "$@"; do
  case "$arg" in
    --global-config) GLOBAL_CONFIG=true ;;
    -*) _die "Unknown flag: $arg" ;;
    *) PROVIDER="$arg" ;;
  esac
done

[[ -z "$PROVIDER" ]] && _die "Usage: almanac install <provider> [--global-config]"

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
