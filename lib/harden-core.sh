#!/usr/bin/env bash
# harden-core.sh - Harden loop rubric bootstrap helpers

almanac_harden_slug() {
  local raw="$1"
  local slug

  slug="$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"

  if [ -z "$slug" ]; then
    slug="target"
  fi

  printf '%s\n' "$slug"
}

almanac_harden_rubric_path() {
  local root="$1"
  local target="$2"
  local slug

  slug="$(almanac_harden_slug "$target")"
  printf '%s/docs/plans/harden/%s/rubric.md\n' "$root" "$slug"
}

almanac_harden_write_rubric() {
  local root="$1"
  local target="$2"
  local goal="$3"
  local path dir

  path="$(almanac_harden_rubric_path "$root" "$target")"
  dir="$(dirname "$path")"

  if [ -e "$path" ]; then
    return 2
  fi

  mkdir -p "$dir"
  cat > "$path" <<EOF
# Harden Rubric

Target: $target
Status: draft

## Goal

$goal

## Acceptance

- [ ] Target behavior satisfies the stated goal.
- [ ] Blocking findings include a failing test, breaking input, or cited acceptance violation.
- [ ] Project feedback loops pass after fixes.

## In Scope

- $target

## Out of Scope

- Add non-goals here before running reviewers.

## Severity

Blocking findings must be falsifiable and reproducible against the current target.
Subjective or unreproducible findings are non-blocking notes.

## Context

- Add intentional decisions and false-positive preemptions here before running reviewers.
EOF
}

almanac_harden_approve_rubric() {
  local root="$1"
  local target="$2"
  local path approved_at tmp

  path="$(almanac_harden_rubric_path "$root" "$target")"

  if [ ! -f "$path" ]; then
    return 2
  fi

  if grep -Eq '^Status: approved$' "$path"; then
    return 3
  fi

  approved_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp "${path}.XXXXXX")"

  if grep -Eq '^Status: draft$' "$path"; then
    awk -v approved_at="$approved_at" '
      /^Status: draft$/ && !replaced {
        print "Status: approved"
        replaced = 1
        next
      }
      { print }
      END {
        print ""
        print "## Approval"
        print ""
        print "Approved: " approved_at
      }
    ' "$path" > "$tmp"
  else
    awk -v approved_at="$approved_at" '
      /^Target: / && !inserted {
        print
        print "Status: approved"
        inserted = 1
        next
      }
      { print }
      END {
        if (!inserted) {
          print "Status: approved"
        }
        print ""
        print "## Approval"
        print ""
        print "Approved: " approved_at
      }
    ' "$path" > "$tmp"
  fi

  mv "$tmp" "$path"
}
