#!/usr/bin/env bash

loop_push_current_branch() {
  local branch upstream

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    return 1
  fi

  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)

  if [ "$upstream" = "origin/$branch" ]; then
    git push 2>&1
  else
    git push -u origin HEAD:"refs/heads/$branch" 2>&1
  fi
}
