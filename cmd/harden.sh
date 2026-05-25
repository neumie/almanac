#!/usr/bin/env bash
# harden.sh - Bootstrap a harden-loop rubric for one target

set -euo pipefail

source "$ALMANAC_HOME/lib/harden-core.sh"

usage() {
  printf '%s\n' "Usage: almanac harden <target> --goal <goal>"
  printf '%s\n' ""
  printf '%s\n' "Creates docs/plans/harden/<target-slug>/rubric.md in the current repo."
}

TARGET=""
GOAL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -g|--goal)
      shift
      [ "$#" -gt 0 ] || _die "Missing value for --goal"
      GOAL="$1"
      ;;
    --)
      shift
      break
      ;;
    -*)
      _die "Unknown harden option: $1"
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        _die "Unexpected harden argument: $1"
      fi
      ;;
  esac
  shift
done

[ -n "$TARGET" ] || {
  usage
  _die "Missing harden target"
}

[ -n "$GOAL" ] || {
  usage
  _die "Missing --goal"
}

RUBRIC_PATH="$(almanac_harden_rubric_path "$PWD" "$TARGET")"
DISPLAY_PATH="${RUBRIC_PATH#$PWD/}"

if [ -e "$RUBRIC_PATH" ]; then
  _die "Rubric already exists: $DISPLAY_PATH"
fi

almanac_harden_write_rubric "$PWD" "$TARGET" "$GOAL"

_success "Draft rubric created: $DISPLAY_PATH"
_info "Edit and approve rubric before running reviewers."
