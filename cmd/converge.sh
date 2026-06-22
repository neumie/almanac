#!/usr/bin/env bash
# converge.sh - Run a generic convergence loop
# summary: Run a generic convergence loop
# usage: almanac converge --goal G (--prompt T | --exec C) [--rounds N] | almanac converge <slug> [--watch | --stop]
# group: loops

set -euo pipefail

source "$ALMANAC_HOME/lib/core.sh"
source "$ALMANAC_HOME/lib/converge-core.sh"

usage() {
  printf '%s\n' "Usage: almanac converge --goal <goal> (--prompt <text> | --exec <command>) [--rounds N] [--no-oversee] [--oversee-every N]"
  printf '%s\n' "       almanac converge <slug> [--watch|--stop]"
  printf '%s\n' ""
  printf '%s\n' "  --prompt <text>  Prompt sent to the configured provider agent each round."
  printf '%s\n' "                   The dominant mode: pass a slash command (e.g. '/almanac:codebase-improve'),"
  printf '%s\n' "                   a chain ('/foo. After that, /bar'), or free-form text."
  printf '%s\n' "  --exec <cmd>     Shell command run by a wrapping worker agent each round."
  printf '%s\n' "                   Power-user escape hatch for non-agent workflows."
  printf '%s\n' "  Exactly one of --prompt or --exec is required."
}

GOAL=""
EXEC_CMD=""
PROMPT=""
ROUNDS="${CONVERGE_ROUND_BUDGET:-10}"
NO_OVERSEE=0
OVERSEE_EVERY="${CONVERGE_OVERSEE_EVERY:-1}"
TARGET_SLUG=""
WATCH=0
STOP=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)       usage; exit 0 ;;
    --goal)          _need_value --goal "$#";          GOAL="$2";          shift ;;
    --exec)          _need_value --exec "$#";          EXEC_CMD="$2";      shift ;;
    --prompt)        _need_value --prompt "$#";        PROMPT="$2";        shift ;;
    --rounds)        _need_value --rounds "$#";        ROUNDS="$2";        shift ;;
    --no-oversee)    NO_OVERSEE=1 ;;
    --oversee-every) _need_value --oversee-every "$#"; OVERSEE_EVERY="$2"; shift ;;
    --watch)         WATCH=1 ;;
    --stop)          STOP=1 ;;
    --)              shift; break ;;
    -*)              _die "Unknown converge option: $1" ;;
    *)
      [ -z "$TARGET_SLUG" ] || _die "Unexpected converge argument: $1"
      TARGET_SLUG="$1"
      ;;
  esac
  shift
done

[ "$WATCH" -eq 0 ] || [ "$STOP" -eq 0 ] || _die "Choose only one of --watch or --stop"

if [ -n "$TARGET_SLUG" ]; then
  [ -z "$GOAL" ] || _die "Cannot combine converge slug with --goal"
  [ -z "$EXEC_CMD" ] || _die "Cannot combine converge slug with --exec"
  [ -z "$PROMPT" ] || _die "Cannot combine converge slug with --prompt"

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

[ -n "$GOAL" ] || _die "Missing required --goal — see 'almanac converge --help'"
# Exactly one of --prompt / --exec is required. --prompt is the dominant mode
# (agent invocation; takes slash commands, chains, or free-form text). --exec is
# the escape hatch for non-agent shell workflows. Mutex enforced here so the
# round-dispatch in lib/converge-core.sh has a clean two-way fork.
if [ -n "$PROMPT" ] && [ -n "$EXEC_CMD" ]; then
  _die "--prompt and --exec are mutually exclusive — pick one"
fi
if [ -z "$PROMPT" ] && [ -z "$EXEC_CMD" ]; then
  _die "One of --prompt or --exec is required"
fi

almanac_converge_run "$PWD" "$GOAL" "$EXEC_CMD" "$ROUNDS" "$NO_OVERSEE" "$OVERSEE_EVERY" "$PROMPT"
