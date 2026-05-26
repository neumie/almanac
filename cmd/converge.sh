#!/usr/bin/env bash
# converge.sh - Run a generic convergence loop

set -euo pipefail

source "$ALMANAC_HOME/lib/converge-core.sh"

usage() {
  printf '%s\n' "Usage: almanac converge --goal <goal> --exec <command> [--rounds N]"
}

GOAL=""
EXEC_CMD=""
ROUNDS="1"

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
    --)
      shift
      break
      ;;
    -*)
      usage >&2
      _die "Unknown converge option: $1"
      ;;
    *)
      usage >&2
      _die "Unexpected converge argument: $1"
      ;;
  esac
  shift
done

[ -n "$GOAL" ] || {
  usage >&2
  _die "Missing required --goal"
}
[ -n "$EXEC_CMD" ] || {
  usage >&2
  _die "Missing required --exec"
}

almanac_converge_run "$PWD" "$GOAL" "$EXEC_CMD" "$ROUNDS"
