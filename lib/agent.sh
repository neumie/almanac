#!/usr/bin/env bash
# lib/agent.sh — the agent/provider seam.
#
# Per the module map, lib/agent.sh owns "the three shapes + provider dispatch".
# Two layers live here:
#   1. The provider-adapter seam (loop-engine-split slice 03): discovery of
#      lib/providers/<name>.sh, contract dispatch (callers never branch on a
#      provider name), and the single default-selection policy.
#   2. The three agent-run shapes (slice 04): almanac_loop_agent_capture /
#      _stream / _raw — intention-revealing replacements for the old
#      mode-parametric almanac_loop_agent_run. Each takes only what its shape
#      needs (no invalid mode combinations to guard); they consume the adapter's
#      argv + filter and own ONLY execution mechanics (exec, capture, stream,
#      PIPESTATUS exit threading).
#
# Self-contained: the seam uses only printf / command -v / source. The run shapes
# add jq / tee / grep / mktemp (coreutils) and emit diagnostics through _error
# when a caller has sourced lib/core.sh, falling back to a plain stderr line
# otherwise (_almanac_agent_err) — so there is still no hard dependency on
# lib/core.sh and any caller (or test) can source this file directly. Provider
# adapters are auto-loaded at source time (almanac_provider_load below).

__almanac_agent_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Normalise a provider name to its adapter key (lowercase; claude-code → claude).
almanac_provider_key() {
  local k
  k="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$k" in
    claude-code) k="claude" ;;
  esac
  printf '%s' "$k"
}

# Source every provider adapter (idempotent — adapters only define functions).
almanac_provider_load() {
  local f
  for f in "$__almanac_agent_dir"/providers/*.sh; do
    [ -f "$f" ] || continue
    # shellcheck source=/dev/null
    source "$f"
  done
  return 0
}

# List discovered provider names — the provider list IS the files present, so
# there is no second place to update. Sorted by the glob (alphabetical).
almanac_provider_list() {
  local f name
  for f in "$__almanac_agent_dir"/providers/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    printf '%s\n' "$name"
  done
  return 0
}

# Is NAME a discovered provider?
almanac_provider_known() {
  local want target
  want="$(almanac_provider_key "$1")"
  while IFS= read -r target; do
    [ "$target" = "$want" ] && return 0
  done <<EOF
$(almanac_provider_list)
EOF
  return 1
}

# Dispatch a contract verb to NAME's adapter: almanac_provider_call <name> <verb>
# [args…]. Returns 2 if the adapter doesn't implement the verb. This is the one
# place that turns (provider, verb) into a function call, so no caller anywhere
# branches on provider name.
almanac_provider_call() {
  local key verb fn
  key="$(almanac_provider_key "$1")"
  verb="$2"
  shift 2
  fn="almanac_provider_${key}_${verb}"
  declare -F "$fn" >/dev/null 2>&1 || return 2
  "$fn" "$@"
}

# Thin public wrappers over the contract verbs.
almanac_provider_available()  { almanac_provider_call "$1" available; }
almanac_provider_active_env() { almanac_provider_call "$1" active_env; }
almanac_provider_models()     { almanac_provider_call "$1" models; }
almanac_provider_efforts()    { almanac_provider_call "$1" efforts; }
almanac_provider_display()    { almanac_provider_call "$1" display; }
almanac_provider_filter()     { almanac_provider_call "$1" filter; }
# argv populates the global _ALMANAC_AGENT_ARGV; callers use almanac_provider_call
# "<name>" argv <model> <effort> <sandbox> <result_file> <shape> directly.

# The single central default-selection policy (the one provider remainder that is
# not in an adapter, by design): the active-env provider if it is installed, else
# the first installed provider in preference order (claude → codex). Echoes the
# chosen name, or "" if no provider is installed.
almanac_provider_default() {
  local p
  # Phase 1 — the provider whose resumable session we are inside.
  for p in $(almanac_provider_list); do
    if almanac_provider_active_env "$p" && almanac_provider_available "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  # Phase 2 — preference order.
  for p in claude codex; do
    if almanac_provider_available "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  printf '%s\n' ""
  return 0
}

# --- Agent run shapes ----------------------------------------------------------
#
# Three intention-revealing shapes replace the old mode-parametric agent_run. The
# common quartet (provider, model, effort, sandbox) comes from role config; the
# provider adapter supplies the exec argv + event filter (deep invocation), and
# these own only execution mechanics. There are no invalid mode combinations to
# guard because each shape takes only the args it needs.

# Diagnostics: prefer lib/core.sh's _error when a caller sourced it (real runs all
# do), so the message is byte-identical; else a plain stderr line. Keeps the seam
# sourceable standalone (tests) without a hard core.sh dependency.
_almanac_agent_err() {
  if declare -F _error >/dev/null 2>&1; then
    _error "$@"
  else
    printf '[error] %s\n' "$*" >&2
  fi
}

# Run a provider command, optionally merging its stderr into stdout (2>&1) when
# $1 is "1". The producer at the head of the stream pipeline so the merge toggles
# without duplicating the pipeline. Its exit is the provider's, so PIPESTATUS[0]
# in the calling pipeline reflects the producer, not this wrapper.
almanac_loop_agent_producer() {
  local merge="$1"; shift
  if [ "$merge" = "1" ]; then
    "$@" 2>&1
  else
    "$@"
  fi
}

# Private: validate the provider is known + on PATH, then build its exec argv for
# SHAPE into _ALMANAC_AGENT_ARGV. Returns 3/4 (with a diagnostic) on an unknown/
# unavailable provider; 0 with the argv ready otherwise. The single place the
# shapes turn (provider, model, effort, sandbox) into exec tokens — no shape
# contains a `codex …`/`claude …` literal.
_almanac_agent_build() {
  local provider="$1" model="$2" effort="$3" sandbox="$4" result_file="$5" shape="$6"
  almanac_provider_known "$provider"     || { _almanac_agent_err "unsupported provider: $provider"; return 3; }
  almanac_provider_available "$provider" || { _almanac_agent_err "provider '$provider' is not on PATH."; return 4; }
  almanac_provider_call "$provider" argv "$model" "$effort" "${sandbox:-danger-full-access}" "$result_file" "$shape"
}

# Private: providers that don't write their result via argv (claude) implement an
# *_extract hook that recovers it from the captured stream; codex writes it
# directly via --output-last-message and declares none. A no-op for the latter.
_almanac_agent_extract() {
  local key; key="$(almanac_provider_key "$1")"
  local stream_file="$2" result_file="$3"
  if declare -F "almanac_provider_${key}_extract" >/dev/null 2>&1; then
    "almanac_provider_${key}_extract" "$stream_file" "$result_file"
  fi
  return 0
}

# capture: run the provider silently, capturing the raw event stream to
# EVENTS_FILE and (for adapters with an extract hook) the final result to
# RESULT_FILE. No stdout — converge's workers and loop's
# overseer all discard it. A direct redirect (no pipe) keeps $? as the provider's
# exit so a failure propagates.
# Usage: almanac_loop_agent_capture <provider> <model> <effort> <sandbox> \
#                                   <prompt_file> <result_file> <events_file>
almanac_loop_agent_capture() {
  [ "$#" -ge 7 ] || return 2
  local provider="$1" model="$2" effort="$3" sandbox="$4"
  local prompt_file="$5" result_file="$6" events_file="$7"
  local prompt
  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2
  [ -n "$events_file" ] || return 2

  _almanac_agent_build "$provider" "$model" "$effort" "$sandbox" "$result_file" "structured" || return
  local cmd=("${_ALMANAC_AGENT_ARGV[@]}")
  prompt="$(cat "$prompt_file")"

  "${cmd[@]}" "$prompt" > "$events_file" || return "$?"
  _almanac_agent_extract "$provider" "$events_file" "$result_file"
}

# stream: run the provider live — tee its raw event stream to EVENTS_FILE AND pipe
# it through the adapter's jq filter to stdout, so the caller sees progress as it
# happens. The PRODUCER's exit wins via PIPESTATUS (a provider failure propagates
# even though it is piped), not the jq filter's; errexit is suspended around the
# pipeline (a no-match filter must not abort a set -e caller) and restored after.
# The `grep '^{'` prefilter keeps only JSON-object lines (the events FILE is the
# raw tee, unaffected); degrades to a raw tee when jq is absent or the adapter
# yields no filter, so output is never silently dropped. Optional MERGE_STDERR
# (merge-stderr|on|1) folds the provider's stderr into the captured/streamed
# output — preserving loop's `codex ... 2>&1 | tee` log capture; default leaves
# stderr on the terminal. The events-file path is NOT echoed (it would corrupt
# the live stream); the caller passes its own path and already knows it.
# Usage: almanac_loop_agent_stream <provider> <model> <effort> <sandbox> \
#                          <prompt_file> <result_file> <events_file> [merge_stderr]
almanac_loop_agent_stream() {
  [ "$#" -ge 7 ] || return 2
  local provider="$1" model="$2" effort="$3" sandbox="$4"
  local prompt_file="$5" result_file="$6" events_file="$7" merge_stderr="${8:-}"
  local prompt filter rc had_e=0 merge=0
  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2
  [ -n "$events_file" ] || return 2
  case "$merge_stderr" in
    merge-stderr|stderr|on|1) merge=1 ;;
  esac

  _almanac_agent_build "$provider" "$model" "$effort" "$sandbox" "$result_file" "structured" || return
  local cmd=("${_ALMANAC_AGENT_ARGV[@]}")
  prompt="$(cat "$prompt_file")"
  filter="$(almanac_provider_filter "$provider" 2>/dev/null)" || filter=""

  case $- in *e*) had_e=1 ;; esac
  set +e
  if command -v jq >/dev/null 2>&1 && [ -n "$filter" ]; then
    almanac_loop_agent_producer "$merge" "${cmd[@]}" "$prompt" | tee "$events_file" | grep --line-buffered '^{' \
      | jq -Rj --unbuffered "fromjson? // empty | objects | ( $filter )"
  else
    almanac_loop_agent_producer "$merge" "${cmd[@]}" "$prompt" | tee "$events_file"
  fi
  rc=${PIPESTATUS[0]}
  [ "$had_e" -eq 1 ] && set -e
  [ "$rc" -eq 0 ] || return "$rc"

  _almanac_agent_extract "$provider" "$events_file" "$result_file"
  return 0
}

# capture_text: capture variant that takes the prompt as a STRING and returns the
# provider's result text on stdout. Owns the full tmpfile lifecycle (prompt,
# result, events) inside a subshell with an EXIT trap, so cleanup runs on every
# exit path — normal return, error, signal — without leaking the parent's traps.
# Provider stderr is NOT silenced (callers that want quiet add `2>/dev/null`).
# The provider's exit code propagates as the function's exit. Use this when the
# caller only needs the result text (overseer judgments, ratification verdicts,
# fire-and-forget fixer dispatches); use almanac_loop_agent_capture directly
# when you need the events.jsonl to persist beyond the call.
# Usage: almanac_loop_agent_capture_text <provider> <model> <effort> <sandbox> <prompt_text>
almanac_loop_agent_capture_text() {
  [ "$#" -ge 5 ] || return 2
  local provider="$1" model="$2" effort="$3" sandbox="$4" prompt_text="$5"
  [ -n "$provider" ] || return 2

  (
    local workdir="" rc=0
    # Trap installed BEFORE mktemp so any failure path (mktemp itself, the
    # capture call, an early `exit "$?"`) still hits cleanup; the guard makes
    # the trap a no-op if workdir was never populated. Subshell-scoped trap, so
    # the parent's traps are unaffected.
    trap '[ -n "${workdir:-}" ] && rm -rf "$workdir"' EXIT
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/almanac-capture-text.XXXXXX")" || exit 1

    printf '%s' "$prompt_text" > "$workdir/prompt"
    almanac_loop_agent_capture "$provider" "$model" "$effort" "$sandbox" \
      "$workdir/prompt" "$workdir/result" "$workdir/events" || exit "$?"

    [ -s "$workdir/result" ] && cat "$workdir/result"
    exit 0
  )
}

# raw: native passthrough for adapters that declare *_supports_raw (codex omits
# --json so its native output streams straight to the terminal — no jq filter, no
# events capture). The direct exec keeps $? as the provider's exit. A provider
# WITHOUT raw support degrades to a silent capture into a throwaway events log, so
# output is never dropped (matching the old agent_run raw fallback).
# Usage: almanac_loop_agent_raw <provider> <model> <effort> <sandbox> \
#                               <prompt_file> <result_file>
almanac_loop_agent_raw() {
  [ "$#" -ge 6 ] || return 2
  local provider="$1" model="$2" effort="$3" sandbox="$4"
  local prompt_file="$5" result_file="$6"
  local key prompt events_file rc=0
  [ -n "$provider" ] || return 2
  [ -f "$prompt_file" ] || return 2

  key="$(almanac_provider_key "$provider")"
  if ! declare -F "almanac_provider_${key}_supports_raw" >/dev/null 2>&1; then
    # The raw fallback's events log is throwaway (the shape doesn't persist
    # events for the caller, unlike capture). Explicit cleanup after capture
    # closes the leak the original return-and-go shape introduced. A bash
    # RETURN trap is not used: trap scope is global, so a function-scoped
    # cleanup that referenced a local would fire on every subsequent return.
    events_file="$(mktemp "${TMPDIR:-/tmp}/almanac-loop-events.XXXXXX")" || return 1
    almanac_loop_agent_capture "$provider" "$model" "$effort" "$sandbox" \
      "$prompt_file" "$result_file" "$events_file" || rc=$?
    rm -f "$events_file"
    return "$rc"
  fi

  _almanac_agent_build "$provider" "$model" "$effort" "$sandbox" "$result_file" "raw" || return
  local cmd=("${_ALMANAC_AGENT_ARGV[@]}")
  prompt="$(cat "$prompt_file")"

  # No --json, no filter, no events capture: native output to the terminal. codex
  # writes its result via --output-last-message, so no extract step is needed.
  "${cmd[@]}" "$prompt" || return "$?"
  return 0
}

almanac_provider_load
