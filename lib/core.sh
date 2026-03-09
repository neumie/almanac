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
