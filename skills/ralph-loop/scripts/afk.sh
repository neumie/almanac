#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 10"
  exit 1
fi

if [ ! -f "plans/prompt.md" ]; then
  echo "Error: plans/prompt.md not found. Run /ralph-loop to set up first."
  exit 1
fi

stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

for ((i=1; i<=$1; i++)); do
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  echo ""
  echo "======= ITERATION $i of $1 ======="
  echo ""

  ralph_commits=$(git log --grep="RALPH" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

  claude \
    --print \
    --output-format stream-json \
    --verbose \
    "@plans/prompt.md Previous RALPH commits: $ralph_commits" \
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
echo "Ralph finished $1 iterations. Tasks may remain — check with: git log --grep=RALPH --oneline"
