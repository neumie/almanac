#!/usr/bin/env bash
# sync.sh — Check adapted skills for upstream changes.
# summary: Check adapted skills for upstream changes
# usage: almanac sync [--diff]
# group: maintenance
#
# Exit status is actionable: 0 = all tracked skills up to date, 1 = at least one
# upstream changed (run with --diff for links/SHAs), 2 = a fetch error occurred.

set -euo pipefail
source "$ALMANAC_HOME/lib/core.sh"
source "$ALMANAC_HOME/lib/almanac-core.sh"

SHOW_DIFF=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) printf '%s\n' "Usage: almanac sync [--diff]"; exit 0 ;;
    --diff)    SHOW_DIFF=true ;;
    *)         _die "Unknown sync option: $1" ;;
  esac
  shift
done

# Fetch SHA of a file from GitHub.
# Emits ONLY a valid 40-char git blob SHA. On 404 / rate-limit, `gh api` prints
# the JSON error body to stdout — without this guard that body gets captured and
# mistaken for a SHA, so every skill falsely reports "changed".
_fetch_sha() {
  local api_path="$1" raw=""
  if command -v gh &>/dev/null; then
    raw=$(gh api "$api_path" --jq '.sha' 2>/dev/null || true)
  elif command -v curl &>/dev/null; then
    raw=$(curl -sL "https://api.github.com/$api_path" 2>/dev/null | grep '"sha"' | head -1 | sed 's/.*"sha":[[:space:]]*"\([^"]*\)".*/\1/' || true)
  else
    _die "Neither gh nor curl available"
  fi
  if printf '%s' "$raw" | grep -Eq '^[0-9a-f]{40}$'; then
    printf '%s' "$raw"
  fi
}

_info "Checking adapted skills for upstream changes..."

found=0
up_to_date=0
changed=0
unbaselined=0
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
    _error "$skill_name: failed to fetch upstream (bad path or API error)"
    errors=$((errors + 1))
    continue
  fi

  if [ -z "$upstream_sha" ]; then
    _warn "$skill_name: no baseline upstream-sha recorded (upstream now ${current_sha:0:12})"
    unbaselined=$((unbaselined + 1))
    continue
  fi

  if [ "$current_sha" = "$upstream_sha" ]; then
    _success "$skill_name: up to date"
    up_to_date=$((up_to_date + 1))
  else
    _warn "$skill_name: upstream changed (adapted $adapted_date)"
    changed=$((changed + 1))

    if [ "$SHOW_DIFF" = true ]; then
      _info "  Upstream:     https://github.com/$repo/blob/main/$skill_path/SKILL.md"
      _info "  Local SHA:    ${upstream_sha:0:12}"
      _info "  Upstream SHA: ${current_sha:0:12}"
    fi
  fi
done < <(almanac_list_skills)

if [ "$found" -eq 0 ]; then
  _info "No skills with upstream tracking found"
  exit 0
fi

_info "Results: $found tracked, $up_to_date up to date, $changed changed, $unbaselined unbaselined, $errors errors"
if [ "$changed" -gt 0 ] && [ "$SHOW_DIFF" = false ]; then
  _warn "Run 'almanac sync --diff' to see details"
fi

# Actionable exit status (see header): fetch errors dominate, then drift.
if [ "$errors" -gt 0 ]; then
  exit 2
elif [ "$changed" -gt 0 ]; then
  exit 1
fi
exit 0
