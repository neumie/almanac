#!/usr/bin/env bash
# sync.sh — Check adapted skills for upstream changes

source "$ALMANAC_HOME/lib/core.sh"
source "$ALMANAC_HOME/lib/almanac-core.sh"

SHOW_DIFF=false
[ "${1:-}" = "--diff" ] && SHOW_DIFF=true

# Fetch SHA of a file from GitHub
_fetch_sha() {
  local api_path="$1"
  if command -v gh &>/dev/null; then
    gh api "$api_path" --jq '.sha' 2>/dev/null || true
  elif command -v curl &>/dev/null; then
    curl -sL "https://api.github.com/$api_path" 2>/dev/null | grep '"sha"' | head -1 | sed 's/.*"sha":[[:space:]]*"\([^"]*\)".*/\1/' || true
  else
    _die "Neither gh nor curl available"
  fi
}

_info "Checking adapted skills for upstream changes..."
echo ""

found=0
up_to_date=0
changed=0
errors=0

while IFS= read -r skill_dir; do
  [ -d "$skill_dir" ] || continue
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  # Extract upstream metadata from frontmatter
  frontmatter=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$skill_file")

  upstream=$(echo "$frontmatter" | grep 'upstream:' | head -1 | sed 's/^[[:space:]]*upstream:[[:space:]]*//' || true)
  [ -z "$upstream" ] && continue

  upstream_sha=$(echo "$frontmatter" | grep 'upstream-sha:' | head -1 | sed 's/^[[:space:]]*upstream-sha:[[:space:]]*//' || true)
  adapted_date=$(echo "$frontmatter" | grep 'adapted-date:' | head -1 | sed 's/^[[:space:]]*adapted-date:[[:space:]]*//' | tr -d '"' || true)

  skill_name=$(basename "$skill_dir")
  found=$((found + 1))

  # Parse repo and path from upstream (format: owner/repo/path)
  repo=$(echo "$upstream" | cut -d'/' -f1-2)
  skill_path=$(echo "$upstream" | cut -d'/' -f3-)

  # Get current SHA from GitHub API
  current_sha=$(_fetch_sha "repos/$repo/contents/$skill_path/SKILL.md")

  if [ -z "$current_sha" ]; then
    echo -e "  ${_RED}✗${_RESET} $skill_name: failed to fetch upstream"
    errors=$((errors + 1))
    continue
  fi

  if [ "$current_sha" = "$upstream_sha" ]; then
    echo -e "  ${_GREEN}✓${_RESET} $skill_name: up to date"
    up_to_date=$((up_to_date + 1))
  else
    echo -e "  ${_YELLOW}⚠${_RESET} $skill_name: upstream changed (adapted $adapted_date)"
    changed=$((changed + 1))

    if [ "$SHOW_DIFF" = true ]; then
      echo ""
      echo "    Upstream: https://github.com/$repo/blob/main/$skill_path/SKILL.md"
      echo "    Local SHA:    ${upstream_sha:0:12}"
      echo "    Upstream SHA: ${current_sha:0:12}"
      echo ""
    fi
  fi
done < <(almanac_list_skills)

echo ""
if [ "$found" -eq 0 ]; then
  _info "No skills with upstream tracking found"
else
  echo "Results: $found tracked, $up_to_date up to date, $changed changed, $errors errors"
  if [ "$changed" -gt 0 ] && [ "$SHOW_DIFF" = false ]; then
    _warn "Run 'almanac sync --diff' to see details"
  fi
fi
