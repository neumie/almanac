#!/usr/bin/env bash
# harden-core.sh - Harden loop rubric bootstrap + reviewer helpers

# loop-core.sh (the old shared-engine barrel) is deleted; harden-core sources the
# focused modules it actually uses, each directly and idempotently so it works
# both through bin/almanac and when a test sources this file directly. core.sh
# is sourced literally (it owns the helper); the other deps go through
# _almanac_source_sibling so the boilerplate stays minimal.
if ! declare -F _error >/dev/null 2>&1; then
  __harden_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__harden_core_dir/core.sh"
  unset __harden_core_dir
fi

# Explicit deps (each declared module is the contract surface this file consumes;
# transitive availability is not relied on).
_almanac_source_sibling agent.sh    almanac_loop_agent_capture   # agent run shapes (ratify/fixer)
_almanac_source_sibling run.sh      almanac_loop_register_run    # run registry + worker paths/health
_almanac_source_sibling worker.sh   almanac_loop_worker_start    # worker orchestration (reviewer/fixer fan-out)
_almanac_source_sibling ui.sh       almanac_loop_ui_render       # gum-or-plain dashboard seam
_almanac_source_sibling role.sh     almanac_loop_role_resolve    # per-role provider/model/effort resolution
_almanac_source_sibling feedback.sh almanac_loop_feedback_run    # objective fixer gate

# --- Role config (per-role provider / model / effort) --------------------------
#
# Each harden role selects its own agent config:
#   conductor - judges/ratifies findings and declares convergence
#   reviewer  - one read-only reviewer per lens (lens -> provider map)
#   fixer     - the single sequential write-capable fixer
#
# Resolution layers, most specific first, via the shared loop resolver:
#   provider: HARDEN_<ROLE>[_<LENS>]_PROVIDER -> HARDEN_<ROLE>_PROVIDER
#             -> HARDEN_PROVIDER -> $(almanac_provider_default) (the central
#             default-selection policy — active-env provider, else preference
#             order; mirrors converge so neither loop hardcodes a provider name)
#   model:    HARDEN_<ROLE>[_<LENS>]_MODEL    -> HARDEN_<ROLE>_MODEL
#             -> HARDEN_MODEL -> "" (the provider's own default)
#   effort:   HARDEN_<ROLE>[_<LENS>]_EFFORT   -> HARDEN_<ROLE>_EFFORT
#             -> HARDEN_EFFORT -> "" (the provider's own default)
#
# Only reviewers consult the lens, so providers can be mixed across lenses in one
# round; conductor and fixer are single-instance and ignore it. Resolution reads
# ONLY HARDEN_* (and the shared loop env) — never any host marker — so the tuple
# is identical whether the run was launched from Claude Code or Codex.
#
# Emits one tab-separated `provider<TAB>model<TAB>effort` line — the deep form
# callers use to populate three locals in one read:
#   IFS=$'\t' read -r provider model effort < <(almanac_harden_role_resolve reviewer "$lens")
# Pre-deepening, every callsite triple-called a thin `_role_field` wrapper that
# itself re-walked the env layering for each field — nine env lookups per
# worker spawn for three values. Returns 2 on unknown role.
almanac_harden_role_resolve() {
  local role="$1"
  local lens="${2:-}"

  case "$role" in
    reviewer) ;;
    conductor | fixer) lens="" ;;
    *) return 2 ;;
  esac

  almanac_loop_role_resolve "harden" "$role" "$lens" "$(almanac_provider_default)" "" ""
}

almanac_harden_rubric_path() {
  local root="$1"
  local target="$2"
  local slug

  slug="$(almanac_loop_slug "$target")"
  printf '%s/rubric.md\n' "$(almanac_loop_plan_dir harden "$root" "$slug")"
}

# Resolve a target argument to its absolute filesystem path: absolute targets
# pass through, relative targets are interpreted under $root. Path resolution
# only — callers do their own existence check (some sites operate on the
# ledger and don't need the target to still exist on disk).
almanac_harden_target_path() {
  local root="$1"
  local target="$2"
  case "$target" in
    /*) printf '%s\n' "$target" ;;
    *)  printf '%s/%s\n' "$root" "$target" ;;
  esac
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

# Return 0 when the rubric is approved (locked), non-zero otherwise — including
# when it is still a draft or the file is absent. Pure read; the loop gates on
# this so reviewers never run against a half-authored bar.
almanac_harden_rubric_approved() {
  local rubric_path="$1"

  [ -f "$rubric_path" ] || return 1
  grep -Eq '^Status: approved$' "$rubric_path"
}

# Emit the rubric's acceptance criteria — the bar reviewers and ratification work
# against. Prints every bullet line under the `## Acceptance` heading up to the
# next `## ` section. Empty when the rubric or section is absent. Pure read.
almanac_harden_rubric_acceptance() {
  local path="$1"

  [ -f "$path" ] || return 0

  awk '
    /^## Acceptance[[:space:]]*$/ { in_acc = 1; next }
    in_acc && /^## / { in_acc = 0 }
    in_acc && /^- / { print }
  ' "$path"
}

# Append one acceptance criterion to the rubric's `## Acceptance` section. This is
# how a ratified finding grows the bar: monotonic (criteria are only added), visible
# (a clean diff), and append-only. The new `- [ ] <criterion>` lands at the end of
# the Acceptance block, before the next section. Idempotent: an identical criterion
# is never re-added (returns 1, writes nothing) so re-ratifying a reopened finding
# cannot duplicate it. Returns 2 when the rubric or its Acceptance section is absent.
almanac_harden_rubric_append_criterion() {
  local path="$1"
  local criterion="$2"
  local tmp

  [ -f "$path" ] || return 2
  grep -q '^## Acceptance[[:space:]]*$' "$path" || return 2

  if grep -Fxq -- "- [ ] $criterion" "$path" || \
      grep -Fxq -- "- [x] $criterion" "$path"; then
    return 1
  fi

  tmp="$(mktemp "${path}.XXXXXX")"
  awk -v crit="$criterion" '
    /^## Acceptance[[:space:]]*$/ { print; in_acc = 1; next }
    in_acc && /^## / {
      print "- [ ] " crit
      inserted = 1
      in_acc = 0
      for (i = 1; i <= nb; i++) print blanks[i]
      nb = 0
      print
      next
    }
    in_acc && /^[[:space:]]*$/ { nb++; blanks[nb] = $0; next }
    in_acc {
      for (i = 1; i <= nb; i++) print blanks[i]
      nb = 0
      print
      next
    }
    { print }
    END {
      if (in_acc && !inserted) {
        print "- [ ] " crit
        for (i = 1; i <= nb; i++) print blanks[i]
      }
    }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

# --- Rubric immutability guard -------------------------------------------------
#
# The rubric is the contract, and during a run it is immutable to agents: the
# goalposts move only by a deliberate human act (the developer editing the file
# between runs / approving it) or the conductor's controlled append at
# ratification (almanac_harden_rubric_append_criterion — a visible, monotonic
# diff that runs OUTSIDE the reviewer/fixer phase). Reviewers run read-only and
# cannot write the rubric; the fixer (later slice) has write access and could.
# These two helpers bracket an agent phase — snapshot before, verify after — and
# revert any agent edit, so a stray agent write during a run cannot lower the bar.

# Snapshot the rubric to a protected temp copy and echo the snapshot path so the
# caller can pass it to almanac_harden_rubric_verify. Returns 2 (echoes nothing)
# when no rubric exists — an ad-hoc bare run with no drafted contract has nothing
# to guard.
almanac_harden_rubric_snapshot() {
  local rubric_path="$1"
  local snap

  [ -f "$rubric_path" ] || return 2

  snap="$(mktemp "${TMPDIR:-/tmp}/almanac-rubric-lock.XXXXXX")"
  cp "$rubric_path" "$snap"
  printf '%s\n' "$snap"
}

# Verify the rubric is byte-identical to its snapshot; if an agent modified it
# during the guarded phase, revert it and warn (the contract is immutable to
# agents). Discards the snapshot either way. Returns 1 when a modification was
# reverted, 0 when unchanged, 2 when the snapshot is missing.
almanac_harden_rubric_verify() {
  local rubric_path="$1"
  local snap="$2"

  [ -n "$snap" ] && [ -f "$snap" ] || return 2

  if ! cmp -s "$rubric_path" "$snap"; then
    cp "$snap" "$rubric_path"
    rm -f "$snap"
    _warn "Rubric was modified during the run; reverted (contract is immutable to agents — amend it directly between runs)."
    return 1
  fi

  rm -f "$snap"
  return 0
}

# Emit the configured reviewer lens set, one lens per line. Defaults to the five
# PRD lenses; override at runtime via HARDEN_LENSES (comma- or whitespace-
# separated).
almanac_harden_lenses() {
  local raw="${HARDEN_LENSES:-correctness security perf edge-cases contracts}"

  # Trailing newline matters: a `read` loop consumer drops a final line that
  # lacks one, which would silently swallow the last lens.
  printf '%s\n' "$raw" | tr -s ', \t' '\n' | sed '/^$/d'
}

almanac_harden_max_reviewers() {
  printf '%s\n' "${HARDEN_MAX_REVIEWERS:-16}"
}

# Build the fixed prompt for one read-only reviewer over a target, including the
# JSON-Lines findings schema. When a rubric path is given and exists, the rubric's
# acceptance criteria are embedded as the bar the reviewer judges against, so
# reviewers consume the contract rather than an implicit standard. An optional
# steering directive (4th arg) is embedded too, so an operator who redirects the
# run at the HITL checkpoint (e.g. "focus on the auth module") reaches the
# reviewers on the next round. Kept separate so the schema can grow without
# touching orchestration. (Exact prompt wording is not asserted in tests by
# design; that the rubric bar and the steer directive are consumed is.)
almanac_harden_reviewer_prompt() {
  local target="$1"
  local lens="${2:-correctness}"
  local rubric_path="${3:-}"
  local directive="${4:-}"
  local rubric_bar=""

  if [ -n "$rubric_path" ] && [ -f "$rubric_path" ]; then
    rubric_bar="$(almanac_harden_rubric_acceptance "$rubric_path")"
  fi

  cat <<EOF
You are a read-only code reviewer. Lens: ${lens}.

Review the target below for ${lens} defects only. You cannot modify any files;
this is a read-only review.

Target: ${target}
EOF

  if [ -n "$rubric_bar" ]; then
    cat <<EOF

Judge the target against this acceptance bar (the rubric contract). A finding is
only blocking if it violates a criterion below or demonstrably breaks behavior:

${rubric_bar}
EOF
  fi

  if [ -n "$directive" ]; then
    cat <<EOF

The operator steered this run with the directive below — follow it and prioritize
the findings it points you toward:

${directive}
EOF
  fi

  cat <<EOF

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
      | {
          lens: (.lens // ""),
          severity: (.severity // ""),
          location: (.location // ""),
          claim: (.claim // ""),
          demonstration: (.demonstration // "")
        }
      | select(
          (.lens | type == "string" and length > 0) and
          (.severity | type == "string" and length > 0) and
          (.location | type == "string" and length > 0) and
          (.claim | type == "string" and length > 0) and
          (.demonstration | type == "string" and length > 0)
        )
      | [.lens, .severity, .location, .claim, .demonstration]
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
      lens = field($0, "lens")
      severity = field($0, "severity")
      location = field($0, "location")
      claim = field($0, "claim")
      demonstration = field($0, "demonstration")
      if (lens != "" && severity != "" && location != "" && claim != "" && demonstration != "") {
        printf "%s\t%s\t%s\t%s\t%s\n", lens, severity, location, claim, demonstration
      }
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

  slug="$(almanac_loop_slug "$target")"
  printf '%s/findings.md\n' "$(almanac_loop_plan_dir harden "$root" "$slug")"
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

  almanac_harden_ledger_append_entry_unchecked \
    "$path" "$id" "$lens" "$severity" "$location" "$claim" \
    "$demonstration" "$status" "$round" "$adjudication"
}

# Append one already-deduped finding section. Callers must have initialised the
# ledger and decided the id is new; this keeps bulk ingestion from grepping the
# growing ledger once per finding.
almanac_harden_ledger_append_entry_unchecked() {
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

# Walk the ledger markdown file and emit one TSV row per finding section:
#   id, lens, severity, location, claim, demonstration, status, round, adjudication
# Missing path -> emits nothing (return 0). This is the SINGLE markdown→record
# walker for the ledger; every read-side consumer (open_blocking, status,
# record's existing-statuses snapshot) slices these rows instead of re-parsing
# the markdown. Schema list lives in this one awk — adding a finding field is
# one variable, one case branch, one printf %s here, never N synchronised
# parsers. Format mirrors almanac_harden_parse_findings (9 fields, same order)
# so reviewer-parsed and ledger-parsed rows are directly comparable.
almanac_harden_ledger_to_tsv() {
  local path="$1"
  [ -f "$path" ] || return 0
  awk '
    function flush() {
      if (id != "") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, lens, severity, location, claim, demonstration, status, round, adjudication
      }
    }
    /^## / {
      flush()
      id = substr($0, 4)
      lens = ""; severity = ""; location = ""; claim = ""; demonstration = ""
      status = ""; round = ""; adjudication = ""
      next
    }
    /^- / {
      line = substr($0, 3)
      p = index(line, ":")
      if (p == 0) next
      key = substr(line, 1, p - 1)
      val = substr(line, p + 1)
      sub(/^ /, "", val)
      if      (key == "lens")          lens = val
      else if (key == "severity")      severity = val
      else if (key == "location")      location = val
      else if (key == "claim")         claim = val
      else if (key == "demonstration") demonstration = val
      else if (key == "status")        status = val
      else if (key == "round")         round = val
      else if (key == "adjudication")  adjudication = val
    }
    END { flush() }
  ' "$path"
}

# Parse a reviewer result and append each new finding to the ledger, deduping
# against everything already adjudicated. Prints the count of findings actually
# added (duplicates do not count).
almanac_harden_ledger_record() {
  local path="$1"
  local result_file="$2"
  local round="${3:-1}"
  local parsed statuses actions reopen_ids action
  local id lens severity location claim demonstration status r adjudication
  local added=0

  almanac_harden_ledger_init "$path"

  parsed="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-findings.XXXXXX")"
  statuses="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-statuses.XXXXXX")"
  actions="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-actions.XXXXXX")"
  reopen_ids="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-reopen.XXXXXX")"

  almanac_harden_parse_findings "$result_file" "$round" > "$parsed"

  almanac_harden_ledger_to_tsv "$path" | awk -F'\t' '{ print $1 "\t" $7 }' > "$statuses"

  awk '
    BEGIN { FS = "\t" }
    FILENAME == ARGV[1] { existing[$1] = $2; next }
    $1 == "" { next }
    seen[$1]++ { next }
    !($1 in existing) {
      print "append\t" $0
      next
    }
    existing[$1] == "fixed" {
      print "reopen\t" $0
      next
    }
  ' "$statuses" "$parsed" > "$actions"

  while IFS=$'\t' read -r action id lens severity location claim demonstration status r adjudication; do
    [ -n "$id" ] || continue
    case "$action" in
      append)
        almanac_harden_ledger_append_entry_unchecked \
          "$path" "$id" "$lens" "$severity" "$location" "$claim" \
          "$demonstration" "$status" "$r" "$adjudication"
        added=$((added + 1))
        ;;
      reopen)
        printf '%s\n' "$id" >> "$reopen_ids"
        ;;
    esac
  done < "$actions"

  if [ -s "$reopen_ids" ]; then
    almanac_harden_ledger_set_status_many "$path" "open" \
      "re-raised by reviewer at round $round; pending ratification" < "$reopen_ids"
  fi

  rm -f "$parsed" "$statuses" "$actions" "$reopen_ids"

  printf '%s\n' "$added"
}

# Emit the open blocking findings as TSV rows
# (id, lens, severity, location, claim, demonstration). Only status=open
# entries qualify; fixed / rejected-subjective / wontfix-per-context never gate.
almanac_harden_ledger_open_blocking() {
  almanac_harden_ledger_to_tsv "$1" \
    | awk -F'\t' 'BEGIN { OFS="\t" } $7 == "open" { print $1, $2, $3, $4, $5, $6 }'
}

# Print the recorded status of the finding with this id (empty when the id is
# not in the ledger). Used by ratification to tell new from already-adjudicated.
almanac_harden_ledger_status() {
  local path="$1"
  local id="$2"

  almanac_harden_ledger_to_tsv "$path" \
    | awk -F'\t' -v want="$id" '$1 == want { print $7; exit }'
}

# Rewrite the status (and adjudication note) of the finding with this id in
# place, leaving every other field and finding untouched. Returns 1 when the
# ledger file is absent. Thin sugar over `_set_status_many` — the canonical
# in-place ledger-rewrite engine — so the awk program that knows the ledger
# layout lives in ONE place; adding a ledger field is a one-spot change.
almanac_harden_ledger_set_status() {
  local path="$1" id="$2" status="$3" adjudication="${4:-}"
  printf '%s\n' "$id" | almanac_harden_ledger_set_status_many "$path" "$status" "$adjudication"
}

# Rewrite status/adjudication for many finding ids in one ledger pass. Reads ids
# from stdin, one per line. Used after a batch fix so marking N findings fixed is
# O(ledger) instead of N full ledger rewrites.
almanac_harden_ledger_set_status_many() {
  local path="$1"
  local status="$2"
  local adjudication="${3:-}"
  local ids tmp

  [ -f "$path" ] || return 1

  ids="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-ids.XXXXXX")"
  cat > "$ids"
  [ -s "$ids" ] || { rm -f "$ids"; return 0; }

  tmp="$(mktemp "${path}.XXXXXX")"
  awk -v ids="$ids" -v status="$status" -v adj="$adjudication" '
    BEGIN {
      while ((getline line < ids) > 0) {
        if (line != "") wanted[line] = 1
      }
      close(ids)
    }
    /^## / { cur = substr($0, 4); print; next }
    (cur in wanted) && /^- status:/ { print "- status: " status; next }
    (cur in wanted) && /^- adjudication:/ { print "- adjudication: " adj; next }
    { print }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
  rm -f "$ids"
}

# --- Ratification engine -------------------------------------------------------
#
# A finding is "blocking" only if its demonstration objectively reproduces
# against the current target — never on a reviewer's assertion alone. Execution
# of the demonstration is isolated behind a seam (almanac_harden_demo_reproduces)
# so the decision logic is testable without running anything, and so the real
# executor (a conductor agent-runner call) can be wired in a later slice.

# Prompt the conductor uses to execute one finding's demonstration. It must run
# the demonstration against the CURRENT code and render a strict, falsifiable
# verdict — never an opinion. The verdict contract is a single machine-readable
# token so the parser can be unambiguous (see almanac_harden_ratify_verdict).
almanac_harden_ratify_prompt() {
  local demonstration="$1"
  local target_path="${2:-}"

  cat <<EOF
You are the CONDUCTOR in a code-hardening loop. Ratify ONE reviewer finding by
EXECUTING its demonstration against the current code — decide by reproduction,
never by opinion.

Target: ${target_path:-(the current working directory)}

Demonstration to reproduce:
${demonstration}

Do this:
1. Carry out the demonstration against the code AS IT IS RIGHT NOW: run the
   proposed failing test, try the specific breaking input, or check the cited
   rubric criterion.
2. Decide strictly. The finding reproduces ONLY if the defect actually manifests
   against the current code. A demonstration that you cannot run, that is vague
   or speculative, or that does not actually fail does NOT reproduce.
3. You are a JUDGE, not a fixer: do not modify the target to change the outcome.

End your message with EXACTLY ONE of these two lines and nothing after it:
HARDEN_VERDICT=reproduces
HARDEN_VERDICT=not-reproduces
EOF
}

# Parse the conductor's final message into a reproduce verdict. The contract is a
# single unambiguous token: the affirmative is the literal "HARDEN_VERDICT=reproduces"
# (the negative "HARDEN_VERDICT=not-reproduces" cannot match it — the char after
# `=` is `n`, not `r`). Anything else (no token, garbled, only the negative) reads
# as "not", so an un-parseable verdict is conservatively a non-blocking note.
# Two arities so callers can pass either a result FILE or the result TEXT (the
# string variant lets agent_capture_text callers avoid materialising a tmpfile
# just to grep it).
almanac_harden_ratify_verdict() {
  local result_file="$1"
  [ -f "$result_file" ] || { printf '%s\n' "not"; return 0; }
  almanac_harden_ratify_verdict_text "$(cat "$result_file")"
}

almanac_harden_ratify_verdict_text() {
  local result_text="$1"
  if printf '%s\n' "$result_text" | grep -Fxq 'HARDEN_VERDICT=reproduces' 2>/dev/null; then
    printf '%s\n' "reproduces"
  else
    printf '%s\n' "not"
  fi
}

# Execution seam: decide whether a finding's demonstration reproduces against the
# target. Return 0 = reproduces (real defect, blocking), non-zero = does not
# reproduce (opinion / stale). This seam IS the conductor executing the
# demonstration: it runs the demonstration through the resolved conductor provider
# (the (provider, model, effort) it is handed — no host-marker dependence, so it
# is mixable per the role config) via the shared agent runner and reads the
# conductor's verdict back from its final message. PRD story 8: "blocking means
# objectively reproducible, not a reviewer's assertion."
#
# Conservative on every uncertainty so opinions never silently gate the loop and
# a flaky/missing provider never blocks a run: an empty demonstration, an
# unresolved conductor provider, a failed/un-runnable conductor call, or an
# un-parseable verdict all read as non-reproducing (a note). Tests override this
# to drive the decision paths directly; here it is the real executor.
almanac_harden_demo_reproduces() {
  local demonstration="$1"
  local target_path="${2:-}"
  local conductor_provider="${3:-}"
  local conductor_model="${4:-}"
  local conductor_effort="${5:-}"
  local result_text rc=0

  # Nothing to execute / no provider to execute it through -> conservative note.
  [ -n "$demonstration" ] || return 1
  [ -n "$conductor_provider" ] || return 1

  # Reviewer text is untrusted. Ratification may inspect/run existing repro
  # commands, but it must not write to the repo before the single fixer phase
  # (read-only sandbox). capture_text owns the prompt/result/events tmpfiles via
  # an EXIT-trapped subshell, so a signal mid-call can't leak them.
  result_text="$(almanac_loop_agent_capture_text \
    "$conductor_provider" "$conductor_model" "$conductor_effort" "read-only" \
    "$(almanac_harden_ratify_prompt "$demonstration" "$target_path")" 2>/dev/null)" || rc=$?

  # Provider missing/crashed or the demonstration was un-runnable: cannot
  # confirm reproduction -> non-blocking note, never a hang or a hard failure.
  [ "$rc" -eq 0 ] || return 1

  [ "$(almanac_harden_ratify_verdict_text "$result_text")" = "reproduces" ] && return 0
  return 1
}

# Adjudicate one finding by executing its demonstration through the seam and
# recording the outcome in the ledger. Prints the verdict:
#   blocking - new/open finding whose demonstration reproduces (ratified, gates)
#   note     - new/open finding that does not reproduce (non-blocking note)
#   reopened - an already-adjudicated finding whose demonstration newly reproduces
#   dropped  - an already-adjudicated finding that still does not reproduce
# Already-adjudicated findings are re-litigated ONLY when they newly reproduce,
# so a rejected opinion cannot churn the loop round after round.
#
# When a rubric path is given, a finding that reproduces (blocking or reopened)
# also appends a falsifiable criterion to the rubric's `## Acceptance` — the bar
# grows monotonically and visibly with every ratified defect. Notes and drops
# never touch the rubric, so opinions cannot raise the bar.
#
# The trailing conductor (provider, model, effort) args (11th-13th) identify the
# provider that executes the demonstration; they are passed straight to the
# execution seam. Optional/backward-compatible — omit them to use the default.
almanac_harden_ratify() {
  local path="$1"
  local id="$2"
  local lens="$3"
  local severity="$4"
  local location="$5"
  local claim="$6"
  local demonstration="$7"
  local round="${8:-1}"
  local target_path="${9:-}"
  local rubric_path="${10:-}"
  local conductor_provider="${11:-}"
  local conductor_model="${12:-}"
  local conductor_effort="${13:-}"
  local current_status reproduces status note

  almanac_harden_ledger_init "$path"
  current_status="$(almanac_harden_ledger_status "$path" "$id")"

  if almanac_harden_demo_reproduces "$demonstration" "$target_path" \
      "$conductor_provider" "$conductor_model" "$conductor_effort"; then
    reproduces=1
  else
    reproduces=0
  fi

  # A ratified (reproducing) finding grows the rubric bar, regardless of whether
  # it is newly raised or a reopened prior finding. Idempotent on the criterion
  # text, so a reopen never duplicates an already-listed criterion.
  if [ "$reproduces" -eq 1 ] && [ -n "$rubric_path" ]; then
    almanac_harden_rubric_append_criterion "$rubric_path" \
      "${claim} — must not reproduce (lens: ${lens}, at ${location})" >/dev/null || true
  fi

  case "$current_status" in
    fixed | rejected-subjective | wontfix-per-context)
      if [ "$reproduces" -eq 1 ]; then
        almanac_harden_ledger_set_status "$path" "$id" "open" \
          "reopened: demonstration reproduced at round $round"
        printf '%s\n' "reopened"
      else
        printf '%s\n' "dropped"
      fi
      return 0
      ;;
  esac

  if [ "$reproduces" -eq 1 ]; then
    status="open"
    note="ratified: demonstration reproduced at round $round"
  else
    status="rejected-subjective"
    note="did not reproduce at round $round"
  fi

  if [ -z "$current_status" ]; then
    almanac_harden_ledger_append_entry "$path" "$id" "$lens" "$severity" \
      "$location" "$claim" "$demonstration" "$status" "$round" "$note" >/dev/null
  else
    almanac_harden_ledger_set_status "$path" "$id" "$status" "$note"
  fi

  if [ "$reproduces" -eq 1 ]; then
    printf '%s\n' "blocking"
  else
    printf '%s\n' "note"
  fi
}

# Fan out one read-only reviewer per configured lens as a background worker via
# the shared worker orchestration, then aggregate every reviewer's findings into
# the ledger (deduped). Reviewers run concurrently and never write to the target
# (read-only sandbox); the parent aggregates sequentially after they finish, so
# there are no concurrent ledger writers. The lens set is configurable via
# HARDEN_LENSES, capped by HARDEN_MAX_REVIEWERS. Each reviewer's
# provider/model/effort resolves through the shared role config
# (HARDEN_REVIEWER[_<LENS>]_{PROVIDER,MODEL,EFFORT}). _die on a missing target
# before spawning anything.
almanac_harden_fanout() {
  local root="$1"
  local target="$2"
  local round="${3:-1}"
  local directive="${4:-}"
  local target_path run_id run_id_base registry_dir ledger_path rubric_path lens provider model effort
  local worker_id prompt_file pidfile pid result_file status_file wstatus
  local added total_added i max_reviewers succeeded_count suffix
  local -a lenses=() worker_ids=() worker_pids=() prompt_files=()

  target_path="$(almanac_harden_target_path "$root" "$target")"

  if [ ! -e "$target_path" ]; then
    _die "Harden target not found: $target"
  fi

  while IFS= read -r lens; do
    [ -n "$lens" ] || continue
    lenses+=("$lens")
  done < <(almanac_harden_lenses)

  [ "${#lenses[@]}" -gt 0 ] || _die "No reviewer lenses configured"
  max_reviewers="$(almanac_harden_max_reviewers)"
  case "$max_reviewers" in
    ''|*[!0-9]*) _die "HARDEN_MAX_REVIEWERS must be a positive integer: $max_reviewers" ;;
  esac
  [ "$max_reviewers" -ge 1 ] || _die "HARDEN_MAX_REVIEWERS must be at least 1: $max_reviewers"
  if [ "${#lenses[@]}" -gt "$max_reviewers" ]; then
    _die "Too many reviewer lenses (${#lenses[@]}); cap is $max_reviewers (set HARDEN_MAX_REVIEWERS to change it)"
  fi

  run_id="$(almanac_loop_run_id "harden" "$target")"
  run_id_base="$run_id"
  registry_dir="$(almanac_loop_registry_dir "$root")"
  suffix=1
  while [ -e "$registry_dir/$run_id" ]; do
    suffix=$((suffix + 1))
    run_id="${run_id_base}-${suffix}"
  done
  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"

  # The rubric is the contract; once one has been drafted it must be approved
  # (locked) before the loop proceeds, so reviewers never run against a bar the
  # human is still authoring. No rubric at all = an explicit ad-hoc run; proceed.
  if [ -f "$rubric_path" ] && ! almanac_harden_rubric_approved "$rubric_path"; then
    _die "Rubric not approved: ${rubric_path#"$root"/} — edit it, then: almanac harden $target --approve"
  fi

  almanac_harden_ledger_init "$ledger_path"

  # The rubric is immutable to agents during the run. Snapshot it before any
  # reviewer spawns; the reviewer round makes no legitimate rubric edits (the
  # conductor's controlled append happens at ratification, a later phase), so
  # any change observed when reviewers finish is an agent tampering — revert it.
  local rubric_snapshot=""
  if [ -f "$rubric_path" ]; then
    rubric_snapshot="$(almanac_harden_rubric_snapshot "$rubric_path")" || rubric_snapshot=""
  fi

  _info "Hardening $target — fanning out ${#lenses[@]} read-only reviewer(s)"

  for lens in "${lenses[@]}"; do
    IFS=$'\t' read -r provider model effort < <(almanac_harden_role_resolve reviewer "$lens")

    worker_id="reviewer-$lens"
    prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-prompt.XXXXXX")"
    # Reviewers judge against the rubric when one exists (read gracefully when
    # absent, e.g. an ad-hoc bare run with no drafted contract yet) and follow an
    # operator steer directive when one was set at the HITL checkpoint.
    almanac_harden_reviewer_prompt "$target" "$lens" "$rubric_path" "$directive" > "$prompt_file"

    # Capture the worker pid via a file (not $(...)): worker_start backgrounds
    # the agent as a child of THIS shell, so it stays waitable. A command
    # substitution would reparent it into a subshell and break the wait.
    pidfile="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-pid.XXXXXX")"
    almanac_loop_worker_start "$root" "$run_id" "$worker_id" \
      "$provider" "$model" "$effort" "read-only" "$prompt_file" > "$pidfile"
    pid="$(cat "$pidfile")"
    rm -f "$pidfile"

    worker_ids+=("$worker_id")
    worker_pids+=("$pid")
    prompt_files+=("$prompt_file")
    _info "  reviewer lens=$lens provider=$provider pid=$pid (read-only)"
  done

  # Reviewers run concurrently; block until every one finishes.
  for pid in "${worker_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  total_added=0
  succeeded_count=0
  i=0
  for worker_id in "${worker_ids[@]}"; do
    lens="${lenses[$i]}"
    i=$((i + 1))
    status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
    result_file="$(almanac_loop_worker_result_file "$root" "$run_id" "$worker_id")"

    wstatus=""
    if [ -f "$status_file" ]; then
      wstatus="$(almanac_loop_status_field "$status_file" "status" || true)"
    fi

    if [ "$wstatus" != "done" ]; then
      _warn "reviewer lens=$lens failed or did not finish cleanly; skipping its findings"
      continue
    fi
    succeeded_count=$((succeeded_count + 1))

    _info "Findings (lens: $lens):"
    almanac_harden_format_findings "$result_file"

    if [ -f "$result_file" ]; then
      added="$(almanac_harden_ledger_record "$ledger_path" "$result_file" "$round")"
      total_added=$((total_added + added))
    fi
  done

  [ "${#prompt_files[@]}" -eq 0 ] || rm -f "${prompt_files[@]}"

  # Enforce the immutability invariant: revert (and warn about) any rubric edit
  # an agent slipped in during the round.
  if [ -n "$rubric_snapshot" ]; then
    almanac_harden_rubric_verify "$rubric_path" "$rubric_snapshot" || true
  fi

  if [ "$succeeded_count" -eq 0 ]; then
    _warn "All reviewer workers failed; no reliable review result was produced."
    return 1
  fi

  _success "Aggregated $total_added new finding(s) into ${ledger_path#"$root"/}"
}

# --- Single sequential fixer + feedback verdict --------------------------------
#
# After reviewers fan out and the conductor ratifies findings, ONE write-capable
# fixer applies changes for the open blocking findings, in place, in the working
# tree. v1 is deliberately a single sequential agent — no worktrees, no parallel
# writers — so there is never a merge conflict to reconcile and any regression
# test the fixer writes simply persists on disk. The fixer then runs the
# project's feedback loops (shared detection + runner) and reports a verdict per
# loop, so the objective half of "bulletproof" is enforced every round.

# Build the prompt for the single sequential fixer. It receives the kill-list
# (the open blocking findings) and the rubric bar, and is told to apply minimal
# fixes AND leave a regression test per finding so the fix stays enforced. An
# optional steering directive (4th arg) is embedded too, so a mid-run redirect at
# the HITL checkpoint reaches the fixer. Exact wording is not asserted by tests by
# design; that the fixer runs write-capable, its output persists, and it consumes
# the steer directive is.
almanac_harden_fixer_prompt() {
  local target="$1"
  local findings_text="$2"
  local rubric_path="${3:-}"
  local directive="${4:-}"
  local rubric_bar=""

  if [ -n "$rubric_path" ] && [ -f "$rubric_path" ]; then
    rubric_bar="$(almanac_harden_rubric_acceptance "$rubric_path")"
  fi

  cat <<EOF
You are a single sequential fixer with write access to the repository. Apply the
minimal changes that resolve every blocking finding below for the target. For
each finding, add or update a regression test that fails before your fix and
passes after, so the defect cannot silently return.

Target: ${target}

Blocking findings to fix:
${findings_text}
EOF

  if [ -n "$rubric_bar" ]; then
    cat <<EOF

Your changes must satisfy this acceptance bar (the rubric contract):

${rubric_bar}
EOF
  fi

  if [ -n "$directive" ]; then
    cat <<EOF

The operator steered this run with the directive below — apply it while you fix:

${directive}
EOF
  fi

  cat <<EOF

Do not weaken, skip, or delete existing tests, and do not edit the rubric. Leave
the working tree building and the project's feedback loops (tests / typecheck /
lint) green.
EOF
}

# Run the single sequential fixer over the target's open blocking findings, then
# run the project's feedback loops and report a pass/fail verdict per loop.
#
# One agent, write-capable (sandbox=workspace-write, NOT read-only), in place: no
# worktree, so any regression tests it generates persist in the repo after the
# run. Sequential by construction — a single foreground agent call — so there are
# never concurrent writers. The fixer's agent call is bracketed by the rubric
# immutability guard (snapshot before, verify after) so a write-capable fixer
# cannot move the goalposts mid-run; legitimate rubric growth happens earlier, in
# ratification, outside this bracket. On a clean fixer exit every open blocking
# finding is marked `fixed` in the ledger; the next round's reviewers/ratify
# reopen anything that still reproduces, so a still-broken finding cannot be
# silently closed. A no-op (prints a note, returns 0) when there are no open
# blocking findings. Returns the provider's exit code on a fixer failure, leaving
# the findings open.
#
# The objective feedback gate is NOT run here: the convergence loop runs it once
# per round (almanac_harden_round) so feedback executes every round even when
# there is nothing to fix, and the gate reads a fresh verdict. The standalone
# `--fix` CLI path runs almanac_harden_report_feedback explicitly afterwards.
almanac_harden_fix() {
  local root="$1"
  local target="$2"
  local round="${3:-1}"
  local directive="${4:-}"
  local target_path ledger_path rubric_path open findings_text count
  local provider model effort rubric_snapshot rc
  local id lens severity location claim demonstration

  target_path="$(almanac_harden_target_path "$root" "$target")"

  if [ ! -e "$target_path" ]; then
    _die "Harden target not found: $target"
  fi

  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"

  open="$(almanac_harden_ledger_open_blocking "$ledger_path")"
  if [ -z "$open" ]; then
    _info "No open blocking findings to fix."
    return 0
  fi

  count="$(printf '%s\n' "$open" | grep -c .)"

  # Render the kill-list into the fixer prompt's findings block.
  findings_text="$(
    while IFS=$'\t' read -r id lens severity location claim demonstration; do
      [ -n "$id" ] || continue
      printf -- '- [%s] %s: %s (at %s)\n    demo: %s\n' \
        "${severity:-?}" "${lens:-?}" "${claim:-?}" "${location:-?}" "${demonstration:-?}"
    done <<INNER
$open
INNER
  )"

  IFS=$'\t' read -r provider model effort < <(almanac_harden_role_resolve fixer)

  # The rubric is immutable to agents during a run. The fixer is write-capable,
  # so bracket its agent call: snapshot before, verify (revert + warn) after.
  rubric_snapshot=""
  if [ -f "$rubric_path" ]; then
    rubric_snapshot="$(almanac_harden_rubric_snapshot "$rubric_path")" || rubric_snapshot=""
  fi

  _info "Fixing $count open blocking finding(s) with one sequential fixer (provider=$provider, write-capable)"

  # Fire-and-forget: the fixer writes to the workspace; we only care about its
  # exit code. capture_text owns the tmpfile lifecycle so a signal mid-call
  # can't leak prompt/result/events files.
  rc=0
  almanac_loop_agent_capture_text "$provider" "$model" "$effort" "workspace-write" \
    "$(almanac_harden_fixer_prompt "$target" "$findings_text" "$rubric_path" "$directive")" \
    >/dev/null || rc=$?

  if [ -n "$rubric_snapshot" ]; then
    almanac_harden_rubric_verify "$rubric_path" "$rubric_snapshot" || true
  fi

  if [ "$rc" -ne 0 ]; then
    _warn "Fixer failed (exit $rc); blocking findings remain open."
    return "$rc"
  fi

  # The single fixer addresses the whole kill-list; mark all open blocking
  # findings fixed in one ledger rewrite. A finding that still reproduces is
  # reopened next round.
  printf '%s\n' "$open" | awk -F '\t' '$1 != "" { print $1 }' \
    | almanac_harden_ledger_set_status_many "$ledger_path" "fixed" \
      "fixed by sequential fixer at round $round"

  _success "Applied fixes for $count finding(s); regenerated tests persist in the working tree."
}

# Run the project's feedback loops via the shared runner and print a pass/fail
# verdict per loop. Returns the runner's aggregate (0 = all green, non-zero =
# any failed) so a caller (the convergence gate, later) can act on it.
almanac_harden_report_feedback() {
  local root="$1"
  local verdicts cmd verdict rc

  _info "Running project feedback loops:"

  rc=0
  verdicts="$(almanac_loop_feedback_run "$root")" || rc=$?

  if [ -z "$verdicts" ]; then
    _info "  (no feedback loops detected)"
    return 0
  fi

  while IFS=$'\t' read -r cmd verdict; do
    [ -n "$cmd" ] || continue
    if [ "$verdict" = "pass" ]; then
      _success "  PASS  $cmd"
    else
      _warn "  FAIL  $cmd"
    fi
  done <<INNER
$verdicts
INNER

  return "$rc"
}

# --- Convergence loop + gate ---------------------------------------------------
#
# A round is the full hardening pass over one target: fan out reviewers, ratify
# their findings by execution, fix the blocking ones, and run the project's
# feedback loops. The convergence loop repeats rounds until the gate says stop:
# it converges when the acceptance bar is met AND no open blocking findings
# remain, gives up with a clear NON-CONVERGED status when the round budget is
# hit, and otherwise checks in with the human (ship vs. continue) between rounds.
# Because the gate only ever exits on convergence or the budget, the loop always
# terminates — a pathological target cannot run forever.

# Pure convergence predicate. Given the round's state, decide what the loop does
# next. No I/O, no side effects (besides echoing the verdict) so it is trivially
# unit-testable across the whole input space:
#
#   acceptance_met  1 = every acceptance criterion is met, else 0
#   open_blocking   count of open blocking findings still remaining
#   round           the round that just finished (1-based)
#   budget          the hard round cap (>= 1)
#
# Echoes one verdict and returns a distinct code so a caller can branch on either:
#   converged      (return 0) acceptance met AND zero open blocking — exit success
#   non-converged  (return 2) budget reached without convergence — exit failure
#   continue       (return 1) neither — run another round
#
# Convergence is checked first, so a round that converges exactly at the budget
# still reports converged (it never falsely claims non-convergence). And it never
# reports converged unless BOTH conditions hold (it never exits early).
almanac_harden_gate_verdict() {
  local acceptance_met="$1"
  local open_blocking="$2"
  local round="$3"
  local budget="$4"

  if [ "$acceptance_met" = "1" ] && [ "$open_blocking" -eq 0 ]; then
    printf '%s\n' "converged"
    return 0
  fi

  if [ "$round" -ge "$budget" ]; then
    printf '%s\n' "non-converged"
    return 2
  fi

  printf '%s\n' "continue"
  return 1
}

# Return 0 (acceptance met) when the rubric's `## Acceptance` section has no
# unchecked `- [ ]` criteria left, non-zero when at least one remains. An ad-hoc
# run with no rubric has no checklist to satisfy, so acceptance is vacuously met
# (return 0). This is one half of the gate's acceptance signal; the other half —
# the objective feedback loops being green — is the round's own exit code.
almanac_harden_acceptance_met() {
  local rubric_path="$1"

  [ -f "$rubric_path" ] || return 0

  if almanac_harden_rubric_acceptance "$rubric_path" | grep -q '^- \[ \]'; then
    return 1
  fi
  return 0
}

# Ratify every currently-open finding by executing its demonstration through the
# seam (almanac_harden_demo_reproduces): a finding that reproduces stays open
# (blocking) and grows the rubric bar; one that does not becomes a non-blocking
# note. Iterates the open-blocking rows the fan-out just recorded. The rubric
# append happens here, between fan-out and fix and OUTSIDE the immutability
# brackets those phases use — this is the conductor's sanctioned, monotonic
# growth of the contract, not an agent edit. A no-op when nothing is open.
almanac_harden_ratify_open() {
  local root="$1"
  local target="$2"
  local round="${3:-1}"
  local ledger_path rubric_path target_path open
  local cond_provider cond_model cond_effort
  local id lens severity location claim demonstration

  target_path="$(almanac_harden_target_path "$root" "$target")"

  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"

  open="$(almanac_harden_ledger_open_blocking "$ledger_path")"
  [ -n "$open" ] || return 0

  # The conductor is the role that ratifies findings by executing their
  # demonstrations; resolve its (provider, model, effort) once and hand it to the
  # execution seam for every finding this round.
  IFS=$'\t' read -r cond_provider cond_model cond_effort < <(almanac_harden_role_resolve conductor)

  while IFS=$'\t' read -r id lens severity location claim demonstration; do
    [ -n "$id" ] || continue
    almanac_harden_ratify "$ledger_path" "$id" "$lens" "$severity" \
      "$location" "$claim" "$demonstration" "$round" "$target_path" "$rubric_path" \
      "$cond_provider" "$cond_model" "$cond_effort" >/dev/null
  done <<INNER
$open
INNER
}

# Print the kill-list — the blocking findings the round must fix — from the
# open-blocking TSV rows. Reports an empty kill-list explicitly so every round
# shows its verdict input. Pure presentation; does not touch the ledger.
almanac_harden_print_killlist() {
  local rows="$1"
  local id lens severity location claim demonstration

  if [ -z "$rows" ]; then
    _info "Kill-list: no blocking findings this round."
    return 0
  fi

  _info "Kill-list (blocking findings this round):"
  while IFS=$'\t' read -r id lens severity location claim demonstration; do
    [ -n "$id" ] || continue
    printf -- '  - [%s] %s: %s (at %s)\n' \
      "${severity:-?}" "${lens:-?}" "${claim:-?}" "${location:-?}"
  done <<INNER
$rows
INNER
}

# HITL checkpoint between rounds: let the human ship the current state, keep
# going, or steer the run. Returns a distinct code per choice:
#   0 = continue (run another round, directive unchanged)
#   1 = ship (stop, accept the current state now)
#   2 = steer (redirect/amend the run — the directive is echoed on stdout for the
#       caller to thread into the next round's reviewers and fixer)
# HARDEN_HITL ("ship"|"continue"|"steer") drives the choice non-interactively
# (tests, headless runs); on "steer" the directive comes from HARDEN_STEER. With a
# stdin TTY it prompts through the UI seam (gum-or-plain in lib/ui.sh) — gum
# choose/input when gum is present and stderr is a TTY, plain numbered menu / read
# otherwise. With no TTY and no override it defaults to continue so an unattended
# loop keeps working rather than blocking on input. The prompt text goes to stderr
# (ui.sh contract) so stdout carries only the steer directive.
almanac_harden_hitl_checkpoint() {
  local choice="${HARDEN_HITL:-}"
  local directive="${HARDEN_STEER:-}"

  if [ -z "$choice" ]; then
    if [ -t 0 ]; then
      choice="$(almanac_loop_ui_choose "Round complete — ship, continue, or steer?" continue ship steer)" || choice="continue"
    else
      choice="continue"
    fi
  fi

  case "$choice" in
    ship|s|S|SHIP)
      return 1
      ;;
    steer|st|STEER|redirect|amend)
      # Collect a directive to redirect (or amend) the next round, unless one was
      # supplied non-interactively via HARDEN_STEER. Echo it on stdout; the prompt
      # itself goes to stderr (ui.sh contract) so the caller captures only the
      # directive.
      if [ -z "$directive" ] && [ -t 0 ]; then
        directive="$(almanac_loop_ui_input "Steer the run (redirect/amend)")" || directive=""
      fi
      printf '%s\n' "$directive"
      return 2
      ;;
    *)
      return 0
      ;;
  esac
}

# Run one hardening round over the target: fan out reviewers -> ratify their
# findings by execution -> fix the blocking findings -> run the project feedback
# loops. The round's exit code is the feedback verdict (0 = all loops green) so
# the loop can fold it into the acceptance signal. A fixer failure is reported but
# does not abort the round — the next round's reviewers re-surface anything still
# broken. An optional steer directive (4th arg) is threaded into both the reviewer
# fan-out and the fixer, so a mid-run redirect reaches the agents. The per-round
# kill-list + verdict are reported by almanac_harden_run.
almanac_harden_round() {
  local root="$1"
  local target="$2"
  local round="${3:-1}"
  local directive="${4:-}"
  local rc

  almanac_harden_fanout "$root" "$target" "$round" "$directive"
  almanac_harden_ratify_open "$root" "$target" "$round"

  if ! almanac_harden_fix "$root" "$target" "$round" "$directive"; then
    _warn "Fixer did not complete cleanly this round; unaddressed findings carry to the next round."
  fi

  rc=0
  almanac_harden_report_feedback "$root" || rc=$?
  return "$rc"
}

# Drive the convergence loop: repeat almanac_harden_round under the gate until
# the target converges, the round budget is exhausted, or the human ships.
# Budget is configurable (3rd arg, else HARDEN_ROUND_BUDGET, else 5). Each round
# prints its kill-list and a verdict. Returns 0 when converged or shipped, 1 when
# the budget is hit without convergence (clear NON-CONVERGED status).
#
# Between rounds the human can steer at the HITL checkpoint: a steer directive
# (echoed by almanac_harden_hitl_checkpoint, captured here) is carried forward and
# threaded into every subsequent round's reviewers and fixer, so the operator can
# redirect the run without babysitting each worker. An optional starting directive
# (4th arg) seeds the first round; the checkpoint's own directive (HARDEN_STEER /
# the gum prompt) overrides it from the next round on.
#
# The loop registers itself in the shared run registry at start (the same contract
# ralph emits, so it shows in the almanac hub), updates its live run-status blob
# each round (round + lens/open-blocking summary), and marks the run done (converge
# or ship), failed (budget hit), or aborted (signal / mid-round _die) on exit.
almanac_harden_run() {
  local root="$1"
  local target="$2"
  local budget="${3:-${HARDEN_ROUND_BUDGET:-5}}"
  local directive="${4:-}"
  local ledger_path rubric_path round round_rc open_rows open_count acc verdict rc acc_label
  local cond_provider cond_model cond_effort steer_directive hitl_rc
  local run_id pid lens_summary

  case "$budget" in
    ''|*[!0-9]*) _die "Round budget must be a positive integer: $budget" ;;
  esac
  [ "$budget" -ge 1 ] || _die "Round budget must be at least 1: $budget"

  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"

  # Announce the configured conductor — the provider judging findings this run —
  # so the role config is visible to whoever is supervising.
  IFS=$'\t' read -r cond_provider cond_model cond_effort < <(almanac_harden_role_resolve conductor)
  _info "Conductor: provider=$cond_provider${cond_model:+ model=$cond_model}${cond_effort:+ effort=$cond_effort}"

  # Register this loop in the shared run registry — the SAME contract ralph emits
  # (id/type/target/pid/status-file/start), so both appear in the almanac hub. The
  # per-round fan-out keeps its own worker run dirs; this is the loop-level run.
  # Best-effort: a registry failure must never stop a hardening run. lens_summary
  # is the static lens list for the per-round progress blob.
  pid="${BASHPID:-$$}"
  run_id="$(almanac_loop_register_run "$root" "harden" "$target" "$pid" 2>/dev/null || true)"
  lens_summary="$(almanac_harden_lenses | tr '\n' ',' | sed 's/,$//' || true)"
  if [ -n "$run_id" ]; then
    _info "Run registered: $run_id"
    almanac_loop_set_run_config "$root" "$run_id" \
      "provider=${HARDEN_PROVIDER:-$cond_provider}" \
      "model=${HARDEN_MODEL:-$cond_model}" \
      "effort=${HARDEN_EFFORT:-$cond_effort}" \
      "lenses=$lens_summary" \
      "rounds=$budget" >/dev/null 2>&1 || true
    # Mark the run aborted on any unexpected exit (signal, mid-round _die) that
    # leaves it still running; the normal exit paths below mark done/failed and
    # clear this via almanac_loop_run_finalize. The shared helper owns the
    # %q bake that defends against inner-frame `local run_id` shadowing — see
    # `almanac_loop_install_finalize_trap` in lib/run.sh for the full why.
    almanac_loop_install_finalize_trap "$root" "$run_id"
  fi

  round=0
  while :; do
    if almanac_loop_consume_signal harden "$root" stop >/dev/null; then
      _success "Stop signal detected (.harden-stop); exiting before next round."
      almanac_loop_run_finalize "$root" "$run_id" "done"
      return 0
    fi

    steer_directive="$(almanac_loop_consume_signal harden "$root" steer || true)"
    if [ -n "$steer_directive" ]; then
      directive="$steer_directive"
      _info "Steering applied for the next round: $directive"
    fi

    round=$((round + 1))
    _info "=== Harden round $round/$budget ==="

    almanac_harden_round "$root" "$target" "$round" "$directive" && round_rc=0 || round_rc=$?

    open_rows="$(almanac_harden_ledger_open_blocking "$ledger_path")"
    if [ -n "$open_rows" ]; then
      open_count="$(printf '%s\n' "$open_rows" | grep -c '[^[:space:]]' || true)"
    else
      open_count=0
    fi

    # Update the registry's live run-status blob so the hub/dashboard reflect the
    # current round and a lens/open-blocking summary as the loop advances.
    if [ -n "$run_id" ]; then
      almanac_loop_update_run_progress "$root" "$run_id" "$round" \
        "lenses=$lens_summary open-blocking=$open_count" >/dev/null 2>&1 || true
    fi

    # Report this round's kill-list (the blocking findings still open after the
    # round) — the HITL view of what remains to harden.
    almanac_harden_print_killlist "$open_rows"

    # Acceptance for the gate = the round's feedback loops are green AND every
    # rubric acceptance criterion is checked off (vacuously true for ad-hoc runs).
    acc=0
    if [ "$round_rc" -eq 0 ] && almanac_harden_acceptance_met "$rubric_path"; then
      acc=1
    fi

    verdict="$(almanac_harden_gate_verdict "$acc" "$open_count" "$round" "$budget")" && rc=0 || rc=$?
    if [ "$acc" -eq 1 ]; then acc_label="met"; else acc_label="unmet"; fi
    _info "Verdict: $verdict (round $round/$budget, open-blocking=$open_count, acceptance=$acc_label)"

    case "$rc" in
      0)
        _success "Converged after $round round(s): acceptance met and no open blocking findings remain."
        almanac_loop_run_finalize "$root" "$run_id" "done"
        return 0
        ;;
      2)
        _warn "Round budget ($budget) reached — $open_count open blocking finding(s) remain. Status: NON-CONVERGED."
        almanac_loop_run_finalize "$root" "$run_id" "failed"
        return 1
        ;;
      *)
        # HITL checkpoint: continue, ship, or steer. A steer (rc 2) echoes the
        # new directive on stdout; capture it and thread it into the next round.
        steer_directive="$(almanac_harden_hitl_checkpoint)" && hitl_rc=0 || hitl_rc=$?
        case "$hitl_rc" in
          2)
            directive="$steer_directive"
            if [ -n "$directive" ]; then
              _info "Steering applied for the next round: $directive"
            else
              _info "Steering directive cleared for the next round."
            fi
            continue
            ;;
          0)
            continue
            ;;
          *)
            _success "Shipping at round $round by request — $open_count open blocking finding(s) left unaddressed."
            almanac_loop_run_finalize "$root" "$run_id" "done"
            return 0
            ;;
        esac
        ;;
    esac
  done
}

# --- Supervision dashboard -----------------------------------------------------
#
# A gum-styled redraw dashboard for supervising a harden run: reviewer status (per
# lens, with health), the round, findings tallies, rubric progress, and the
# feedback verdict. The render LOGIC is pure (almanac_harden_dashboard_rows: state
# -> printable rows) so it is unit-testable without a terminal; the gather helpers
# read live run state into that pure composer, and almanac_harden_render_dashboard
# wraps the result in gum styling that degrades to plain output when gum is absent
# (via the shared UI primitives in lib/ui.sh).

# Findings tally for the dashboard: counts the ledger's findings by status as
# `open=N fixed=N notes=N`, where notes = rejected-subjective + wontfix-per-context
# (the non-blocking outcomes). Prints all-zero when the ledger is absent.
almanac_harden_findings_tally() {
  local path="$1"

  [ -f "$path" ] || { printf '%s\n' "open=0 fixed=0 notes=0"; return 0; }

  awk '
    /^- status:/ {
      s = $0; sub(/^- status:[ \t]*/, "", s)
      if (s == "open") o++
      else if (s == "fixed") f++
      else if (s == "rejected-subjective" || s == "wontfix-per-context") n++
    }
    END { printf "open=%d fixed=%d notes=%d\n", o, f, n }
  ' "$path"
}

# Rubric acceptance progress for the dashboard: `checked/total` over the
# `## Acceptance` checklist. Prints 0/0 when the rubric or section is absent.
almanac_harden_rubric_progress() {
  local path="$1"
  local acc total checked

  acc="$(almanac_harden_rubric_acceptance "$path")"
  total="$(printf '%s\n' "$acc" | grep -c '^- \[' || true)"
  checked="$(printf '%s\n' "$acc" | grep -c '^- \[[xX]\]' || true)"
  printf '%s/%s\n' "$checked" "$total"
}

# Pure render: compose the dashboard's printable rows from already-gathered state.
# Reads worker rows from stdin as TSV (id<TAB>provider<TAB>health), one per
# reviewer, and takes round/budget, findings tally, rubric progress, and feedback
# verdict as args. No file I/O, no clock, no gum — fully deterministic and
# unit-testable. Surfaces each reviewer's health (running, stalled, idle, looping,
# done, failed) with a status glyph, and reports an empty reviewer set explicitly.
almanac_harden_dashboard_rows() {
  local round="${1:-?}"
  local budget="${2:-?}"
  local tally="${3:-}"
  local progress="${4:-}"
  local verdict="${5:-n/a}"
  local id provider health glyph
  local any=0

  printf 'Harden dashboard — round %s/%s\n' "$round" "$budget"
  printf 'Reviewers:\n'
  while IFS=$'\t' read -r id provider health; do
    [ -n "$id" ] || continue
    glyph="$(almanac_loop_ui_status_glyph "$health")"
    printf '  %s %s  %s  %s\n' "$glyph" "$id" "${provider:-?}" "${health:-?}"
    any=1
  done
  [ "$any" -eq 1 ] || printf '  (no reviewers)\n'
  printf 'Findings: %s\n' "${tally:-open=0 fixed=0 notes=0}"
  printf 'Rubric: %s acceptance criteria\n' "${progress:-0/0}"
  printf 'Feedback: %s\n' "$verdict"
}

# Gather the run's reviewer rows for the composer: one TSV line per worker
# (id<TAB>provider<TAB>health), reading each worker's status.tsv and classifying
# its health via the shared detector. Empty when the run has no workers yet.
# now/stall/loop pass through to the classifier (overridable for tests).
almanac_harden_dashboard_worker_rows() {
  local root="$1"
  local run_id="$2"
  local now="${3:-}"
  local stall="${4:-120}"
  local loop="${5:-5}"
  local workers_dir wdir status_file base id provider health

  workers_dir="$(almanac_loop_workers_dir "$root" "$run_id")"
  [ -d "$workers_dir" ] || return 0
  [ -n "$now" ] || now="$(date +%s)"

  for wdir in "$workers_dir"/*/; do
    [ -d "$wdir" ] || continue
    status_file="$wdir/status.tsv"
    [ -f "$status_file" ] || continue
    base="$(basename "$wdir")"
    id="$(almanac_loop_status_field "$status_file" "id" || true)"
    provider="$(almanac_loop_status_field "$status_file" "provider" || true)"
    health="$(almanac_loop_worker_health_of "$root" "$run_id" "$base" "$now" "$stall" "$loop")"
    printf '%s\t%s\t%s\n' "${id:-$base}" "${provider:-?}" "$health"
  done
}

# Find the most recent harden run id for a target under the run registry (newest
# by directory mtime). Returns non-zero when no matching run exists. Used by the
# dashboard to render the live run's state.
# Render the supervision dashboard for a target's most recent run: gather the
# run's reviewer health, findings tally, and rubric progress, compose the pure
# rows, and style them (gum panel when available, plain text otherwise). Safe to
# call when no run/worker/rubric state exists yet — it degrades to an empty
# reviewer list and zeroed tallies rather than failing.
almanac_harden_render_dashboard() {
  local root="$1"
  local target="$2"
  local round="${3:-?}"
  local budget="${4:-?}"
  local verdict="${5:-n/a}"
  local run_id ledger_path rubric_path tally progress rows

  run_id="$(almanac_loop_latest_run_for_target "$root" "harden" "$target" || true)"
  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"

  tally="$(almanac_harden_findings_tally "$ledger_path")"
  progress="$(almanac_harden_rubric_progress "$rubric_path")"

  rows=""
  if [ -n "$run_id" ]; then
    rows="$(almanac_harden_dashboard_worker_rows "$root" "$run_id" || true)"
  fi

  printf '%s\n' "$rows" \
    | almanac_harden_dashboard_rows "$round" "$budget" "$tally" "$progress" "$verdict" \
    | almanac_loop_ui_render
}

# True (0) when at least one worker in the run is still running (its status.tsv
# status field reads "running"), so the live redraw loop can tell an ongoing run
# from a finished one. Non-zero when the run dir is absent or every worker has
# reached a terminal status (done/failed). Harden does not yet register runs in
# the run registry (deferred to #67), so the redraw loop keys on per-worker status
# rather than a run-status blob.
almanac_harden_run_has_active_worker() {
  local root="$1"
  local run_id="$2"
  local workers_dir wdir st

  workers_dir="$(almanac_loop_workers_dir "$root" "$run_id")"
  [ -d "$workers_dir" ] || return 1

  for wdir in "$workers_dir"/*/; do
    [ -d "$wdir" ] || continue
    [ -f "$wdir/status.tsv" ] || continue
    st="$(almanac_loop_status_field "$wdir/status.tsv" "status" || true)"
    [ "$st" = "running" ] && return 0
  done

  return 1
}

# Live supervision: redraw the dashboard on an interval so an operator can watch a
# harden run unfold (this is the hub's "watch a run" action and the `--watch` CLI
# mode). Each frame clears the terminal (TTY only, via almanac_loop_ui_clear) and
# reprints almanac_harden_render_dashboard from the run's live worker/ledger/rubric
# state, so reviewer health, findings tallies, rubric progress, and the verdict
# update as the run progresses.
#
# Termination is bounded by construction so it can never run forever:
#   max_frames > 0  -> render exactly that many frames (the unit-test path).
#   max_frames == 0 and stdout is NOT a TTY -> render a single frame and return,
#                     so a pipe / script / test never blocks on a live loop.
#   max_frames == 0 on a TTY -> redraw until the latest run's workers have all
#                     finished (or there is no run to watch), then return.
# interval is the seconds slept between frames.
almanac_harden_dashboard_redraw() {
  local root="$1"
  local target="$2"
  local round="${3:-live}"
  local budget="${4:-?}"
  local verdict="${5:-n/a}"
  local max_frames="${6:-0}"
  local interval="${7:-2}"
  local frames=0 run_id

  case "$max_frames" in ''|*[!0-9]*) max_frames=0 ;; esac

  if [ "$max_frames" -eq 0 ] && [ ! -t 1 ]; then
    almanac_harden_render_dashboard "$root" "$target" "$round" "$budget" "$verdict"
    return 0
  fi

  while :; do
    almanac_loop_ui_clear
    almanac_harden_render_dashboard "$root" "$target" "$round" "$budget" "$verdict"
    frames=$((frames + 1))

    if [ "$max_frames" -gt 0 ]; then
      [ "$frames" -ge "$max_frames" ] && break
    else
      run_id="$(almanac_loop_latest_run_for_target "$root" "harden" "$target" || true)"
      if [ -z "$run_id" ] || ! almanac_harden_run_has_active_worker "$root" "$run_id"; then
        break
      fi
    fi

    sleep "$interval"
  done
}

# Watch a single reviewer/worker's live event stream for the target's most recent
# run, so an operator can see what one worker is doing without the whole dashboard.
# worker_id accepts a full worker id (reviewer-correctness) or a bare lens
# (correctness) as shorthand for its reviewer worker. follow="follow" tails the
# log live on a TTY; otherwise the current contents print once. Delegates the
# actual streaming to the shared almanac_loop_worker_watch. Returns 1 (and warns)
# when no run exists for the target.
almanac_harden_watch_worker() {
  local root="$1"
  local target="$2"
  local worker_id="$3"
  local follow="${4:-}"
  local run_id status_file

  run_id="$(almanac_loop_latest_run_for_target "$root" "harden" "$target")" || {
    _warn "No harden run found for target: $target"
    return 1
  }

  # A bare lens (e.g. "security") is shorthand for its reviewer worker when no
  # worker with that exact id exists in the run.
  status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
  if [ ! -f "$status_file" ]; then
    status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "reviewer-$worker_id")"
    [ -f "$status_file" ] && worker_id="reviewer-$worker_id"
  fi

  almanac_loop_worker_watch "$root" "$run_id" "$worker_id" "$follow"
}
