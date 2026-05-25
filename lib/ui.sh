#!/usr/bin/env bash
# ui.sh - gum-or-plain UI seam (the engine's only presentation layer)
#
# The supervision dashboard is a gum-styled redraw loop (PRD: bash + gum, no true
# TUI). Render LOGIC is kept pure (state -> printable rows) so it is unit-testable
# without a terminal; gum is only a styling layer wrapped around that text, and the
# CLI degrades to plain output when gum is absent — keeping almanac's near-zero-dep
# promise. Set ALMANAC_NO_GUM=1 to force plain output (tests, CI, scripts).
#
# Self-contained: these helpers use only printf/read/cat/gum and never call the
# _die/_info output helpers, so this file has no dependency on lib/core.sh. Every
# consumer (loop-core, the launcher, harden-core, the hub) sources it directly.

# True (0) only when gum styling should be used: gum is installed, stdout is a
# terminal, and the operator has not opted out via ALMANAC_NO_GUM. Piped/captured
# output is never styled, so callers and tests can assert on plain content.
almanac_loop_ui_has_gum() {
  [ -z "${ALMANAC_NO_GUM:-}" ] || return 1
  command -v gum >/dev/null 2>&1 || return 1
  [ -t 1 ] || return 1
  return 0
}

# Like almanac_loop_ui_has_gum, but for the interactive SELECTORS (choose / input
# / confirm). They are called inside `$( … )` to capture the chosen value, so
# their stdout is a pipe and `[ -t 1 ]` is ALWAYS false — which wrongly forced the
# plain menus even with gum installed on a real terminal. gum interacts via the
# controlling terminal, not stdout, so gate on stderr being a TTY (`[ -t 2 ]`):
# true inside command substitution on a real terminal, false when piped/captured
# (tests, scripts), so the plain fallback still kicks in off a TTY.
almanac_loop_ui_has_gum_interactive() {
  [ -z "${ALMANAC_NO_GUM:-}" ] || return 1
  command -v gum >/dev/null 2>&1 || return 1
  [ -t 2 ] || return 1
  return 0
}

# Style a block of text read from stdin: a rounded gum panel when gum styling is
# available, otherwise the text passed straight through. Presentation only; the
# content is identical either way, so the dashboard degrades gracefully and stays
# assertable.
almanac_loop_ui_render() {
  if almanac_loop_ui_has_gum; then
    gum style --border rounded --padding "0 1" "$(cat)"
  else
    cat
  fi
}

# Clear the terminal between redraw-loop frames — but ONLY when stdout is a TTY,
# so piped/captured output (tests, scripts, the hub reading a tail) is never
# polluted with clear escape sequences. A no-op off a terminal. Uses clear(1)
# when present, else the ANSI clear+home sequence.
almanac_loop_ui_clear() {
  [ -t 1 ] || return 0
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
  fi
}

# Pure state -> glyph mapping for a worker-health OR run-lifecycle state. Plain
# unicode, no color, no gum, so the dashboard/hub composer that calls it stays
# deterministic. Worker health: running/stalled/idle/looping/done/failed. Run
# lifecycle adds `stale` (a running entry whose pid is gone) and `aborted`.
almanac_loop_ui_status_glyph() {
  case "$1" in
    running) printf '%s\n' "●" ;;
    stalled) printf '%s\n' "◐" ;;
    stale)   printf '%s\n' "◌" ;;
    idle)    printf '%s\n' "○" ;;
    looping) printf '%s\n' "↻" ;;
    done)    printf '%s\n' "✔" ;;
    failed)  printf '%s\n' "✘" ;;
    aborted) printf '%s\n' "■" ;;
    *)       printf '%s\n' "•" ;;
  esac
}

# --- Interactive selection primitives (gum-or-plain) ---------------------------
#
# The interactive hub (and any other menu-driven flow) picks from a list, reads a
# free-text value, and asks yes/no. With gum those are gum choose/input/confirm;
# without gum they degrade to a plain numbered menu + `read`, so the menus work on
# any TTY — keeping almanac's near-zero-dep promise (PRD: "degrade gracefully when
# gum is absent"). The selection LOGIC is split into pure functions (menu_render,
# menu_pick) that are unit-testable off a terminal; the choose/input/confirm
# wrappers add only the gum-or-`read` I/O around them. Set ALMANAC_NO_GUM=1 to
# force the plain path (tests, CI, scripts).

# Pure: render OPTIONS as a 1-based numbered menu, one per line, to stdout. The
# plain-mode selector prints this; tests assert on it directly. No gum, no read.
almanac_loop_ui_menu_render() {
  local i=1 opt
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt"
    i=$((i + 1))
  done
}

# Pure: map a 1-based selection number to the chosen OPTION, echoed on stdout.
# Returns 1 for a blank, non-numeric, or out-of-range selection so the caller can
# treat it like a cancel. No gum, no read — the testable core of the plain chooser.
almanac_loop_ui_menu_pick() {
  local sel="$1"
  shift
  case "$sel" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$sel" -ge 1 ] && [ "$sel" -le "$#" ] || return 1
  shift "$((sel - 1))"
  printf '%s\n' "$1"
}

# Choose one of OPTIONS under HEADER. With gum styling available: `gum choose`.
# Without it: print the header + numbered menu to stderr, read a number from
# stdin, and map it to the option via the pure pick. Either way the chosen option
# is the ONLY thing on stdout (the prompt goes to stderr), so callers capture just
# the choice. Returns nonzero on cancel / EOF / bad input, mirroring gum choose's
# cancel exit so callers can `|| return` to go back.
almanac_loop_ui_choose() {
  local header="$1"
  shift
  local reply
  if almanac_loop_ui_has_gum_interactive; then
    printf '%s\n' "$@" | gum choose --header "$header"
    return
  fi
  printf '%s\n' "$header" >&2
  almanac_loop_ui_menu_render "$@" >&2
  printf 'Select [1-%d]: ' "$#" >&2
  read -r reply || return 1
  almanac_loop_ui_menu_pick "$reply" "$@"
}

# Prompt for a free-text value under HEADER, with an optional DEFAULT ($2). With
# gum: `gum input`. Without it: a plain `read` (empty input falls back to the
# default). The value is echoed on stdout; the prompt goes to stderr.
almanac_loop_ui_input() {
  local header="$1"
  local default="${2:-}"
  local reply
  if almanac_loop_ui_has_gum_interactive; then
    if [ -n "$default" ]; then
      gum input --header "$header" --value "$default"
    else
      gum input --header "$header"
    fi
    return
  fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$header" "$default" >&2
  else
    printf '%s: ' "$header" >&2
  fi
  read -r reply || reply=""
  [ -n "$reply" ] || reply="$default"
  printf '%s\n' "$reply"
}

# Yes/no confirm of PROMPT. With gum: `gum confirm`. Without it: a plain `read`,
# defaulting to yes on empty input to match gum confirm's affirmative-default
# button. Returns 0 for yes, 1 for no (gum confirm's exit semantics), so callers
# keep `gum confirm … || fallback` shape unchanged. Prompt goes to stderr.
almanac_loop_ui_confirm() {
  local prompt="$1"
  local reply
  if almanac_loop_ui_has_gum_interactive; then
    gum confirm "$prompt"
    return
  fi
  printf '%s [Y/n]: ' "$prompt" >&2
  read -r reply || reply=""
  case "$reply" in
    n|N|no|NO|No) return 1 ;;
    *) return 0 ;;
  esac
}
