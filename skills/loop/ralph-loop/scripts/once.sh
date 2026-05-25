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

stream_text='
  if .type == "system" and .subtype == "init" and (.model // "") != "" then
    "Claude model: \(.model)\r\n\n"
  elif .type == "assistant" then
    .message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"
  else
    empty
  end
'
codex_stream_text='
  if .type == "event_msg" and .payload.type == "agent_message" then
    .payload.message | . + "\n\n"
  else
    empty
  end
'

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

ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

case "$PROVIDER" in
  claude)
    prompt="@$PROMPT Previous RALPH commits: $ralph_commits"
    claude \
      --print \
      --output-format stream-json \
      --verbose \
      --permission-mode acceptEdits \
      "${MODEL_ARG[@]}" \
      "${EFFORT_ARG[@]}" \
      "$prompt" \
    | grep --line-buffered '^{' \
    | jq -Rj --unbuffered "fromjson? // empty | ( $stream_text )"
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
      set -o pipefail
      if ! codex \
        --ask-for-approval never \
        exec \
        --cd "$PWD" \
        --sandbox danger-full-access \
        --color never \
        --json \
        --output-last-message "$codex_result" \
        "${MODEL_ARG[@]}" \
        "${EFFORT_ARG[@]}" \
        "$prompt" 2>&1 \
        | tee "$codex_log" \
        | jq -Rj --unbuffered "fromjson? // empty | ( $codex_stream_text )"; then
        set +o pipefail
        echo "Codex failed. Last log lines:"
        tail -n 40 "$codex_log" || true
        rm -f "$codex_result"
        exit 1
      fi
      set +o pipefail
      cat "$codex_result"
    fi
    rm -f "$codex_result"
    ;;
esac
