#!/usr/bin/env bash
# lib/providers/claude.sh — the claude (Claude Code) provider adapter.
#
# One file owns everything the engine needs to know about claude: availability,
# its active-session signal, the model/effort menus, its display name, the exec
# argv (deep invocation — incl. the sandbox→--permission-mode mapping), the
# event-stream jq filter, and how to extract the final result from the stream.
# Nothing outside this file contains a `claude …` literal. Auto-discovered by
# lib/agent.sh from lib/providers/*.sh.
#
# Contract (called as almanac_provider_claude_<verb>):
#   available  — is the claude CLI on PATH?
#   active_env — are we inside a resumable claude session? (see below — false)
#   models     — model menu (one per line; "default"/"custom" are sentinels)
#   efforts    — thinking-effort menu (one per line; claude also has "max")
#   display    — human display name
#   argv       — populate _ALMANAC_AGENT_ARGV with the exec tokens (no prompt)
#   filter     — jq program turning stream-json events into live assistant text
#   extract    — pull the final result out of the captured event stream
#   (no _supports_raw — claude has no native non-JSON passthrough)

almanac_provider_claude_available() {
  command -v claude >/dev/null 2>&1
}

# Claude has no thread-resume env signal that should override provider
# preference. CLAUDECODE merely marks that an ancestor process is a Claude Code
# session — honouring it would wrongly force claude even when a codex thread is
# being resumed (CODEX_THREAD_ID). So active_env is false; the seam's preference
# order (claude → codex) still selects claude when it is the installed default.
almanac_provider_claude_active_env() {
  return 1
}

almanac_provider_claude_models() {
  printf '%s\n' default sonnet opus haiku claude-sonnet-4-6 claude-opus-4-7 custom
}

almanac_provider_claude_efforts() {
  printf '%s\n' default low medium high xhigh max custom
}

almanac_provider_claude_display() {
  printf '%s\n' "Claude Code"
}

# Map a sandbox value to claude's --permission-mode. read-only review runs in
# `plan` (no writes); the `default` sentinel returns an empty mode so the argv
# OMITS --permission-mode entirely, letting claude fall back to its own default
# mode (ralph afk.sh's iteration agent has never set a permission mode);
# everything else (workspace-write, danger-full-access) maps to `acceptEdits`.
almanac_provider_claude_permission() {
  case "$1" in
    read-only) printf '%s\n' "plan" ;;
    default)   printf '%s\n' "" ;;
    *)         printf '%s\n' "acceptEdits" ;;
  esac
}

# Build claude's exec argv into _ALMANAC_AGENT_ARGV (the prompt is appended by
# the runner). claude always streams structured stream-json; the shape arg is
# unused (claude has no raw passthrough). $result_file is unused here — the
# result is recovered post-hoc by _extract, since claude has no result-file flag.
almanac_provider_claude_argv() {
  local model="$1" effort="$2" sandbox="$3" result_file="$4" shape="$5"
  local perm

  _ALMANAC_AGENT_ARGV=(
    claude
    --print
    --output-format stream-json
    --verbose
  )
  perm="$(almanac_provider_claude_permission "$sandbox")"
  [ -n "$perm" ]   && _ALMANAC_AGENT_ARGV+=(--permission-mode "$perm")
  [ -n "$model" ]  && _ALMANAC_AGENT_ARGV+=(--model "$model")
  [ -n "$effort" ] && _ALMANAC_AGENT_ARGV+=(--effort "$effort")
  return 0
}

# jq filter turning claude --output-format stream-json events into the live
# assistant text the console shows: the init model line, then each assistant
# text block, CRLF-normalised so it renders cleanly in a terminal.
almanac_provider_claude_filter() {
  cat <<'JQ'
  if .type == "system" and .subtype == "init" and (.model // "") != "" then
    "Claude model: \(.model)\r\n\n"
  elif .type == "assistant" then
    .message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"
  else
    empty
  end
JQ
}

# Extract claude's final result from the captured stream-json event log into
# $result_file (claude has no --output-last-message flag). Prefers jq; falls back
# to awk so a missing jq never silently drops the result.
almanac_provider_claude_extract() {
  local stream_file="$1"
  local result_file="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.type == "result").result // empty' "$stream_file" | tail -n 1 > "$result_file"
    return 0
  fi

  awk '
    /"type"[[:space:]]*:[[:space:]]*"result"/ && /"result"[[:space:]]*:/ {
      line = $0
      sub(/^.*"result"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      result = line
    }
    END {
      if (result != "") print result
    }
  ' "$stream_file" > "$result_file"
}
