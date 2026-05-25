#!/usr/bin/env bash
# harden.sh - Bootstrap a harden-loop rubric for one target

set -euo pipefail

source "$ALMANAC_HOME/lib/harden-core.sh"

usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac harden <target>"
  printf '%s\n' "  almanac harden <target> --goal <goal>"
  printf '%s\n' "  almanac harden <target> --approve"
  printf '%s\n' ""
  printf '%s\n' "With no flags, runs a single read-only reviewer over the target and"
  printf '%s\n' "prints its findings."
  printf '%s\n' "With --goal, creates docs/plans/harden/<target-slug>/rubric.md in the repo."
  printf '%s\n' "With --approve, approves an edited draft rubric."
}

TARGET=""
GOAL=""
APPROVE=0

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
    --approve)
      APPROVE=1
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

if [ "$APPROVE" -eq 1 ]; then
  [ -z "$GOAL" ] || _die "Use either --goal or --approve, not both"

  RUBRIC_PATH="$(almanac_harden_rubric_path "$PWD" "$TARGET")"
  DISPLAY_PATH="${RUBRIC_PATH#$PWD/}"

  if almanac_harden_approve_rubric "$PWD" "$TARGET"; then
    _success "Rubric approved: $DISPLAY_PATH"
    _info "Next harden-loop phase can require approved status before reviewers run."
    exit 0
  else
    APPROVE_STATUS="$?"
  fi

  case "$APPROVE_STATUS" in
    2)
      _die "Rubric not found: $DISPLAY_PATH"
      ;;
    3)
      _die "Rubric already approved: $DISPLAY_PATH"
      ;;
    *)
      _die "Failed to approve rubric: $DISPLAY_PATH"
      ;;
  esac
fi

if [ -n "$GOAL" ]; then
  RUBRIC_PATH="$(almanac_harden_rubric_path "$PWD" "$TARGET")"
  DISPLAY_PATH="${RUBRIC_PATH#$PWD/}"

  if [ -e "$RUBRIC_PATH" ]; then
    _die "Rubric already exists: $DISPLAY_PATH"
  fi

  almanac_harden_write_rubric "$PWD" "$TARGET" "$GOAL"

  _success "Draft rubric created: $DISPLAY_PATH"
  _info "Edit and approve rubric before running reviewers."
  exit 0
fi

# No --goal or --approve: run a single read-only reviewer over the target.
almanac_harden_review "$PWD" "$TARGET"
