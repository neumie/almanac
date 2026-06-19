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

# Bold section heading for human-facing listings (help, doctor, list). Use this
# instead of `echo -e "${_BOLD}…${_RESET}"`; colors auto-disable off a TTY (see
# the color block above) so piped/captured output stays clean.
_heading() { printf '%b\n' "${_BOLD}$*${_RESET}"; }

# --- Arg parsing: required-value guard -------------------------------------
# DRY replacement for the repeated `shift; [ $# -gt 0 ] || _die …` dance in the
# cmd/*.sh option loops. Call it the moment a `--flag VALUE` option matches,
# BEFORE shifting, passing the loop's current arg count ($#) — which still
# includes the flag, so a present value means count >= 2. _die runs in the
# current shell (never a subshell), so its exit actually aborts the command:
#   --goal) _need_value --goal "$#"; GOAL="$2"; shift 2 ;;
# It does not reject values that begin with '-' — free-text flags (--prompt,
# --goal) legitimately take leading-dash values; that is the parser's job.
_need_value() {
  local flag="$1" remaining="${2:-0}"
  [ "$remaining" -ge 2 ] || _die "Missing value for $flag"
}

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

# --- Command registry ------------------------------------------------------
# The CLI command set is the set of files in cmd/ — single source of truth for
# dispatch (bin/almanac), help generation (cmd/help.sh), and the CLI tests.
# Mirrors almanac_providers globbing providers/: adding a command is one new
# file in cmd/, no edits to the dispatcher or help text. One name per line,
# alphabetical (glob order).
almanac_list_commands() {
  local f name
  for f in "$ALMANAC_HOME"/cmd/*.sh; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .sh)"
    printf '%s\n' "$name"
  done
}

# Read one metadata field from a command file's self-describing header. Each
# cmd/<name>.sh declares `# summary:`, `# usage:`, and `# group:` comment lines
# near the top; help generation and tests read them so the printed help can
# never drift from the actual command. Echoes the first match (empty if absent).
almanac_command_meta() {
  # Split the dependent assignment: bash 3.2 (macOS stock) evaluates every RHS in
  # a single `local` before binding any name, so `$name` in a combined
  # `local name=… file=…$name…` would resolve to the *caller's* name, not "$1".
  local name="$1" field="$2"
  local file="$ALMANAC_HOME/cmd/$name.sh"
  [[ -f "$file" ]] || return 1
  sed -n "s/^# ${field}:[[:space:]]*//p" "$file" | head -1
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

# Check if a provider is installed (return 0 = yes, 1 = no).
#
# Each installable provider declares its install marker — the path that exists
# iff almanac is installed for that provider — as the first line of
# providers/<name>/install-marker. A leading `~` is expanded to $HOME. Providers
# without a marker file are treated as not-installed (e.g. _shared, or a future
# README-only provider that has no detectable filesystem footprint).
#
# Keeping the marker path next to its provider means adding a new installable
# provider is a one-file change (`mkdir providers/foo && echo '~/.foo' >
# providers/foo/install-marker`) — no edits to core.sh.
_is_installed() {
  local provider="$1"
  local marker_file="$ALMANAC_HOME/providers/$provider/install-marker"
  [[ -f "$marker_file" ]] || return 1
  local marker
  IFS= read -r marker < "$marker_file" || return 1
  [[ -n "$marker" ]] || return 1
  marker="${marker/#\~/$HOME}"
  [[ -e "$marker" ]]
}
