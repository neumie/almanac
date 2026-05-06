#!/usr/bin/env bash
# almanac-core.sh — Shared utilities for almanac

# Resolve the almanac root directory
almanac_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Check if a skill directory has a valid SKILL.md
# Validates against the Agent Skills Open Standard (agentskills.io/specification)
almanac_validate_skill() {
  local skill_dir="$1"
  local skill_file="$skill_dir/SKILL.md"
  local errors=0
  local warnings=0

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

  # Extract frontmatter (content between first and second ---)
  local frontmatter
  frontmatter=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$skill_file")

  # --- Required: name field ---
  local name
  name=$(echo "$frontmatter" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//')
  if [ -z "$name" ]; then
    echo "FAIL: SKILL.md in $skill_dir missing 'name' field" >&2
    errors=$((errors + 1))
  else
    # Name format: 1-64 chars, lowercase alphanumeric + hyphens, no leading/trailing/consecutive hyphens
    local name_len=${#name}
    if [ "$name_len" -gt 64 ]; then
      echo "FAIL: name '$name' exceeds 64 characters ($name_len)" >&2
      errors=$((errors + 1))
    fi
    if ! echo "$name" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
      echo "FAIL: name '$name' invalid format (must be lowercase alphanumeric + hyphens)" >&2
      errors=$((errors + 1))
    fi
    if echo "$name" | grep -q '\-\-'; then
      echo "FAIL: name '$name' contains consecutive hyphens" >&2
      errors=$((errors + 1))
    fi
    # Name must match directory name
    local dir_name
    dir_name=$(basename "$skill_dir")
    if [ "$name" != "$dir_name" ]; then
      echo "FAIL: name '$name' does not match directory '$dir_name'" >&2
      errors=$((errors + 1))
    fi
  fi

  # --- Required: description field ---
  # Description may span multiple lines (YAML multiline), extract the full value
  local description
  description=$(echo "$frontmatter" | awk '
    /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      desc = $0
      next
    }
    desc != "" && /^[[:space:]]/ {
      sub(/^[[:space:]]+/, " ")
      desc = desc $0
      next
    }
    desc != "" && /^[a-z]/ { exit }
    END { print desc }
  ')
  if [ -z "$description" ]; then
    echo "FAIL: SKILL.md in $skill_dir missing 'description' field" >&2
    errors=$((errors + 1))
  else
    local desc_len=${#description}
    if [ "$desc_len" -gt 1024 ]; then
      echo "FAIL: description exceeds 1024 characters ($desc_len)" >&2
      errors=$((errors + 1))
    fi
    # Cap at 220 chars to keep aggregated skills listing compact (token budget)
    if [ "$desc_len" -gt 220 ]; then
      echo "FAIL: description exceeds 220 characters ($desc_len) in $skill_dir — keep terse, drop redundant 'Use this whenever the user says...' restatements" >&2
      errors=$((errors + 1))
    fi
  fi

  # --- Frontmatter size check ---
  local fm_size
  fm_size=$(echo "$frontmatter" | wc -c | tr -d ' ')
  if [ "$fm_size" -gt 1024 ]; then
    echo "WARN: frontmatter exceeds 1024 characters ($fm_size)" >&2
    warnings=$((warnings + 1))
  fi

  # --- Optional: compatibility length ---
  local compat
  compat=$(echo "$frontmatter" | grep '^compatibility:' | head -1 | sed 's/^compatibility:[[:space:]]*//')
  if [ -n "$compat" ]; then
    local compat_len=${#compat}
    if [ "$compat_len" -gt 500 ]; then
      echo "WARN: compatibility exceeds 500 characters ($compat_len)" >&2
      warnings=$((warnings + 1))
    fi
  fi

  # --- Line count recommendation ---
  local line_count
  line_count=$(wc -l < "$skill_file" | tr -d ' ')
  if [ "$line_count" -gt 500 ]; then
    echo "WARN: SKILL.md has $line_count lines (recommended: under 500)" >&2
    warnings=$((warnings + 1))
  fi

  # --- Optional: metadata.dependencies validation ---
  # Check that each dependency references an existing skill directory
  local skills_root
  skills_root="$(dirname "$skill_dir")"
  local in_deps=0
  while IFS= read -r line; do
    # Detect the start of the dependencies list
    if echo "$line" | grep -qE '^[[:space:]]+dependencies:'; then
      in_deps=1
      continue
    fi
    # If we're in the dependencies list, read list items
    if [ "$in_deps" -eq 1 ]; then
      if echo "$line" | grep -qE '^[[:space:]]+-[[:space:]]'; then
        local dep
        dep=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
        if [ ! -d "$skills_root/$dep" ] || [ ! -f "$skills_root/$dep/SKILL.md" ]; then
          echo "FAIL: dependency '$dep' not found (required by $(basename "$skill_dir"))" >&2
          errors=$((errors + 1))
        fi
      else
        in_deps=0
      fi
    fi
  done <<< "$frontmatter"

  [ "$errors" -eq 0 ] && return 0 || return 1
}

# List all skill directories
almanac_list_skills() {
  local root
  root="$(almanac_root)"
  for dir in "$root"/skills/*/; do
    [ -d "$dir" ] && echo "$dir"
  done
}
