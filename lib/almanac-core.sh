#!/usr/bin/env bash
# almanac-core.sh — Shared utilities for almanac

# Resolve the almanac root directory
almanac_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Check if a skill directory has a valid SKILL.md
almanac_validate_skill() {
  local skill_dir="$1"
  local skill_file="$skill_dir/SKILL.md"

  if [ ! -f "$skill_file" ]; then
    echo "FAIL: missing SKILL.md in $skill_dir" >&2
    return 1
  fi

  # Check for YAML frontmatter
  local first_line
  first_line=$(head -1 "$skill_file")
  if [ "$first_line" != "---" ]; then
    echo "FAIL: SKILL.md in $skill_dir missing YAML frontmatter" >&2
    return 1
  fi

  # Check for required fields (extract between first and second ---)
  local frontmatter
  frontmatter=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$skill_file")

  if ! echo "$frontmatter" | grep -q '^name:'; then
    echo "FAIL: SKILL.md in $skill_dir missing 'name' field" >&2
    return 1
  fi

  if ! echo "$frontmatter" | grep -q '^description:'; then
    echo "FAIL: SKILL.md in $skill_dir missing 'description' field" >&2
    return 1
  fi

  return 0
}

# List all skill directories
almanac_list_skills() {
  local root
  root="$(almanac_root)"
  for dir in "$root"/skills/*/; do
    [ -d "$dir" ] && echo "$dir"
  done
}
