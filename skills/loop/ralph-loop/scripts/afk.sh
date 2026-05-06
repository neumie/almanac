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

push_ralph_commits() {
  if git remote get-url origin >/dev/null 2>&1; then
    echo ""
    echo "======= PUSHING TO REMOTE ======="
    git push 2>&1 || echo "[warn] git push failed — push manually to share work."
  fi
}

# Observer: periodic drift detection. Runs in a background subshell, polls every
# RALPH_OBSERVE_INTERVAL seconds (default 900 = 15min). On HIGH drift, writes
# .ralph-stop so the next iteration exits gracefully. Set RALPH_NO_OBSERVE=1 to
# disable.
OBSERVE_INTERVAL="${RALPH_OBSERVE_INTERVAL:-900}"
OBSERVE_LOG="plans/observer-${PRD_NAME}.log"
OBSERVER_PID=""

run_observer_once() {
  local recent_commits
  recent_commits=$(git log --grep="RALPH(${PRD_NAME})" -n 10 --format="%h %ad %s%n%b---" --date=short 2>/dev/null || echo "No RALPH commits yet")

  local observer_prompt
  observer_prompt="Read the PRD context at @${PROMPT}. You are an observer watching an autonomous coding loop named ralph(${PRD_NAME}).

Recent RALPH commits (last 10):
${recent_commits}

Detect drift. Drift includes (non-exhaustive):
- Repeated tasks or task ping-pong
- Off-PRD topics — work unrelated to the PRD
- ABORT loops — repeated aborts on the same blocker
- Vague 'no real progress' commits
- Scope creep beyond the PRD
- Test rot or growing failures
- Anything else that suggests wasted effort

Output exactly two lines, no preamble:
DRIFT_LEVEL: <low|medium|high>
REASON: <one paragraph explaining the assessment>

Be conservative. Only output 'high' with clear evidence — when 'high', the loop will be stopped via .ralph-stop."

  local result
  result=$(claude \
    --print \
    --permission-mode plan \
    "${MODEL_ARG[@]}" \
    "$observer_prompt" 2>&1 || true)

  {
    echo ""
    echo "===== OBSERVE $(date -Iseconds) ====="
    echo "$result"
  } >> "$OBSERVE_LOG"

  if echo "$result" | grep -qiE '^[[:space:]]*DRIFT_LEVEL:[[:space:]]*high'; then
    {
      echo ""
      echo "======= OBSERVER: HIGH DRIFT DETECTED — writing .ralph-stop ======="
      echo "$result"
    } >&2
    touch .ralph-stop
  fi
}

start_observer() {
  if [ "${RALPH_NO_OBSERVE:-}" = "1" ]; then
    echo "[observer] disabled (RALPH_NO_OBSERVE=1)"
    return
  fi
  mkdir -p "$(dirname "$OBSERVE_LOG")"
  {
    echo ""
    echo "===== OBSERVER STARTED $(date -Iseconds) interval=${OBSERVE_INTERVAL}s ====="
  } >> "$OBSERVE_LOG"
  (
    while true; do
      sleep "$OBSERVE_INTERVAL"
      [ -f .ralph-stop ] && exit 0
      run_observer_once
    done
  ) &
  OBSERVER_PID=$!
  echo "[observer] started (PID $OBSERVER_PID, interval ${OBSERVE_INTERVAL}s, log $OBSERVE_LOG)"
}

stop_observer() {
  if [ -n "${OBSERVER_PID:-}" ]; then
    kill "$OBSERVER_PID" 2>/dev/null || true
    wait "$OBSERVER_PID" 2>/dev/null || true
  fi
}

cleanup_all() {
  stop_observer
  [ -n "${tmpfile:-}" ] && rm -f "$tmpfile"
}
trap cleanup_all EXIT INT TERM

start_observer

for ((i=1; i<=$ITERATIONS; i++)); do
  if [ -f .ralph-stop ]; then
    echo ""
    echo "======= STOP SIGNAL DETECTED (.ralph-stop) ======="
    echo "Exiting after iteration $((i-1)) of $ITERATIONS."
    rm -f .ralph-stop
    push_ralph_commits
    exit 0
  fi

  tmpfile=$(mktemp)

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
    push_ralph_commits
    exit 0
  fi

  if [[ "$result" == *"<promise>ABORT</promise>"* ]]; then
    echo ""
    echo "Ralph aborted at iteration $i. Check the last commit message for details."
    push_ralph_commits
    exit 1
  fi
done

echo ""
echo "Ralph finished $ITERATIONS iterations. Tasks may remain — check with: git log --grep='RALPH($PRD_NAME)' --oneline"
push_ralph_commits
