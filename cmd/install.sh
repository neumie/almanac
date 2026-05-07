#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

source "$ALMANAC_HOME/lib/almanac-core.sh"

_install_claude_code() {
  local commands_dir="$HOME/.claude/commands/almanac"
  local skills_dir="$HOME/.claude/skills/almanac"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  mkdir -p "$commands_dir" "$skills_dir"

  # Migrate from old layout: ~/.claude/skills/almanac as a single dir-symlink
  # to skills/. Replace with a real directory of per-skill flat symlinks.
  if [[ -L "$skills_dir" ]]; then
    rm "$skills_dir"
    mkdir -p "$skills_dir"
  fi

  almanac_validate_unique_names || _die "duplicate skill names — fix before installing"

  # Per-skill flat symlinks. Skills live nested at skills/<category>/<name>/
  # but install flat so Claude Code's flat skill discovery finds them.
  local count=0
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")

    # Slash command symlink (per-file)
    local cmd_target="$commands_dir/$name.md"
    [[ -L "$cmd_target" || -f "$cmd_target" ]] && rm "$cmd_target"
    local legacy="$HOME/.claude/commands/$name.md"
    [[ -L "$legacy" ]] && rm "$legacy"
    ln -s "$dir/SKILL.md" "$cmd_target"

    # Skill directory symlink (per-dir, so scripts/ + references/ resolve)
    local skill_target="$skills_dir/$name"
    [[ -L "$skill_target" || -e "$skill_target" ]] && rm -rf "$skill_target"
    ln -s "$dir" "$skill_target"

    count=$((count + 1))
  done < <(almanac_list_skills)

  # Clean up dangling slash-command symlinks (from deleted skills)
  for link in "$commands_dir"/*.md; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] || rm "$link"
  done

  # Clean up dangling skill-dir symlinks
  for link in "$skills_dir"/*; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] || rm "$link"
  done

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
  _success "Linked $count skill dirs at ~/.claude/skills/almanac/<name>"
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

_install_codex() {
  local skills_dir="$HOME/.agents/skills/almanac"
  local legacy_skills_dir="$HOME/.codex/skills/almanac"
  local legacy_prompts_dir="$HOME/.codex/prompts"

  [[ -d "$HOME/.codex" ]] || _die "~/.codex not found — is Codex installed?"
  mkdir -p "$skills_dir"

  # Migrate from old layout: ~/.agents/skills/almanac as a single dir-symlink
  # to skills/. Replace with a real directory of per-skill flat symlinks.
  if [[ -L "$skills_dir" ]]; then
    rm "$skills_dir"
    mkdir -p "$skills_dir"
  fi

  almanac_validate_unique_names || _die "duplicate skill names — fix before installing"

  local count=0
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")

    local skill_target="$skills_dir/$name"
    [[ -L "$skill_target" || -e "$skill_target" ]] && rm -rf "$skill_target"
    ln -s "$dir" "$skill_target"

    count=$((count + 1))
  done < <(almanac_list_skills)

  # Clean up dangling skill-dir symlinks from deleted skills.
  for link in "$skills_dir"/*; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] || rm "$link"
  done

  # Clean up legacy Codex install locations from older almanac versions.
  for link in "$legacy_skills_dir"/*; do
    [[ -L "$link" ]] || continue
    [[ "$(readlink "$link")" == *almanac* ]] || continue
    rm "$link"
  done
  [[ -d "$legacy_skills_dir" ]] && rmdir "$legacy_skills_dir" 2>/dev/null || true

  for link in "$legacy_prompts_dir"/*.md; do
    [[ -L "$link" ]] || continue
    [[ "$(readlink "$link")" == *almanac* ]] || continue
    rm "$link"
  done
  [[ -d "$legacy_prompts_dir" ]] && rmdir "$legacy_prompts_dir" 2>/dev/null || true

  _success "Linked $count skill dirs at ~/.agents/skills/almanac/<name>"
  _info "Skills can be invoked as \$<name> or from /skills — restart codex to reload"
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
    if [[ "$PROVIDER" == "codex" ]]; then
      _install_codex
    else
      _install_symlink "$PROVIDER"
    fi
    ;;
  *)
    _die "No installer for provider: $PROVIDER"
    ;;
esac
