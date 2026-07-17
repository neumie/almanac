#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider.
# summary: Install almanac for a provider (e.g. claude-code)
# usage: almanac install <provider> [--global-config]
# group: providers

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"
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

  # Symlink global CLAUDE.md -> canonical AGENTS.md in the almanac repo.
  # The same source file is used by other providers (Codex installs it as
  # ~/.codex/AGENTS.md), keeping one source of truth across tools.
  local agents_md="$ALMANAC_HOME/providers/_shared/AGENTS.md"
  local claude_target="$HOME/.claude/CLAUDE.md"
  if [[ -f "$agents_md" ]]; then
    if [[ ! -e "$claude_target" && ! -L "$claude_target" ]]; then
      ln -s "$agents_md" "$claude_target"
      _success "Installed global CLAUDE.md -> ~/.claude/CLAUDE.md"
    elif [[ -L "$claude_target" ]] && { readlink "$claude_target" | grep -q "almanac" || [[ "$(readlink "$claude_target")" == "AGENTS.md" ]]; }; then
      # Recognise our own symlinks: direct (.../almanac/...) or legacy hop -> AGENTS.md
      rm "$claude_target"
      ln -s "$agents_md" "$claude_target"
      _success "Updated global CLAUDE.md -> ~/.claude/CLAUDE.md"
    elif [[ "$GLOBAL_CONFIG" == true ]]; then
      [[ -f "$claude_target" ]] && _warn "Replacing custom ~/.claude/CLAUDE.md with almanac version"
      [[ -L "$claude_target" || -f "$claude_target" ]] && rm "$claude_target"
      ln -s "$agents_md" "$claude_target"
      _success "Installed global CLAUDE.md -> ~/.claude/CLAUDE.md"
    else
      _info "Skipped ~/.claude/CLAUDE.md — custom file exists (use --global-config to override)"
    fi
  fi

  _success "Installed $count skills into ~/.claude/commands/almanac/"
  _success "Linked $count skill dirs at ~/.claude/skills/almanac/<name>"
  _info "Skills appear as almanac:<name> — start claude as usual"

  # Report optional deps (gum styles loop dashboards; optional).
  almanac_report_gum
}

_install_symlink() {
  local provider="$1"
  local readme="$ALMANAC_HOME/providers/$provider/README.md"
  if [[ -f "$readme" ]]; then
    _info "Follow the setup instructions:"
    printf '\n'
    cat "$readme"
  else
    _warn "No setup instructions for $provider"
  fi
}

_shared_manifest_owns() {
  local manifest="$1"
  local wanted_name="$2"
  local wanted_target="$3"
  local name target

  [[ -f "$manifest" ]] || return 1
  while IFS=$'\t' read -r name target; do
    [[ "$name" == "$wanted_name" && "$target" == "$wanted_target" ]] && return 0
  done < "$manifest"
  return 1
}

_shared_manifest_has_name() {
  local manifest="$1"
  local wanted_name="$2"
  local name target

  [[ -f "$manifest" ]] || return 1
  while IFS=$'\t' read -r name target; do
    [[ "$name" == "$wanted_name" ]] && return 0
  done < "$manifest"
  return 1
}

_shared_has_current_links() {
  local skills_dir="$1"
  local dir name skill_target

  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    skill_target="$skills_dir/$name"
    [[ -L "$skill_target" ]] || continue
    [[ "$(readlink "$skill_target")" == "$dir" ]] && return 0
  done < <(almanac_list_skills)
  return 1
}

_link_shared_agent_skills() {
  local owner="$1"
  local skills_dir="$HOME/.agents/skills/almanac"
  local state_dir="$skills_dir/.almanac-install"
  local owners_dir="$state_dir/owners"
  local manifest="$state_dir/manifest.tsv"
  local manifest_tmp="$state_dir/manifest.tsv.tmp.$$"
  local legacy_directory_link=false
  local infer_legacy_codex=false
  local dir name skill_target actual_target old_name old_target

  # Older installs used one directory symlink. Only migrate the exact Almanac
  # source for this checkout; never replace an unrelated shared-skills link.
  if [[ -L "$skills_dir" ]]; then
    [[ "$(readlink "$skills_dir")" == "$ALMANAC_HOME/skills" ]] || \
      _die "Refusing to replace non-Almanac skill directory: $skills_dir"
    rm "$skills_dir"
    legacy_directory_link=true
  fi
  mkdir -p "$skills_dir"

  almanac_validate_unique_names || _die "duplicate skill names — fix before installing"

  # Before Pi support, this shared location was owned by the Codex installer.
  # Preserve that ownership when a Pi install migrates an existing layout.
  if [[ "$owner" == "pi" && ! -d "$owners_dir" ]]; then
    if [[ "$legacy_directory_link" == true ]] || _shared_has_current_links "$skills_dir"; then
      infer_legacy_codex=true
    fi
  fi

  # Preflight every collision before changing any link. Exact manifest targets
  # permit moving between Almanac checkouts without trusting path substrings.
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    skill_target="$skills_dir/$name"
    [[ -e "$skill_target" || -L "$skill_target" ]] || continue
    [[ -L "$skill_target" ]] || \
      _die "Refusing to replace non-Almanac skill: $skill_target"
    actual_target=$(readlink "$skill_target")
    if [[ "$actual_target" != "$dir" ]] && \
       ! _shared_manifest_owns "$manifest" "$name" "$actual_target"; then
      _die "Refusing to replace non-Almanac skill link: $skill_target"
    fi
  done < <(almanac_list_skills)

  mkdir -p "$owners_dir"
  : > "$manifest_tmp"
  LINKED_SHARED_SKILL_COUNT=0
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    skill_target="$skills_dir/$name"

    if [[ -e "$skill_target" || -L "$skill_target" ]]; then
      [[ -L "$skill_target" ]] || \
        _die "Refusing to replace non-Almanac skill: $skill_target"
      actual_target=$(readlink "$skill_target")
      if [[ "$actual_target" != "$dir" ]] && \
         ! _shared_manifest_owns "$manifest" "$name" "$actual_target"; then
        _die "Refusing to replace non-Almanac skill link: $skill_target"
      fi
      rm "$skill_target"
    fi
    ln -s "$dir" "$skill_target"
    printf '%s\t%s\n' "$name" "$dir" >> "$manifest_tmp"
    LINKED_SHARED_SKILL_COUNT=$((LINKED_SHARED_SKILL_COUNT + 1))
  done < <(almanac_list_skills)

  # Remove deleted skills only when the prior manifest proves exact ownership.
  if [[ -f "$manifest" ]]; then
    while IFS=$'\t' read -r old_name old_target; do
      [[ "$old_name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
      _shared_manifest_has_name "$manifest_tmp" "$old_name" && continue
      skill_target="$skills_dir/$old_name"
      [[ -L "$skill_target" ]] || continue
      [[ "$(readlink "$skill_target")" == "$old_target" ]] || continue
      rm "$skill_target"
    done < "$manifest"
  fi

  mv "$manifest_tmp" "$manifest"
  [[ "$infer_legacy_codex" == true ]] && : > "$owners_dir/codex"
  : > "$owners_dir/$owner"
}

_install_codex() {
  local legacy_skills_dir="$HOME/.codex/skills/almanac"
  local legacy_prompts_dir="$HOME/.codex/prompts"
  local dir name link

  [[ -d "$HOME/.codex" ]] || _die "~/.codex not found — is Codex installed?"
  _link_shared_agent_skills codex

  # Clean up legacy Codex install locations from older Almanac versions.
  # Exact current source targets avoid deleting unrelated links.
  if [[ -L "$legacy_skills_dir" && "$(readlink "$legacy_skills_dir")" == "$ALMANAC_HOME/skills" ]]; then
    rm "$legacy_skills_dir"
  elif [[ -d "$legacy_skills_dir" ]]; then
    while IFS= read -r dir; do
      dir="${dir%/}"
      [ -f "$dir/SKILL.md" ] || continue
      name=$(basename "$dir")
      link="$legacy_skills_dir/$name"
      [[ -L "$link" ]] || continue
      [[ "$(readlink "$link")" == "$dir" ]] || continue
      rm "$link"
    done < <(almanac_list_skills)
    rmdir "$legacy_skills_dir" 2>/dev/null || true
  fi

  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    link="$legacy_prompts_dir/$name.md"
    [[ -L "$link" ]] || continue
    [[ "$(readlink "$link")" == "$dir/SKILL.md" ]] || continue
    rm "$link"
  done < <(almanac_list_skills)
  [[ -d "$legacy_prompts_dir" ]] && rmdir "$legacy_prompts_dir" 2>/dev/null || true

  _success "Linked $LINKED_SHARED_SKILL_COUNT skill dirs at ~/.agents/skills/almanac/<name>"
  _info "Skills can be invoked as \$<name> or from /skills — restart codex to reload"

  # Report optional deps (gum styles loop dashboards; optional).
  almanac_report_gum

  # Symlink global AGENTS.md (same canonical file used by claude-code).
  local agents_md="$ALMANAC_HOME/providers/_shared/AGENTS.md"
  local agents_target="$HOME/.codex/AGENTS.md"
  if [[ -f "$agents_md" ]]; then
    if [[ ! -e "$agents_target" && ! -L "$agents_target" ]]; then
      ln -s "$agents_md" "$agents_target"
      _success "Installed global AGENTS.md -> ~/.codex/AGENTS.md"
    elif [[ -L "$agents_target" ]] && [[ "$(readlink "$agents_target")" == "$agents_md" ]]; then
      rm "$agents_target"
      ln -s "$agents_md" "$agents_target"
      _success "Updated global AGENTS.md -> ~/.codex/AGENTS.md"
    elif [[ "$GLOBAL_CONFIG" == true ]]; then
      [[ -f "$agents_target" ]] && _warn "Replacing custom ~/.codex/AGENTS.md with almanac version"
      [[ -L "$agents_target" || -f "$agents_target" ]] && rm "$agents_target"
      ln -s "$agents_md" "$agents_target"
      _success "Installed global AGENTS.md -> ~/.codex/AGENTS.md"
    else
      _info "Skipped ~/.codex/AGENTS.md — custom file exists (use --global-config to override)"
    fi
  fi
}

_install_pi() {
  _link_shared_agent_skills pi

  _success "Linked $LINKED_SHARED_SKILL_COUNT skill dirs at ~/.agents/skills/almanac/<name>"
  _info "Skills can be invoked as /skill:<name> — run /reload in Pi to load them"

  # Report optional deps (gum styles loop dashboards; optional).
  almanac_report_gum
}

# --- main ---

GLOBAL_CONFIG=false
PROVIDER=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) printf '%s\n' "Usage: almanac install <provider> [--global-config]"; exit 0 ;;
    --global-config) GLOBAL_CONFIG=true ;;
    -*) _die "Unknown install option: $arg" ;;
    *)
      [[ -z "$PROVIDER" ]] || _die "Unexpected argument: $arg (one provider at a time)"
      PROVIDER="$arg"
      ;;
  esac
done

[[ -n "$PROVIDER" ]] || _die "Usage: almanac install <provider> [--global-config]"

PROVIDER_DIR="$ALMANAC_HOME/providers/$PROVIDER"
[[ -d "$PROVIDER_DIR" ]] || _die "Unknown provider: $PROVIDER (run 'almanac list')"

case "$PROVIDER" in
  claude-code)
    _install_claude_code
    ;;
  opencode|cursor|codex|pi)
    case "$PROVIDER" in
      codex) _install_codex ;;
      pi) _install_pi ;;
      *) _install_symlink "$PROVIDER" ;;
    esac
    ;;
  *)
    _die "No installer for provider: $PROVIDER"
    ;;
esac
