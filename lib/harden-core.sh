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

  if grep -Fxq -- "- [ ] $criterion" "$path"; then
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
# separated). The lens set determines the reviewer count — there is no enforced
# cap, so adding lenses adds reviewers.
almanac_harden_lenses() {
  local raw="${HARDEN_LENSES:-correctness security perf edge-cases contracts}"

  # Trailing newline matters: a `read` loop consumer drops a final line that
  # lacks one, which would silently swallow the last lens.
  printf '%s\n' "$raw" | tr -s ', \t' '\n' | sed '/^$/d'
}

# Build the fixed prompt for one read-only reviewer over a target, including the
# JSON-Lines findings schema. When a rubric path is given and exists, the rubric's
# acceptance criteria are embedded as the bar the reviewer judges against, so
# reviewers consume the contract rather than an implicit standard. Kept separate so
# the schema can grow without touching orchestration. (Exact prompt wording is not
# asserted in tests by design; that the rubric bar is consumed is.)
almanac_harden_reviewer_prompt() {
  local target="$1"
  local lens="${2:-correctness}"
  local rubric_path="${3:-}"
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

# Print the recorded status of the finding with this id (empty when the id is
# not in the ledger). Used by ratification to tell new from already-adjudicated.
almanac_harden_ledger_status() {
  local path="$1"
  local id="$2"

  [ -f "$path" ] || return 0

  awk -v want="$id" '
    /^## / { cur = substr($0, 4); next }
    /^- status:/ && cur == want {
      val = $0
      sub(/^- status:[ \t]*/, "", val)
      print val
      exit
    }
  ' "$path"
}

# Rewrite the status (and adjudication note) of the finding with this id in
# place, leaving every other field and finding untouched. Returns 1 when the
# ledger file is absent.
almanac_harden_ledger_set_status() {
  local path="$1"
  local id="$2"
  local status="$3"
  local adjudication="${4:-}"
  local tmp

  [ -f "$path" ] || return 1

  tmp="$(mktemp "${path}.XXXXXX")"
  awk -v want="$id" -v status="$status" -v adj="$adjudication" '
    /^## / { cur = substr($0, 4); print; next }
    cur == want && /^- status:/ { print "- status: " status; next }
    cur == want && /^- adjudication:/ { print "- adjudication: " adj; next }
    { print }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

# --- Ratification engine -------------------------------------------------------
#
# A finding is "blocking" only if its demonstration objectively reproduces
# against the current target — never on a reviewer's assertion alone. Execution
# of the demonstration is isolated behind a seam (almanac_harden_demo_reproduces)
# so the decision logic is testable without running anything, and so the real
# executor (a conductor agent-runner call) can be wired in a later slice.

# Execution seam: decide whether a finding's demonstration reproduces against the
# target. Return 0 = reproduces (real defect, blocking), non-zero = does not
# reproduce (opinion / stale). The default is conservative — without a real
# executor wired it treats every demonstration as non-reproducing, so opinions
# never silently gate the loop. The convergence-loop slice overrides this with a
# conductor agent-runner call; tests override it to drive the decision paths.
almanac_harden_demo_reproduces() {
  local demonstration="$1"
  local target_path="${2:-}"

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
  local current_status reproduces status note

  almanac_harden_ledger_init "$path"
  current_status="$(almanac_harden_ledger_status "$path" "$id")"

  if almanac_harden_demo_reproduces "$demonstration" "$target_path"; then
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
# HARDEN_LENSES with no enforced cap. Each reviewer's provider/model/effort
# resolves through the shared role config
# (HARDEN_REVIEWER[_<LENS>]_{PROVIDER,MODEL,EFFORT}). _die on a missing target
# before spawning anything.
almanac_harden_fanout() {
  local root="$1"
  local target="$2"
  local target_path run_id ledger_path rubric_path lens provider model effort
  local worker_id prompt_file pidfile pid result_file status_file wstatus
  local added total_added i
  local -a lenses=() worker_ids=() worker_pids=() prompt_files=()

  case "$target" in
    /*) target_path="$target" ;;
    *)  target_path="$root/$target" ;;
  esac

  if [ ! -e "$target_path" ]; then
    _die "Harden target not found: $target"
  fi

  while IFS= read -r lens; do
    [ -n "$lens" ] || continue
    lenses+=("$lens")
  done < <(almanac_harden_lenses)

  [ "${#lenses[@]}" -gt 0 ] || _die "No reviewer lenses configured"

  run_id="$(almanac_loop_run_id "harden" "$target")"
  ledger_path="$(almanac_harden_ledger_path "$root" "$target")"
  rubric_path="$(almanac_harden_rubric_path "$root" "$target")"
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
    provider="$(almanac_loop_role_field "harden" "reviewer" "$lens" "provider" "claude")"
    model="$(almanac_loop_role_field "harden" "reviewer" "$lens" "model" "")"
    effort="$(almanac_loop_role_field "harden" "reviewer" "$lens" "effort" "")"

    worker_id="reviewer-$lens"
    prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-harden-prompt.XXXXXX")"
    # Reviewers judge against the rubric when one exists (read gracefully when
    # absent, e.g. an ad-hoc bare run with no drafted contract yet).
    almanac_harden_reviewer_prompt "$target" "$lens" "$rubric_path" > "$prompt_file"

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
  i=0
  for worker_id in "${worker_ids[@]}"; do
    lens="${lenses[$i]}"
    i=$((i + 1))
    status_file="$(almanac_loop_worker_status_file "$root" "$run_id" "$worker_id")"
    result_file="$(almanac_loop_worker_file "$root" "$run_id" "$worker_id" "result.txt")"

    wstatus=""
    if [ -f "$status_file" ]; then
      wstatus="$(almanac_loop_status_field "$status_file" "status" || true)"
    fi

    if [ "$wstatus" = "failed" ]; then
      _warn "reviewer lens=$lens failed; skipping its findings"
      continue
    fi

    _info "Findings (lens: $lens):"
    almanac_harden_format_findings "$result_file"

    if [ -f "$result_file" ]; then
      added="$(almanac_harden_ledger_record "$ledger_path" "$result_file" 1)"
      total_added=$((total_added + added))
    fi
  done

  [ "${#prompt_files[@]}" -eq 0 ] || rm -f "${prompt_files[@]}"

  # Enforce the immutability invariant: revert (and warn about) any rubric edit
  # an agent slipped in during the round.
  if [ -n "$rubric_snapshot" ]; then
    almanac_harden_rubric_verify "$rubric_path" "$rubric_snapshot" || true
  fi

  _success "Aggregated $total_added new finding(s) into ${ledger_path#"$root"/}"
}
