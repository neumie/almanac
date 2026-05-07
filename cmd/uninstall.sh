#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider

source "$ALMANAC_HOME/lib/almanac-core.sh"

_uninstall_claude_code() {
  local commands_dir="$HOME/.claude/commands/almanac"

  # Remove skill symlinks from ~/.claude/commands/almanac/
  local count=0
  while IFS= read -r dir; do
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")
    local target="$commands_dir/$name.md"

    if [[ -L "$target" ]]; then
      rm "$target"
      count=$((count + 1))
    fi

    # Also clean up legacy flat symlink
    local legacy="$HOME/.claude/commands/$name.md"
    [[ -L "$legacy" ]] && rm "$legacy"
  done < <(almanac_list_skills)

  # Remove almanac directory if empty
  [[ -d "$commands_dir" ]] && rmdir "$commands_dir" 2>/dev/null || true

  _info "Removed $count skill symlinks from ~/.claude/commands/almanac/"

  # Remove skills resource symlink (added in newer installs)
  local skills_link="$HOME/.claude/skills/almanac"
  if [[ -L "$skills_link" ]] && [[ "$(readlink "$skills_link")" == *almanac* ]]; then
    rm "$skills_link"
    _info "Removed skill resource link ~/.claude/skills/almanac"
  fi

  # Remove CLAUDE.md symlink if it points to almanac
  local claude_md="$HOME/.claude/CLAUDE.md"
  if [[ -L "$claude_md" ]] && [[ "$(readlink "$claude_md")" == *almanac* ]]; then
    rm "$claude_md"
    _info "Removed CLAUDE.md symlink from ~/.claude/"
  fi

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

_uninstall_codex() {
  local skills_dir="$HOME/.agents/skills/almanac"
  local legacy_skills_dir="$HOME/.codex/skills/almanac"
  local prompts_dir="$HOME/.codex/prompts"

  if [[ -L "$skills_dir" ]] && [[ "$(readlink "$skills_dir")" == *almanac* ]]; then
    rm "$skills_dir"
    _info "Removed legacy skill resource link ~/.agents/skills/almanac"
  fi

  if [[ -L "$legacy_skills_dir" ]] && [[ "$(readlink "$legacy_skills_dir")" == *almanac* ]]; then
    rm "$legacy_skills_dir"
    _info "Removed legacy skill resource link ~/.codex/skills/almanac"
  fi

  local count=0
  for target in "$skills_dir"/*; do
    [[ -L "$target" ]] || continue
    [[ "$(readlink "$target")" == *almanac* ]] || continue
    rm "$target"
    count=$((count + 1))
  done

  [[ -d "$skills_dir" ]] && rmdir "$skills_dir" 2>/dev/null || true

  _info "Removed $count skill symlinks from ~/.agents/skills/almanac/"

  local legacy_count=0
  for target in "$legacy_skills_dir"/*; do
    [[ -L "$target" ]] || continue
    [[ "$(readlink "$target")" == *almanac* ]] || continue
    rm "$target"
    legacy_count=$((legacy_count + 1))
  done

  [[ -d "$legacy_skills_dir" ]] && rmdir "$legacy_skills_dir" 2>/dev/null || true
  [[ "$legacy_count" -gt 0 ]] && _info "Removed $legacy_count legacy skill symlinks from ~/.codex/skills/almanac/"

  local prompt_count=0
  while IFS= read -r dir; do
    [ -f "$dir/SKILL.md" ] || continue
    local name
    name=$(basename "$dir")
    local target="$prompts_dir/$name.md"

    [[ -L "$target" ]] || continue
    [[ "$(readlink "$target")" == *almanac* ]] || continue
    rm "$target"
    prompt_count=$((prompt_count + 1))
  done < <(almanac_list_skills)

  [[ -d "$prompts_dir" ]] && rmdir "$prompts_dir" 2>/dev/null || true

  _info "Removed $prompt_count slash prompt symlinks from ~/.codex/prompts/"
  _success "Uninstalled almanac from Codex"
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
  codex)
    _uninstall_codex
    ;;
  *)
    _warn "No uninstaller for $PROVIDER — remove manually"
    ;;
esac
