#!/usr/bin/env bash
# run.sh — the run-status record: the run registry's schema, owned in one place.
#
# A run-status *record* is a per-run status.tsv — one `key<TAB>value` line per
# field. This module owns the CANONICAL FIELD LIST and the only set/get-by-name
# accessors for it, so the run-status contract — every run (ralph or harden)
# carries exactly this key set, in this order — is enforced *by construction*:
# a caller names only the fields it has values for; the record fills in the rest,
# and no writer ever enumerates the schema by hand.
#
# Self-contained (printf/read only; no lib/core.sh dependency), so the record is
# its own test surface — tests/test-run.sh sources this file directly.
#
# (loop-engine-split slice 05 seeds run.sh with the record; later slices fold the
# run registry, control, worker health, and hub read-views in here and delete
# loop-core.sh — see CONTEXT.md's module map.)

# THE single source of truth for the run-status schema: the canonical field list
# in write order. record_set iterates exactly this list, so every record carries
# the same keys regardless of which subset a caller supplies. The first seven are
# also the registry's index.tsv columns (the lightweight list pointer); the last
# three (finished_at/round/summary) are the per-run detail the index omits.
almanac_loop_record_fields() {
  printf '%s\n' \
    id type target pid status_file started_at status finished_at round summary
}

# True when NAME is a canonical run-status field. Lets record_set reject a typo
# rather than silently writing a key no reader ever looks for.
almanac_loop_record_has_field() {
  local wanted="$1" field
  while IFS= read -r field; do
    [ "$field" = "$wanted" ] && return 0
  done <<< "$(almanac_loop_record_fields)"
  return 1
}

# Get one field from a record FILE by name. Prints the value (which may itself
# contain tabs — reassembled from the trailing columns) and returns 0; returns 1
# when the field is absent. This is the generic tab-field reader for the run
# registry; loop-core's almanac_loop_status_field is a thin alias over it for the
# worker-status and hub read paths.
almanac_loop_record_get() {
  local file="$1" wanted="$2" key value rest

  while IFS=$'\t' read -r key value rest; do
    if [ "$key" = "$wanted" ]; then
      if [ -n "${rest:-}" ]; then
        value="${value}"$'\t'"${rest}"
      fi
      printf '%s\n' "$value"
      return 0
    fi
  done < "$file"

  return 1
}

# Set one or more fields by name, round-tripping the rest. Each argument is a
# `field=value` pair (the value may itself contain `=`). The record is rewritten
# with the FULL canonical key set in canonical order: every canonical field
# already in the file is preserved unless overridden, and a not-yet-existing file
# is initialised with every key (blank where unset). So `register` seeds the
# record by naming only its known fields, while `mark`/`update` change only
# theirs and leave the rest intact — no caller enumerates the schema. Returns 2
# on a missing file argument or a `field=value` whose field is not canonical.
almanac_loop_record_set() {
  local file="$1"
  shift
  [ -n "$file" ] || return 2

  local pair pfield field cur val out=""
  local have_file=0
  if [ -f "$file" ]; then
    have_file=1
  fi

  # Reject any override outside the canonical schema before writing anything.
  for pair in "$@"; do
    pfield="${pair%%=*}"
    almanac_loop_record_has_field "$pfield" || return 2
  done

  while IFS= read -r field; do
    [ -n "$field" ] || continue
    cur=""
    if [ "$have_file" = 1 ]; then
      cur="$(almanac_loop_record_get "$file" "$field" || true)"
    fi
    val="$cur"
    for pair in "$@"; do
      pfield="${pair%%=*}"
      if [ "$pfield" = "$field" ]; then
        val="${pair#*=}"
      fi
    done
    out="${out}${field}"$'\t'"${val}"$'\n'
  done <<< "$(almanac_loop_record_fields)"

  printf '%s' "$out" > "$file"
}
