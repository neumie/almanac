#!/usr/bin/env bash
# converge.sh - Run a generic convergence loop

set -euo pipefail

source "$ALMANAC_HOME/lib/converge-core.sh"

usage() {
  printf '%s\n' "Usage: almanac converge --goal <goal> --exec <command> [--rounds N] [--no-oversee] [--oversee-every N]"
  printf '%s\n' "       almanac converge <slug> [--watch|--stop]"
}

GOAL=""
EXEC_CMD=""
ROUNDS="${CONVERGE_ROUND_BUDGET:-10}"
NO_OVERSEE=0
OVERSEE_EVERY="${CONVERGE_OVERSEE_EVERY:-1}"
TARGET_SLUG=""
WATCH=0
STOP=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --goal)
      shift
      [ "$#" -gt 0 ] || {
        usage >&2
        _die "Missing value for --goal"
      }
      GOAL="$1"
      ;;
    --exec)
      shift
      [ "$#" -gt 0 ] || {
        usage >&2
        _die "Missing value for --exec"
      }
      EXEC_CMD="$1"
      ;;
    --rounds)
      shift
      [ "$#" -gt 0 ] || {
        usage >&2
        _die "Missing value for --rounds"
      }
      ROUNDS="$1"
      ;;
    --no-oversee)
      NO_OVERSEE=1
      ;;
    --oversee-every)
      shift
      [ "$#" -gt 0 ] || {
        usage >&2
        _die "Missing value for --oversee-every"
      }
      OVERSEE_EVERY="$1"
      ;;
    --watch)
      WATCH=1
      ;;
    --stop)
      STOP=1
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage >&2
      _die "Unknown converge option: $1"
      ;;
    *)
      [ -z "$TARGET_SLUG" ] || {
        usage >&2
        _die "Unexpected converge argument: $1"
      }
      TARGET_SLUG="$1"
      ;;
  esac
  shift
done

[ "$WATCH" -eq 0 ] || [ "$STOP" -eq 0 ] || _die "Choose only one of --watch or --stop"

if [ -n "$TARGET_SLUG" ]; then
  [ -z "$GOAL" ] || _die "Cannot combine converge slug with --goal"
  [ -z "$EXEC_CMD" ] || _die "Cannot combine converge slug with --exec"

  if [ "$STOP" -eq 1 ]; then
    almanac_converge_stop "$PWD" "$TARGET_SLUG" || _die "Unknown converge run: $TARGET_SLUG"
    _success "Stop requested for converge: $TARGET_SLUG"
    exit 0
  fi

  if [ "$WATCH" -eq 1 ]; then
    almanac_converge_watch "$PWD" "$TARGET_SLUG" follow || _die "Unknown converge run: $TARGET_SLUG"
    exit 0
  fi

  almanac_converge_status "$PWD" "$TARGET_SLUG" || _die "Unknown converge run: $TARGET_SLUG"
  exit 0
fi

[ "$WATCH" -eq 0 ] || _die "--watch requires a converge slug"
[ "$STOP" -eq 0 ] || _die "--stop requires a converge slug"

[ -n "$GOAL" ] || {
  usage >&2
  _die "Missing required --goal"
}
[ -n "$EXEC_CMD" ] || {
  usage >&2
  _die "Missing required --exec"
}

almanac_converge_run "$PWD" "$GOAL" "$EXEC_CMD" "$ROUNDS" "$NO_OVERSEE" "$OVERSEE_EVERY"
