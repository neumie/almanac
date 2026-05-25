#!/usr/bin/env bash
# harden-core.sh - Harden loop rubric bootstrap + reviewer helpers

# The reviewer path leans on the shared loop engine (role config + agent runner).
# Source it idempotently so harden-core works both through bin/almanac and when a
# test sources this file directly. pwd -P resolves the install symlink so the
# sibling loop-core.sh is found from either path.
if ! declare -F almanac_loop_agent_run >/dev/null 2>&1; then
  __harden_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/loop-core.sh
  source "$__harden_core_dir/loop-core.sh"
  unset __harden_core_dir
fi

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

almanac_harden_default_lens() {
  printf '%s\n' "correctness"
}

# Build the fixed prompt for one read-only reviewer over a target, including the
# JSON-Lines findings schema. Kept separate so the schema can grow without
# touching orchestration. (Prompt strings are not asserted in tests by design.)
almanac_harden_reviewer_prompt() {
  local target="$1"
  local lens="${2:-correctness}"

  cat <<EOF
You are a read-only code reviewer. Lens: ${lens}.

Review the target below for ${lens} defects only. You cannot modify any files;
this is a read-only review.

Target: ${target}

Report each defect as one JSON object per line (JSON Lines) and output nothing
else — no prose, no markdown fences. Each object must use this schema:

{"lens":"${lens}","severity":"high|medium|low","location":"<file:line or symbol>","claim":"<one-line defect>","demonstration":"<failing test, breaking input, or cited rubric criterion>"}

Only report a defect you can demonstrate with a failing test, a specific breaking
input, or a cited criterion. If you find no demonstrable defects, output nothing.
EOF
}

# Normalize the reviewer's JSON-Lines result into TSV rows
# (lens, severity, location, claim, demonstration). Malformed lines are dropped
# cleanly. Prefers jq; falls back to a flat-field awk extractor when jq is absent
# so harden keeps almanac's near-zero-dependency promise.
almanac_harden_findings_tsv() {
  local result_file="$1"

  [ -f "$result_file" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    jq -Rr '
      fromjson?
      | select(type == "object")
      | [(.lens // ""), (.severity // ""), (.location // ""), (.claim // ""), (.demonstration // "")]
      | @tsv
    ' "$result_file" 2>/dev/null
    return 0
  fi

  awk '
    function field(line, key,   v) {
      v = line
      if (v ~ ("\"" key "\"[ \t]*:[ \t]*\"")) {
        sub(".*\"" key "\"[ \t]*:[ \t]*\"", "", v)
        sub("\".*", "", v)
        return v
      }
      return ""
    }
    /"claim"[ \t]*:/ {
      printf "%s\t%s\t%s\t%s\t%s\n", \
        field($0, "lens"), field($0, "severity"), field($0, "location"), \
        field($0, "claim"), field($0, "demonstration")
    }
  ' "$result_file"
}

# Print parsed findings as a readable list. Reports "No findings reported." when
# the reviewer returned nothing parseable.
almanac_harden_format_findings() {
  local result_file="$1"
  local lens severity location claim demonstration count

  count=0
  while IFS=$'\t' read -r lens severity location claim demonstration; do
    [ -n "${lens}${severity}${location}${claim}${demonstration}" ] || continue
    printf -- '- [%s] %s: %s\n' "${severity:-?}" "${lens:-?}" "${claim:-?}"
    [ -n "$location" ] && printf '    where: %s\n' "$location"
    [ -n "$demonstration" ] && printf '    demo:  %s\n' "$demonstration"
    count=$((count + 1))
  done < <(almanac_harden_findings_tsv "$result_file")

  if [ "$count" -eq 0 ]; then
    printf '%s\n' "No findings reported."
  fi
}

# --- Findings ledger -----------------------------------------------------------
#
# Canonical finding schema (one JSON object per reviewer line, see the reviewer
# prompt above): lens, severity, location, claim, demonstration. The ledger adds
# three adjudication fields when a finding is recorded:
#   id            - deterministic fingerprint of (lens, location, claim)
#   status        - open | fixed | rejected-subjective | wontfix-per-context
#   round         - the review round that first raised the finding
#   adjudication  - free-text note (why rejected / how fixed); empty when open
#
# Findings persist append-only to findings.md next to the target's rubric.md.
# Each finding is one markdown section keyed by its id, so the file is both
# human-readable and re-parseable (dedupe + open-blocking query read it back).

almanac_harden_ledger_path() {
  local root="$1"
  local target="$2"
  local slug

  slug="$(almanac_harden_slug "$target")"
  printf '%s/docs/plans/harden/%s/findings.md\n' "$root" "$slug"
}

# Deterministic finding identity. Two reviewer reports of the same defect
# (same lens, same place, same claim) collapse to one id so re-raising a
# finding never re-adds it. Demonstration is deliberately excluded: a reworded
# repro must not look like a new finding. cksum keeps this dependency-free.
almanac_harden_finding_id() {
  local lens="$1"
  local location="$2"
  local claim="$3"
  local sum

  sum="$(printf '%s\037%s\037%s' "$lens" "$location" "$claim" | cksum | awk '{print $1}')"
  printf 'f-%s\n' "$sum"
}

almanac_harden_ledger_init() {
  local path="$1"
  local dir

  dir="$(dirname "$path")"
  mkdir -p "$dir"

  if [ ! -f "$path" ]; then
    {
      printf '%s\n\n' "# Findings Ledger"
      printf '%s\n' "<!-- Append-only finding records managed by 'almanac harden'. One section per finding. -->"
    } > "$path"
  fi
}

# True when the ledger already holds a finding with this id.
almanac_harden_ledger_has() {
  local path="$1"
  local id="$2"

  [ -f "$path" ] || return 1
  grep -Fxq -- "## $id" "$path"
}

# Append one finding section. Returns 1 (and writes nothing) when the id is
# already present, so callers can count genuinely-new findings. Creates the
# ledger file with its header on first write.
almanac_harden_ledger_append_entry() {
  [ "$#" -ge 7 ] || return 2

  local path="$1"
  local id="$2"
  local lens="$3"
  local severity="$4"
  local location="$5"
  local claim="$6"
  local demonstration="$7"
  local status="${8:-open}"
  local round="${9:-1}"
  local adjudication="${10:-}"

  almanac_harden_ledger_init "$path"

  if almanac_harden_ledger_has "$path" "$id"; then
    return 1
  fi

  {
    printf '\n## %s\n\n' "$id"
    printf -- '- lens: %s\n' "$lens"
    printf -- '- severity: %s\n' "$severity"
    printf -- '- location: %s\n' "$location"
    printf -- '- claim: %s\n' "$claim"
    printf -- '- demonstration: %s\n' "$demonstration"
    printf -- '- status: %s\n' "$status"
    printf -- '- round: %s\n' "$round"
    printf -- '- adjudication: %s\n' "$adjudication"
  } >> "$path"
}

# Normalize a reviewer's JSON-Lines result into ledger-entry TSV rows
# (id, lens, severity, location, claim, demonstration, status, round,
# adjudication). New findings are status=open with an empty adjudication.
# Malformed reviewer lines are dropped cleanly (via almanac_harden_findings_tsv).
almanac_harden_parse_findings() {
  local result_file="$1"
  local round="${2:-1}"
  local lens severity location claim demonstration id

  while IFS=$'\t' read -r lens severity location claim demonstration; do
    [ -n "${lens}${severity}${location}${claim}${demonstration}" ] || continue
    id="$(almanac_harden_finding_id "$lens" "$location" "$claim")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$lens" "$severity" "$location" "$claim" "$demonstration" "open" "$round" ""
  done < <(almanac_harden_findings_tsv "$result_file")
}

# Parse a reviewer result and append each new finding to the ledger, deduping
# against everything already adjudicated. Prints the count of findings actually
# added (duplicates do not count).
almanac_harden_ledger_record() {
  local path="$1"
  local result_file="$2"
  local round="${3:-1}"
  local id lens severity location claim demonstration status r adjudication
  local added=0

  while IFS=$'\t' read -r id lens severity location claim demonstration status r adjudication; do
    [ -n "$id" ] || continue
    if almanac_harden_ledger_append_entry \
      "$path" "$id" "$lens" "$severity" "$location" "$claim" \
      "$demonstration" "$status" "$r" "$adjudication"; then
      added=$((added + 1))
    fi
  done < <(almanac_harden_parse_findings "$result_file" "$round")

  printf '%s\n' "$added"
}

# Emit the open blocking findings as TSV rows
# (id, lens, severity, location, claim, demonstration). Only status=open
# entries qualify; fixed / rejected-subjective / wontfix-per-context never gate.
almanac_harden_ledger_open_blocking() {
  local path="$1"

  [ -f "$path" ] || return 0

  awk '
    function flush() {
      if (id != "" && status == "open") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, lens, severity, location, claim, demonstration
      }
    }
    /^## / {
      flush()
      id = substr($0, 4)
      lens = ""; severity = ""; location = ""; claim = ""; demonstration = ""; status = ""
      next
    }
    /^- / {
      line = substr($0, 3)
      p = index(line, ":")
      if (p == 0) next
      key = substr(line, 1, p - 1)
      val = substr(line, p + 1)
      sub(/^ /, "", val)
      if (key == "lens") lens = val
      else if (key == "severity") severity = val
      else if (key == "location") location = val
      else if (key == "claim") claim = val
      else if (key == "demonstration") demonstration = val
      else if (key == "status") status = val
    }
    END { flush() }
  ' "$path"
}

# Run a single read-only reviewer over a target via the shared agent runner and
# print its findings. Resolves provider/model/effort through the shared role
# config (HARDEN_REVIEWER[_<LENS>]_{PROVIDER,MODEL,EFFORT}). _die on a missing
# target or a failed provider run.
almanac_harden_review() {
  local root="$1"
  local target="$2"
  local lens="${3:-}"
  local target_path provider model effort prompt_file result_file rc

  [ -n "$lens" ] || lens="$(almanac_harden_default_lens)"

  case "$target" in
    /*) target_path="$target" ;;
    *)  target_path="$root/$target" ;;
  esac

  if [ ! -e "$target_path" ]; then
    _die "Harden target not found: $target"
  fi

  provider="$(almanac_loop_role_field "harden" "reviewer" "$lens" "provider" "claude")"
  model="$(almanac_loop_role_field "harden" "reviewer" "$lens" "model" "")"
  effort="$(almanac_loop_role_field "harden" "reviewer" "$lens" "effort" "")"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-result.XXXXXX")"

  almanac_harden_reviewer_prompt "$target" "$lens" > "$prompt_file"

  _info "Reviewing $target (lens: $lens, provider: $provider, read-only)"

  rc=0
  almanac_loop_agent_run "$provider" "$model" "$effort" "read-only" "$prompt_file" "$result_file" >/dev/null || rc=$?

  if [ "$rc" -ne 0 ]; then
    rm -f "$prompt_file" "$result_file"
    _die "Reviewer ($provider) failed with exit $rc"
  fi

  _info "Findings:"
  almanac_harden_format_findings "$result_file"

  rm -f "$prompt_file" "$result_file"
}
