#!/usr/bin/env bash
# help.sh — Show almanac CLI usage, generated from the command registry.
# summary: Show this help
# usage: almanac help
# group: other
#
# Nothing here hard-codes the command list: it walks almanac_list_commands and
# reads each command's self-declared `# summary:` and `# group:` header, so the
# printed help can never drift from cmd/. For full per-command detail and flags,
# `almanac <command> --help`.

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"

# Print every command tagged with GROUP under LABEL, aligned. Silent if the
# group is empty, so the section only appears when it has members.
_help_print_group() {
  local want="$1" label="$2" name group summary shown=0
  while IFS= read -r name; do
    group="$(almanac_command_meta "$name" group || true)"
    [ "${group:-other}" = "$want" ] || continue
    [ "$shown" -eq 0 ] && { printf '%s\n' "$label"; shown=1; }
    summary="$(almanac_command_meta "$name" summary || true)"
    printf '  %-24s %s\n' "$name" "$summary"
  done < <(almanac_list_commands)
  [ "$shown" -eq 1 ] && printf '\n'
  return 0
}

_heading "almanac — agent toolkit CLI"
printf '\n'
printf 'Usage: almanac <command> [args]\n'
printf "Run 'almanac <command> --help' for details and flags on any command.\n\n"
printf '  %-24s %s\n\n' "(no command)" "Open the loop hub on a TTY; else print this help"

# Section order is curated; the members of each section are not.
_help_print_group loops       "Loops:"
_help_print_group providers   "Providers:"
_help_print_group maintenance "Maintenance:"
_help_print_group other       "Other:"
