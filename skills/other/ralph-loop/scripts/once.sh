#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <prd-name>"
  echo "Example: $0 auth-system"
  echo ""
  echo "Available PRDs:"
  ls plans/*.md 2>/dev/null | grep -v prompt | grep -v brief | sed 's|plans/||;s|\.md||' | sed 's/^/  /'
  exit 1
fi

PRD_NAME="$1"
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

ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

claude --permission-mode acceptEdits "${MODEL_ARG[@]}" "@$PROMPT Previous RALPH commits: $ralph_commits"
