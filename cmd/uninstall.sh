#!/usr/bin/env bash
# uninstall.sh — Remove almanac from a specific provider.
# summary: Remove almanac from a provider
# usage: almanac uninstall <provider>
# group: providers

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"
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

  # Remove skill resource links (newer installs use a real almanac dir containing
  # one symlink per skill; older installs used one almanac dir symlink).
  local skills_link="$HOME/.claude/skills/almanac"
  if [[ -L "$skills_link" ]] && [[ "$(readlink "$skills_link")" == *almanac* ]]; then
    rm "$skills_link"
    _info "Removed skill resource link ~/.claude/skills/almanac"
  elif [[ -d "$skills_link" ]]; then
    while IFS= read -r dir; do
      [ -f "$dir/SKILL.md" ] || continue
      local name
      name=$(basename "$dir")
      local skill_target="$skills_link/$name"
      if [[ -L "$skill_target" ]] && [[ "$(readlink "$skill_target")" == *almanac* ]]; then
        rm "$skill_target"
      fi
    done < <(almanac_list_skills)
    rmdir "$skills_link" 2>/dev/null || true
    _info "Removed skill resource links from ~/.claude/skills/almanac/"
  fi

  # Remove CLAUDE.md symlink if it's ours (direct -> almanac, or legacy hop -> AGENTS.md)
  local claude_md="$HOME/.claude/CLAUDE.md"
  if [[ -L "$claude_md" ]]; then
    local link
    link="$(readlink "$claude_md")"
    if [[ "$link" == *almanac* || "$link" == "AGENTS.md" ]]; then
      rm "$claude_md"
      _info "Removed CLAUDE.md symlink from ~/.claude/"
    fi
  fi

  # Migration: older almanac versions also installed ~/.claude/AGENTS.md as a
  # symlink-hop intermediary. Remove it if present and points to almanac.
  local legacy_agents_md="$HOME/.claude/AGENTS.md"
  if [[ -L "$legacy_agents_md" ]] && [[ "$(readlink "$legacy_agents_md")" == *almanac* ]]; then
    rm "$legacy_agents_md"
    _info "Removed legacy AGENTS.md symlink from ~/.claude/"
  fi

  # Clean up legacy plugin registry entries (from older installs)
  local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"
  local settings="$HOME/.claude/settings.json"

  if [[ -f "$installed_plugins" ]] && grep -q 'almanac@local' "$installed_plugins"; then
    python3 - "$installed_plugins" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data.get('plugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
PY
    _info "Removed legacy almanac@local from installed_plugins.json"
  fi

  if [[ -f "$settings" ]] && grep -q 'almanac@local' "$settings"; then
    python3 - "$settings" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data.get('enabledPlugins', {}).pop('almanac@local', None)
json.dump(data, open(path, 'w'), indent=2)
PY
    _info "Removed legacy almanac@local from settings.json"
  fi

  # Clean up legacy alias from shell rc (from older installs)
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]] && grep -q 'plugin-dir.*almanac' "$rc"; then
      python3 - "$rc" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).readlines()
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
open(path, 'w').write(''.join(out))
PY
      _info "Removed legacy alias from $rc"
    fi
  done

  _success "Uninstalled almanac from Claude Code"
}

_shared_current_link_exists() {
  local skills_dir="$1"
  local dir name target

  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    target="$skills_dir/$name"
    [[ -L "$target" ]] || continue
    [[ "$(readlink "$target")" == "$dir" ]] && return 0
  done < <(almanac_list_skills)
  return 1
}

_shared_owner_remains() {
  local owners_dir="$1"
  local marker

  for marker in "$owners_dir"/*; do
    [[ -f "$marker" ]] && return 0
  done
  return 1
}

_remove_shared_agent_skills() {
  local owner="$1"
  local skills_dir="$HOME/.agents/skills/almanac"
  local state_dir="$skills_dir/.almanac-install"
  local owners_dir="$state_dir/owners"
  local manifest="$state_dir/manifest.tsv"
  local dir name expected_target target marker

  REMOVED_SHARED_SKILL_COUNT=0
  SHARED_SKILLS_RETAINED=false

  # A state-less shared install predates Pi support and therefore belongs to
  # Codex. A Pi uninstall must not claim or remove it.
  if [[ "$owner" == "pi" && ! -d "$owners_dir" ]]; then
    if [[ -L "$skills_dir" ]] || _shared_current_link_exists "$skills_dir"; then
      SHARED_SKILLS_RETAINED=true
      return
    fi
  fi

  # Older Codex installs used one directory symlink. Remove only the exact
  # source for this checkout, never a path that merely contains "almanac".
  if [[ -L "$skills_dir" ]]; then
    if [[ "$owner" == "codex" && "$(readlink "$skills_dir")" == "$ALMANAC_HOME/skills" ]]; then
      rm "$skills_dir"
      _info "Removed legacy skill resource link ~/.agents/skills/almanac"
    else
      SHARED_SKILLS_RETAINED=true
    fi
    return
  fi

  if [[ -d "$owners_dir" ]]; then
    marker="$owners_dir/$owner"
    if [[ ! -f "$marker" ]]; then
      SHARED_SKILLS_RETAINED=true
      return
    fi
    rm "$marker"
    if _shared_owner_remains "$owners_dir"; then
      SHARED_SKILLS_RETAINED=true
      return
    fi
  fi

  if [[ -f "$manifest" ]]; then
    while IFS=$'\t' read -r name expected_target; do
      [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
      target="$skills_dir/$name"
      [[ -L "$target" ]] || continue
      [[ "$(readlink "$target")" == "$expected_target" ]] || continue
      rm "$target"
      REMOVED_SHARED_SKILL_COUNT=$((REMOVED_SHARED_SKILL_COUNT + 1))
    done < "$manifest"
  else
    # Backward-compatible cleanup for old Codex installs: exact current source
    # targets only. Moved or foreign links are intentionally left untouched.
    while IFS= read -r dir; do
      dir="${dir%/}"
      [ -f "$dir/SKILL.md" ] || continue
      name=$(basename "$dir")
      target="$skills_dir/$name"
      [[ -L "$target" ]] || continue
      [[ "$(readlink "$target")" == "$dir" ]] || continue
      rm "$target"
      REMOVED_SHARED_SKILL_COUNT=$((REMOVED_SHARED_SKILL_COUNT + 1))
    done < <(almanac_list_skills)
  fi

  [[ -f "$manifest" ]] && rm "$manifest"
  [[ -d "$owners_dir" ]] && rmdir "$owners_dir" 2>/dev/null || true
  [[ -d "$state_dir" ]] && rmdir "$state_dir" 2>/dev/null || true
  [[ -d "$skills_dir" ]] && rmdir "$skills_dir" 2>/dev/null || true
}

_uninstall_codex() {
  local legacy_skills_dir="$HOME/.codex/skills/almanac"
  local prompts_dir="$HOME/.codex/prompts"
  local dir name target

  _remove_shared_agent_skills codex
  if [[ "$SHARED_SKILLS_RETAINED" == true ]]; then
    _info "Kept shared skill links for another installed harness"
  else
    _info "Removed $REMOVED_SHARED_SKILL_COUNT skill symlinks from ~/.agents/skills/almanac/"
  fi

  local legacy_count=0
  if [[ -L "$legacy_skills_dir" && "$(readlink "$legacy_skills_dir")" == "$ALMANAC_HOME/skills" ]]; then
    rm "$legacy_skills_dir"
    _info "Removed legacy skill resource link ~/.codex/skills/almanac"
  elif [[ -d "$legacy_skills_dir" ]]; then
    while IFS= read -r dir; do
      dir="${dir%/}"
      [ -f "$dir/SKILL.md" ] || continue
      name=$(basename "$dir")
      target="$legacy_skills_dir/$name"
      [[ -L "$target" ]] || continue
      [[ "$(readlink "$target")" == "$dir" ]] || continue
      rm "$target"
      legacy_count=$((legacy_count + 1))
    done < <(almanac_list_skills)
  fi

  [[ -d "$legacy_skills_dir" ]] && rmdir "$legacy_skills_dir" 2>/dev/null || true
  [[ "$legacy_count" -gt 0 ]] && _info "Removed $legacy_count legacy skill symlinks from ~/.codex/skills/almanac/"

  local prompt_count=0
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    target="$prompts_dir/$name.md"

    [[ -L "$target" ]] || continue
    [[ "$(readlink "$target")" == "$dir/SKILL.md" ]] || continue
    rm "$target"
    prompt_count=$((prompt_count + 1))
  done < <(almanac_list_skills)

  [[ -d "$prompts_dir" ]] && rmdir "$prompts_dir" 2>/dev/null || true

  _info "Removed $prompt_count slash prompt symlinks from ~/.codex/prompts/"

  # Remove global AGENTS.md only when it points to this checkout's source.
  local agents_md="$HOME/.codex/AGENTS.md"
  local agents_source="$ALMANAC_HOME/providers/_shared/AGENTS.md"
  if [[ -L "$agents_md" ]] && [[ "$(readlink "$agents_md")" == "$agents_source" ]]; then
    rm "$agents_md"
    _info "Removed AGENTS.md symlink from ~/.codex/"
  fi

  _success "Uninstalled almanac from Codex"
}

_uninstall_pi() {
  _remove_shared_agent_skills pi
  if [[ "$SHARED_SKILLS_RETAINED" == true ]]; then
    _info "Kept shared skill links for Codex or another installer"
  else
    _info "Removed $REMOVED_SHARED_SKILL_COUNT skill symlinks from ~/.agents/skills/almanac/"
  fi
  _success "Uninstalled almanac from Pi"
}

# --- main ---

case "${1:-}" in
  -h|--help) printf '%s\n' "Usage: almanac uninstall <provider>"; exit 0 ;;
esac

PROVIDER="${1:-}"
[[ -n "$PROVIDER" ]] || _die "Usage: almanac uninstall <provider>"
[[ "$#" -le 1 ]] || _die "Unexpected argument: $2 (one provider at a time)"

PROVIDER_DIR="$ALMANAC_HOME/providers/$PROVIDER"
[[ -d "$PROVIDER_DIR" ]] || _die "Unknown provider: $PROVIDER (run 'almanac list')"

case "$PROVIDER" in
  claude-code)
    _uninstall_claude_code
    ;;
  codex)
    _uninstall_codex
    ;;
  pi)
    _uninstall_pi
    ;;
  *)
    _warn "No uninstaller for $PROVIDER — remove manually"
    ;;
esac
