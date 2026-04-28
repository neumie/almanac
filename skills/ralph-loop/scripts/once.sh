#!/bin/bash
set -e

if [ ! -f "plans/prompt.md" ]; then
  echo "Error: plans/prompt.md not found. Run /ralph-loop to set up first."
  exit 1
fi

ralph_commits=$(git log --grep="RALPH" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

claude --permission-mode acceptEdits "@plans/prompt.md Previous RALPH commits: $ralph_commits"
