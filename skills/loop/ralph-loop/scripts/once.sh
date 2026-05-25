#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ralph-run-registry.sh"

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

detect_provider() {
  if [ -n "${RALPH_PROVIDER:-}" ]; then
    echo "$RALPH_PROVIDER"
  elif [ -n "${CODEX_THREAD_ID:-}" ] && command -v codex >/dev/null 2>&1; then
    echo "codex"
  elif command -v claude >/dev/null 2>&1; then
    echo "claude"
  elif command -v codex >/dev/null 2>&1; then
    echo "codex"
  else
    echo "none"
  fi
}

PROVIDER="$(detect_provider | tr '[:upper:]' '[:lower:]')"

# Model override: set RALPH_MODEL env var. Unset = provider default.
MODEL_ARG=()
if [ -n "${RALPH_MODEL:-}" ]; then
  MODEL_ARG=(--model "$RALPH_MODEL")
fi
EFFORT_ARG=()

if [ ! -f "$PROMPT" ]; then
  echo "Error: $PROMPT not found. Run /ralph-loop $PRD_NAME to set up first."
  exit 1
fi

case "$PROVIDER" in
  claude)
    if ! command -v claude >/dev/null 2>&1; then
      echo "Error: RALPH_PROVIDER=claude but 'claude' is not on PATH."
      exit 1
    fi
    PROVIDER_DISPLAY="Claude Code"
    MODEL_DISPLAY="${RALPH_MODEL:-Claude Code default (resolved on session start)}"
    if [ -n "${RALPH_EFFORT:-}" ]; then
      EFFORT_ARG=(--effort "$RALPH_EFFORT")
    fi
    EFFORT_DISPLAY="${RALPH_EFFORT:-provider default}"
    PERMISSION_DISPLAY="acceptEdits"
    ;;
  codex)
    if ! command -v codex >/dev/null 2>&1; then
      echo "Error: RALPH_PROVIDER=codex but 'codex' is not on PATH."
      exit 1
    fi
    PROVIDER_DISPLAY="Codex"
    MODEL_DISPLAY="${RALPH_MODEL:-Codex default}"
    if [ -n "${RALPH_EFFORT:-}" ]; then
      EFFORT_ARG=(-c "model_reasoning_effort=\"$RALPH_EFFORT\"")
    fi
    EFFORT_DISPLAY="${RALPH_EFFORT:-provider default}"
    PERMISSION_DISPLAY="approval never, sandbox danger-full-access"
    ;;
  *)
    echo "Error: no supported agent found. Install Claude Code or Codex, or set RALPH_PROVIDER."
    exit 1
    ;;
esac

ralph_register_run "$PRD_NAME"
trap 'ralph_finish_run "$?"' EXIT

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
    # workspace-write maps to acceptEdits (once.sh's permission mode);
    # RALPH_MODEL/RALPH_EFFORT pass straight through as the seam's model/effort.
    # Unlike the old inline pipe (no pipefail), the seam preserves claude's exit
    # via PIPESTATUS, so a provider failure now propagates instead of being
    # swallowed — matching the codex branch and the agent-runner contract.
    prompt="@$PROMPT Previous RALPH commits: $ralph_commits"
    claude_prompt_file=$(mktemp)
    claude_events_file=$(mktemp)
    claude_result_file=$(mktemp)
    printf '%s' "$prompt" > "$claude_prompt_file"
    almanac_loop_agent_run \
      claude "${RALPH_MODEL:-}" "${RALPH_EFFORT:-}" workspace-write \
      "$claude_prompt_file" "$claude_result_file" "$claude_events_file" stream
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
      # Raw-output mode stays inline: the shared seam is always --json, but
      # verbose mode wants codex's plain output with no stream filter.
      codex \
        --ask-for-approval never \
        exec \
        --cd "$PWD" \
        --sandbox danger-full-access \
        --color never \
        --output-last-message "$codex_result" \
        "${MODEL_ARG[@]}" \
        "${EFFORT_ARG[@]}" \
        "$prompt"
    else
      # Default codex path routes through the shared agent_run seam in stream mode
      # rather than an inline codex exec (#66 — ralph migration onto the engine).
      # The seam builds the same invocation (--json --output-last-message,
      # --sandbox danger-full-access, plus --model/-c effort), tees the raw stream
      # to the session log, and pipes the live agent-message text through the same
      # jq filter — console output is unchanged. merge-stderr preserves once.sh's
      # `codex ... 2>&1 | tee` so codex's stderr still lands in the log.
      # RALPH_MODEL/RALPH_EFFORT pass straight through as the seam's model/effort,
      # and the seam preserves codex's exit via PIPESTATUS (once.sh kept pipefail
      # before; the seam owns that now). On failure we print the same log tail.
      codex_prompt_file=$(mktemp)
      printf '%s' "$prompt" > "$codex_prompt_file"
      if ! almanac_loop_agent_run \
        codex "${RALPH_MODEL:-}" "${RALPH_EFFORT:-}" danger-full-access \
        "$codex_prompt_file" "$codex_result" "$codex_log" stream merge-stderr; then
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
