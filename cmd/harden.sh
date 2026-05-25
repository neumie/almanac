#!/usr/bin/env bash
# harden.sh - Bootstrap a harden-loop rubric for one target

set -euo pipefail

source "$ALMANAC_HOME/lib/harden-core.sh"

usage() {
  printf '%s\n' "Usage:"
  printf '%s\n' "  almanac harden <target>"
  printf '%s\n' "  almanac harden <target> --goal <goal>"
  printf '%s\n' "  almanac harden <target> --approve"
  printf '%s\n' "  almanac harden <target> --fix"
  printf '%s\n' "  almanac harden <target> --loop [--rounds N]"
  printf '%s\n' "  almanac harden <target> --watch"
  printf '%s\n' "  almanac harden <target> --watch-worker <lens|worker-id>"
  printf '%s\n' ""
  printf '%s\n' "With no flags, fans out one read-only reviewer per lens over the target,"
  printf '%s\n' "aggregates their findings into the ledger, and prints them. Configure the"
  printf '%s\n' "lens set via HARDEN_LENSES (comma- or space-separated; no enforced cap)."
  printf '%s\n' "If a rubric has been drafted for the target, it must be approved first;"
  printf '%s\n' "a target with no rubric runs ad-hoc."
  printf '%s\n' "With --goal, creates docs/plans/harden/<target-slug>/rubric.md in the repo."
  printf '%s\n' "With --approve, approves an edited draft rubric."
  printf '%s\n' "With --fix, runs one sequential write-capable fixer over the open blocking"
  printf '%s\n' "findings, then runs the project feedback loops and reports a verdict per loop."
  printf '%s\n' "With --loop, runs the convergence loop (fan-out -> ratify -> fix -> feedback"
  printf '%s\n' "-> gate) in rounds until it converges or the round budget is hit. Set the"
  printf '%s\n' "budget with --rounds N (default 5, or HARDEN_ROUND_BUDGET). Between rounds a"
  printf '%s\n' "HITL checkpoint lets you ship, continue, or steer — steering captures a"
  printf '%s\n' "directive that redirects the next round's reviewers and fixer."
  printf '%s\n' "With --watch, redraws the live supervision dashboard for the target's most"
  printf '%s\n' "recent run (reviewer health, findings tallies, rubric progress, verdict)."
  printf '%s\n' "With --watch-worker, streams a single reviewer's live event log (pass a lens"
  printf '%s\n' "like 'security' or a full worker id like 'reviewer-security')."
}

TARGET=""
GOAL=""
APPROVE=0
FIX=0
LOOP=0
ROUNDS=""
WATCH=0
WATCH_WORKER=""

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
    --fix)
      FIX=1
      ;;
    --loop)
      LOOP=1
      ;;
    --watch)
      WATCH=1
      ;;
    --watch-worker)
      shift
      [ "$#" -gt 0 ] || _die "Missing value for --watch-worker"
      WATCH_WORKER="$1"
      ;;
    --rounds)
      shift
      [ "$#" -gt 0 ] || _die "Missing value for --rounds"
      ROUNDS="$1"
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

# Live supervision modes (read-only): watch the dashboard or a single worker's
# event stream for the target's most recent run. Mutually exclusive with the
# action modes (--goal/--approve/--fix/--loop).
if [ "$WATCH" -eq 1 ] || [ -n "$WATCH_WORKER" ]; then
  [ -z "$GOAL" ] || _die "Use either --goal or a --watch mode, not both"
  [ "$APPROVE" -eq 0 ] || _die "Use either --approve or a --watch mode, not both"
  [ "$FIX" -eq 0 ] || _die "Use either --fix or a --watch mode, not both"
  [ "$LOOP" -eq 0 ] || _die "Use either --loop or a --watch mode, not both"
  [ -z "$ROUNDS" ] || _die "--rounds does not apply to a --watch mode"

  if [ "$WATCH" -eq 1 ] && [ -n "$WATCH_WORKER" ]; then
    _die "Use either --watch or --watch-worker, not both"
  fi

  if [ -n "$WATCH_WORKER" ]; then
    almanac_harden_watch_worker "$PWD" "$TARGET" "$WATCH_WORKER" "follow"
    exit 0
  fi

  almanac_harden_dashboard_redraw "$PWD" "$TARGET"
  exit 0
fi

if [ "$LOOP" -eq 1 ]; then
  [ -z "$GOAL" ] || _die "Use either --goal or --loop, not both"
  [ "$APPROVE" -eq 0 ] || _die "Use either --approve or --loop, not both"
  [ "$FIX" -eq 0 ] || _die "Use either --fix or --loop, not both"

  almanac_harden_run "$PWD" "$TARGET" ${ROUNDS:+"$ROUNDS"}
  exit 0
fi

[ -z "$ROUNDS" ] || _die "--rounds only applies with --loop"

if [ "$FIX" -eq 1 ]; then
  [ -z "$GOAL" ] || _die "Use either --goal or --fix, not both"
  [ "$APPROVE" -eq 0 ] || _die "Use either --approve or --fix, not both"

  almanac_harden_fix "$PWD" "$TARGET"
  # Feedback is decoupled from the fixer (the loop runs it per round); run it
  # here so the standalone --fix path still reports the objective verdict.
  almanac_harden_report_feedback "$PWD"
  exit 0
fi

if [ "$APPROVE" -eq 1 ]; then
  [ -z "$GOAL" ] || _die "Use either --goal or --approve, not both"

  RUBRIC_PATH="$(almanac_harden_rubric_path "$PWD" "$TARGET")"
  DISPLAY_PATH="${RUBRIC_PATH#$PWD/}"

  if almanac_harden_approve_rubric "$PWD" "$TARGET"; then
    _success "Rubric approved: $DISPLAY_PATH"
    _info "Contract locked — reviewers can now run: almanac harden $TARGET"
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

# No --goal or --approve: fan out N read-only reviewers (one per configured
# lens) over the target and aggregate their findings into the ledger.
almanac_harden_fanout "$PWD" "$TARGET"
