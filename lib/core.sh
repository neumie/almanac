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

# --- ALMANAC_HOME resolution -----------------------------------------------
# Canonical resolver and single source of truth for locating the real repo root
# from an entry point. Prefer an already-exported ALMANAC_HOME; otherwise resolve
# the caller's own path to its physical directory (pwd -P, so the install
# dir-symlink ~/.claude/skills/almanac/<name> -> repo/skills/<category>/<name>
# and a plain checkout both land on the real repo) and climb <depth> parents to
# the repo root.
#
# Entry points can't call this until core.sh is sourced, so each inlines an
# identical one-line bootstrap that mirrors it (the standardized snippet):
#   ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/<REL>" && pwd -P)}"
# where <REL> is the file's known depth below the root (bin/ -> "..",
# skills/<cat>/<name>/scripts/ -> "../../../.."). Keep snippet and function in
# sync; this function is the tested form (tests/test-home-resolve.sh).
almanac_resolve_home() {
  local src="${1:?almanac_resolve_home: source path required}" depth="${2:-0}"
  if [ -n "${ALMANAC_HOME:-}" ]; then
    printf '%s\n' "$ALMANAC_HOME"
    return 0
  fi
  local home
  home="$(cd -P "$(dirname "$src")" && pwd -P)"
  while [ "$depth" -gt 0 ]; do
    home="$(dirname "$home")"
    depth=$((depth - 1))
  done
  printf '%s\n' "$home"
}

# --- Sibling-source helper -------------------------------------------------
# Idempotently source a sibling lib/ file from the caller's directory.
# Usage (from inside lib/<some-module>.sh, after core.sh has been sourced):
#   _almanac_source_sibling <basename.sh> <guard_function>
# If <guard_function> already exists, returns 0 without sourcing — so the same
# module can be pulled in via multiple paths (bin/almanac, a test sourcing it
# directly, transitive sourcing) without re-defining its functions.
#
# The caller's directory is resolved via BASH_SOURCE[1] (the file that called
# this helper) with pwd -P, so the install-time symlink
# ~/.claude/skills/almanac/<name> → repo/skills/<cat>/<name> and a plain
# checkout both land on the real lib/.
#
# Replaces the verbose five-line idiom that used to live at the top of every
# consumer module (`if ! declare -F X; then __dir=…; source …; unset __dir; fi`).
# Lives in core.sh because every consumer of this helper already depends on
# core.sh; modules that deliberately have NO core.sh dependency (run.sh, ui.sh,
# loops.sh, agent.sh) keep the literal snippet instead.
_almanac_source_sibling() {
  local module="$1"
  local guard_fn="$2"
  declare -F "$guard_fn" >/dev/null 2>&1 && return 0
  local caller_dir
  caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd -P)"
  # shellcheck source=/dev/null
  source "$caller_dir/$module"
}

# Providers with adapters
almanac_providers() {
  local provider
  for dir in "$ALMANAC_HOME"/providers/*/; do
    [[ -d "$dir" ]] || continue
    provider="$(basename "$dir")"
    [[ "$provider" == _* ]] && continue
    printf '%s\n' "$provider"
  done
}

# Optional-dependency detection. `gum` (Charm) styles loop
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
    _warn "gum: not found — loop dashboards degrade to plain output"
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
