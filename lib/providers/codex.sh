#!/usr/bin/env bash
# lib/providers/codex.sh — the codex provider adapter.
#
# One file owns everything the engine needs to know about codex: availability,
# its active-session signal, the model/effort menus, its display name, the exec
# argv (deep invocation — incl. the sandbox value and --json-or-not by shape),
# and the event-stream jq filter. Nothing outside this file contains a `codex …`
# literal. Auto-discovered by lib/agent.sh from lib/providers/*.sh; adding a
# provider is a sibling file implementing the same contract.
#
# Contract (called as almanac_provider_codex_<verb>):
#   available    — is the codex CLI on PATH?
#   active_env   — are we inside a resumable codex session? (CODEX_THREAD_ID)
#   models       — model menu (one per line; "default"/"custom" are sentinels)
#   efforts      — thinking-effort menu (one per line)
#   display      — human display name
#   argv         — populate _ALMANAC_AGENT_ARGV with the exec tokens (no prompt)
#   filter       — jq program turning --json events into live agent-message text
#   supports_raw — declared (codex has a native, non-JSON passthrough mode)
#   (no _extract — codex writes its result via --output-last-message)

almanac_provider_codex_available() {
  command -v codex >/dev/null 2>&1
}

# CODEX_THREAD_ID is a resume directive ("continue this exact thread"), so a run
# inside a codex session should prefer codex — the seam's default-selection
# honours this active-env signal before falling back to preference order.
almanac_provider_codex_active_env() {
  [ -n "${CODEX_THREAD_ID:-}" ]
}

almanac_provider_codex_models() {
  printf '%s\n' default gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2 custom
}

almanac_provider_codex_efforts() {
  printf '%s\n' default low medium high xhigh custom
}

almanac_provider_codex_display() {
  printf '%s\n' "Codex"
}

# Declared (not called) so the agent runner can detect — without branching on
# provider name — that codex has a raw passthrough shape (native output, no
# --json/filter/events capture). Providers without it fall back to capture.
almanac_provider_codex_supports_raw() {
  return 0
}

# Build codex's exec argv into _ALMANAC_AGENT_ARGV (the prompt is appended by the
# runner, not here). shape "raw" omits --json so codex's native output streams
# straight to the terminal; every other shape parses the structured --json event
# stream. --output-last-message captures the final message to $result_file in
# both shapes. The sandbox value is passed straight through to --sandbox.
almanac_provider_codex_argv() {
  local model="$1" effort="$2" sandbox="$3" result_file="$4" shape="$5"
  sandbox="${sandbox:-danger-full-access}"

  _ALMANAC_AGENT_ARGV=(
    codex
    --ask-for-approval never
    exec
    --cd "$PWD"
    --sandbox "$sandbox"
    --color never
  )
  [ "$shape" = "raw" ] || _ALMANAC_AGENT_ARGV+=(--json)
  _ALMANAC_AGENT_ARGV+=(--output-last-message "$result_file")
  [ -n "$model" ]  && _ALMANAC_AGENT_ARGV+=(--model "$model")
  [ -n "$effort" ] && _ALMANAC_AGENT_ARGV+=(-c "model_reasoning_effort=\"$effort\"")
  return 0
}

# jq filter turning codex --json events into the live agent-message text the
# console shows.
almanac_provider_codex_filter() {
  cat <<'JQ'
  if .type == "item.completed" and .item.type == "agent_message" then
    .item.text | . + "\n\n"
  else
    empty
  end
JQ
}
