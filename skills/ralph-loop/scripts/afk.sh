#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <prd-name> <iterations>"
  echo "Example: $0 auth-system 10"
  echo ""
  echo "Available PRDs:"
  ls plans/*.md 2>/dev/null | grep -v prompt | grep -v brief | sed 's|plans/||;s|\.md||' | sed 's/^/  /'
  exit 1
fi

PRD_NAME="$1"
ITERATIONS="$2"
PROMPT="plans/prompt-${PRD_NAME}.md"

# Model override: set RALPH_MODEL env var (e.g. RALPH_MODEL=claude-opus-4-7).
# Unset = use Claude Code's default (currently Sonnet).
MODEL_ARG=()
if [ -n "${RALPH_MODEL:-}" ]; then
  MODEL_ARG=(--model "$RALPH_MODEL")
fi

if [ ! -f "$PROMPT" ]; then
  echo "Error: $PROMPT not found. Run /ralph-loop $PRD_NAME to set up first."
  exit 1
fi

stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

for ((i=1; i<=$ITERATIONS; i++)); do
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  echo ""
  echo "======= ITERATION $i of $ITERATIONS ($PRD_NAME) ======="
  echo ""

  ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

  claude \
    --print \
    --output-format stream-json \
    --verbose \
    "${MODEL_ARG[@]}" \
    "@$PROMPT Previous RALPH commits: $ralph_commits" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    echo "Ralph complete after $i iterations."
    exit 0
  fi

  if [[ "$result" == *"<promise>ABORT</promise>"* ]]; then
    echo ""
    echo "Ralph aborted at iteration $i. Check the last commit message for details."
    exit 1
  fi
done

echo ""
echo "Ralph finished $ITERATIONS iterations. Tasks may remain — check with: git log --grep='RALPH($PRD_NAME)' --oneline"
