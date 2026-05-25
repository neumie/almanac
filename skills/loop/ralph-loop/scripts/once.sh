#!/bin/bash
set -e

# --- snapshot-exec guard ---------------------------------------------------
# Run from an immutable copy so a loop refactoring this runner cannot corrupt a
# live run mid-iteration (bash re-reads the main script by offset). Re-exec once
# — only when executed directly, never when sourced — from a temp copy; siblings
# and libs still load from the real dir via RALPH_REAL_DIR. The snapshot is
# removed by the EXIT trap (RALPH_SNAP_FILE).
if [ -z "${RALPH_SNAPSHOT:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  __real="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  __snap="$(mktemp "${TMPDIR:-/tmp}/almanac-runner.XXXXXX")"
  cp "${BASH_SOURCE[0]}" "$__snap"
  RALPH_SNAPSHOT=1 RALPH_REAL_DIR="$__real" RALPH_SNAP_FILE="$__snap" exec bash "$__snap" "$@"
fi

SCRIPT_DIR="${RALPH_REAL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
# ALMANAC_HOME bootstrap — same standardized snippet as the other entry points
# (mirrors almanac_resolve_home in lib/core.sh), resolved off SCRIPT_DIR rather
# than ${BASH_SOURCE[0]} because the snapshot-exec guard above runs us from an
# immutable temp copy; RALPH_REAL_DIR is the real scripts dir.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)}"
source "$SCRIPT_DIR/ralph-run-registry.sh"

# Provider seam (almanac_provider_*) — sourced directly so this runner's use of
# the seam (default-selection / availability / display) is an explicit
# dependency, not borrowed transitively.
if ! declare -F almanac_provider_default >/dev/null 2>&1; then
  source "$ALMANAC_HOME/lib/agent.sh"
fi

# Role config seam (almanac_loop_role_field) — sourced directly so this runner's
# per-role provider/model/effort resolution is an explicit dependency, not
# borrowed transitively.
if ! declare -F almanac_loop_role_field >/dev/null 2>&1; then
  source "$ALMANAC_HOME/lib/role.sh"
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <prd-name>"
  echo "Example: $0 auth-system"
  echo ""
  echo "Available PRDs:"
  for d in docs/plans/*/; do
    [ -f "$d/prd.md" ] && basename "$d"
  done 2>/dev/null | sed 's/^/  /'
  exit 1
fi

PRD_NAME="$1"
PROMPT="docs/plans/${PRD_NAME}/prompt.md"

# Iteration-agent role config resolves through the shared engine helper
# (almanac_loop_role_field): RALPH_AGENT_<FIELD> -> RALPH_<FIELD> -> default, the
# same precedence harden's roles use (#66 crit 3 — ralph uses the shared role
# config). RALPH_PROVIDER/RALPH_MODEL/RALPH_EFFORT still work (the fallback); the
# new RALPH_AGENT_* keys now override per-role. An explicit provider config wins;
# absent it, ralph's CLI auto-detection (CODEX_THREAD_ID, then installed CLI)
# stays — that runtime detection is ralph-specific, not a role-config concern.
detect_provider() {
  local configured default
  configured="$(almanac_loop_role_field ralph agent "" provider "")"
  if [ -n "$configured" ]; then
    echo "$configured"
  else
    default="$(almanac_provider_default)"
    echo "${default:-none}"
  fi
}

PROVIDER="$(detect_provider | tr '[:upper:]' '[:lower:]')"

# Model/effort overrides resolve through the same shared role-config helper.
# Unset = provider default. Both providers now route through the shared agent_run
# seam (which takes these scalars directly), so once.sh no longer builds MODEL_ARG
# /EFFORT_ARG arrays — that arg-shaping lives in the seam (#66 crit 6).
AGENT_MODEL="$(almanac_loop_role_field ralph agent "" model "")"
AGENT_EFFORT="$(almanac_loop_role_field ralph agent "" effort "")"

if [ ! -f "$PROMPT" ]; then
  echo "Error: $PROMPT not found. Run /ralph-loop $PRD_NAME to set up first."
  exit 1
fi

# Availability + display route through the provider seam (no provider-name
# branching). The remaining case sets only the banner's cosmetic default-text.
if [ "$PROVIDER" = "none" ] || ! almanac_provider_known "$PROVIDER"; then
  echo "Error: no supported agent found. Install Claude Code or Codex, or set RALPH_PROVIDER."
  exit 1
fi
if ! almanac_provider_available "$PROVIDER"; then
  echo "Error: provider '$PROVIDER' selected but its CLI is not on PATH."
  exit 1
fi
PROVIDER_DISPLAY="$(almanac_provider_display "$PROVIDER")"
EFFORT_DISPLAY="${AGENT_EFFORT:-provider default}"
case "$PROVIDER" in
  claude)
    MODEL_DISPLAY="${AGENT_MODEL:-Claude Code default (resolved on session start)}"
    PERMISSION_DISPLAY="acceptEdits"
    ;;
  codex)
    MODEL_DISPLAY="${AGENT_MODEL:-Codex default}"
    PERMISSION_DISPLAY="approval never, sandbox danger-full-access"
    ;;
esac

ralph_register_run "$PRD_NAME"
trap 'ralph_finish_run "$?"; rm -f "${RALPH_SNAP_FILE:-}"' EXIT

echo "======= RALPH ONCE ======="
echo "PRD:         $PRD_NAME"
echo "Prompt:      $PROMPT"
echo "Run ID:      $RALPH_RUN_ID"
echo "Provider:    $PROVIDER_DISPLAY"
echo "Model:       $MODEL_DISPLAY"
echo "Effort:      $EFFORT_DISPLAY"
echo "Permission:  $PERMISSION_DISPLAY"
echo "=========================="
echo ""

ralph_update_run_progress 1 "provider=$PROVIDER iteration=1/1"

ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

case "$PROVIDER" in
  claude)
    # Provider invocation goes through the shared agent_run seam in stream mode
    # rather than an inline claude exec (#66 — ralph migration onto the engine).
    # The seam builds the same invocation once.sh used (--print --output-format
    # stream-json --verbose --permission-mode acceptEdits, plus --model/--effort),
    # tees the raw event stream to its events file, and pipes the live assistant
    # text to stdout through the same jq filter — so console output is unchanged.
    # workspace-write maps to acceptEdits (once.sh's permission mode); the
    # role-resolved AGENT_MODEL/AGENT_EFFORT feed the seam's model/effort.
    # Unlike the old inline pipe (no pipefail), the seam preserves claude's exit
    # via PIPESTATUS, so a provider failure now propagates instead of being
    # swallowed — matching the codex branch and the agent-runner contract.
    prompt="@$PROMPT Previous RALPH commits: $ralph_commits"
    claude_prompt_file=$(mktemp)
    claude_events_file=$(mktemp)
    claude_result_file=$(mktemp)
    printf '%s' "$prompt" > "$claude_prompt_file"
    almanac_loop_agent_stream \
      claude "$AGENT_MODEL" "$AGENT_EFFORT" workspace-write \
      "$claude_prompt_file" "$claude_result_file" "$claude_events_file"
    rm -f "$claude_prompt_file" "$claude_events_file" "$claude_result_file"
    ;;
  codex)
    prompt="# OUTPUT STYLE

As you work, emit concise progress updates describing what you are doing and what you learned. Keep these updates short and useful. Do not manually paste command output; the runner logs raw tool output separately.

$(cat "$PROMPT")

Previous RALPH commits:
$ralph_commits"
    mkdir -p "docs/plans/${PRD_NAME}"
    codex_log="docs/plans/${PRD_NAME}/ralph-codex-once.log"
    codex_result=$(mktemp)
    echo "Codex session log: $codex_log"
    if [ "${RALPH_CODEX_VERBOSE:-}" = "1" ]; then
      # Raw-output mode now routes through the shared agent_run seam too, via its
      # raw passthrough mode (#66 crit 6 — no inline provider exec remains): raw
      # runs codex WITHOUT --json so its native output streams straight to the
      # terminal (no jq filter, no events capture), while --output-last-message
      # still captures the final message to $codex_result. The role-resolved
      # AGENT_MODEL/AGENT_EFFORT feed the seam, which propagates codex's exit; on
      # failure we clean up and exit so the run is marked failed (as set -e did).
      codex_prompt_file=$(mktemp)
      printf '%s' "$prompt" > "$codex_prompt_file"
      if ! almanac_loop_agent_raw \
        codex "$AGENT_MODEL" "$AGENT_EFFORT" danger-full-access \
        "$codex_prompt_file" "$codex_result"; then
        rm -f "$codex_prompt_file" "$codex_result"
        exit 1
      fi
      rm -f "$codex_prompt_file"
    else
      # Default codex path routes through the shared agent_run seam in stream mode
      # rather than an inline codex exec (#66 — ralph migration onto the engine).
      # The seam builds the same invocation (--json --output-last-message,
      # --sandbox danger-full-access, plus --model/-c effort), tees the raw stream
      # to the session log, and pipes the live agent-message text through the same
      # jq filter — console output is unchanged. merge-stderr preserves once.sh's
      # `codex ... 2>&1 | tee` so codex's stderr still lands in the log. The
      # role-resolved AGENT_MODEL/AGENT_EFFORT feed the seam's model/effort,
      # and the seam preserves codex's exit via PIPESTATUS (once.sh kept pipefail
      # before; the seam owns that now). On failure we print the same log tail.
      codex_prompt_file=$(mktemp)
      printf '%s' "$prompt" > "$codex_prompt_file"
      if ! almanac_loop_agent_stream \
        codex "$AGENT_MODEL" "$AGENT_EFFORT" danger-full-access \
        "$codex_prompt_file" "$codex_result" "$codex_log" merge-stderr; then
        rm -f "$codex_prompt_file"
        echo "Codex failed. Last log lines:"
        tail -n 40 "$codex_log" || true
        rm -f "$codex_result"
        exit 1
      fi
      rm -f "$codex_prompt_file"
      cat "$codex_result"
    fi
    rm -f "$codex_result"
    ;;
esac
