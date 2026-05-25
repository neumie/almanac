#!/usr/bin/env bash
# core.sh — Shared CLI utilities for almanac

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
  _BOLD="\033[1m"
  _RED="\033[31m"
  _GREEN="\033[32m"
  _YELLOW="\033[33m"
  _BLUE="\033[34m"
  _RESET="\033[0m"
else
  _BOLD="" _RED="" _GREEN="" _YELLOW="" _BLUE="" _RESET=""
fi

_info()    { echo -e "${_BLUE}[info]${_RESET} $*"; }
_success() { echo -e "${_GREEN}[ok]${_RESET} $*"; }
_warn()    { echo -e "${_YELLOW}[warn]${_RESET} $*"; }
_error()   { echo -e "${_RED}[error]${_RESET} $*" >&2; }
_die()     { _error "$@"; exit 1; }

# Providers with adapters
almanac_providers() {
  for dir in "$ALMANAC_HOME"/providers/*/; do
    [[ -d "$dir" ]] && basename "$dir"
  done
}

# Optional-dependency detection. `gum` (Charm) styles the harden/ralph
# dashboards and HITL prompts; it is optional — the CLI degrades to plain output
# when absent. This is a pure binary-presence check (unlike the runtime
# TTY-gated almanac_loop_ui_has_gum), so install/doctor can report it.
almanac_gum_present() { command -v gum >/dev/null 2>&1; }

# Report gum presence/absence with an actionable hint. Used by `almanac doctor`
# and the installers so users learn the dashboard is gum-styled and optional.
almanac_report_gum() {
  if almanac_gum_present; then
    _success "gum: installed ($(command -v gum)) — dashboards render styled"
  else
    _warn "gum: not found — harden/ralph dashboards degrade to plain output"
    _info "Install gum (optional) for styled dashboards: https://github.com/charmbracelet/gum"
  fi
}

# Check if a provider is installed (return 0 = yes, 1 = no)
_is_installed() {
  local provider="$1"
  case "$provider" in
    claude-code)
      [[ -d "$HOME/.claude/commands/almanac" ]]
      ;;
    opencode)
      [[ -e "$HOME/.config/opencode/skills/almanac" ]]
      ;;
    cursor)
      [[ -e "$HOME/.cursor/skills/almanac" ]]
      ;;
    codex)
      [[ -e "$HOME/.agents/skills/almanac" ]]
      ;;
    *)
      return 1
      ;;
  esac
}
