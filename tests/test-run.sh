#!/usr/bin/env bash
# test-run.sh - run-status record tests (lib/run.sh)
#
# Sources lib/run.sh DIRECTLY (not through loop-core) so the run-status record —
# almanac_loop_record_fields / _has_field / _get / _set — is its own test
# surface. The record owns the canonical run-status field list; these tests pin
# the set/get-by-name accessors, the round-trip-preserving write, and the
# identical-key-set-by-construction contract that the registry (test-loop-core)
# and hub (test-hub) build on.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/run.sh"

TMPDIRS=()
NEW_TMPDIR=""

cleanup() {
  local dir
  [ "${#TMPDIRS[@]}" -eq 0 ] && return 0
  for dir in "${TMPDIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

echo "=== Run-Status Record Tests ==="

test_record_fields_is_canonical_schema() {
  local expected actual
  expected=$(printf '%s\n' \
    id type target pid status_file started_at status finished_at round summary)
  actual="$(almanac_loop_record_fields)"
  assert_eq "$expected" "$actual" "record_fields must be the canonical run-status schema, in order"
  echo "  PASS: record_fields is the canonical schema"
}

test_record_has_field_recognises_only_canonical() {
  almanac_loop_record_has_field "id" || fail "id must be a canonical field"
  almanac_loop_record_has_field "summary" || fail "summary must be a canonical field"
  if almanac_loop_record_has_field "bogus"; then
    fail "a non-canonical field must not be recognised"
  fi
  echo "  PASS: record_has_field recognises only canonical fields"
}

test_record_set_initialises_full_key_set() {
  local tmp file keys expected
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  # Name only a subset; the record must still carry EVERY canonical key in order.
  almanac_loop_record_set "$file" "id=r1" "type=ralph" "status=running"

  keys="$(cut -f1 "$file")"
  expected="$(almanac_loop_record_fields)"
  assert_eq "$expected" "$keys" "a fresh record must carry every canonical key in order"
  assert_eq "r1" "$(almanac_loop_record_get "$file" id)" "supplied id must be set"
  assert_eq "ralph" "$(almanac_loop_record_get "$file" type)" "supplied type must be set"
  assert_eq "running" "$(almanac_loop_record_get "$file" status)" "supplied status must be set"
  assert_eq "" "$(almanac_loop_record_get "$file" summary)" "an unsupplied field must be present but blank"
  echo "  PASS: record_set initialises the full canonical key set"
}

test_record_set_round_trips_untouched_fields() {
  local tmp file
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  almanac_loop_record_set "$file" \
    "id=r1" "type=harden" "target=src/app.js" "pid=42" "status=running" "started_at=T0"
  # update only live progress
  almanac_loop_record_set "$file" "round=3" "summary=lenses=security open-blocking=2"
  # mark terminal
  almanac_loop_record_set "$file" "status=done" "finished_at=T1"

  assert_eq "r1"         "$(almanac_loop_record_get "$file" id)"          "id preserved across sets"
  assert_eq "harden"     "$(almanac_loop_record_get "$file" type)"        "type preserved"
  assert_eq "src/app.js" "$(almanac_loop_record_get "$file" target)"      "target preserved"
  assert_eq "42"         "$(almanac_loop_record_get "$file" pid)"         "pid preserved"
  assert_eq "T0"         "$(almanac_loop_record_get "$file" started_at)"  "started_at preserved"
  assert_eq "3"          "$(almanac_loop_record_get "$file" round)"       "round set"
  assert_eq "lenses=security open-blocking=2" \
    "$(almanac_loop_record_get "$file" summary)" "a value containing '=' is preserved verbatim"
  assert_eq "done"       "$(almanac_loop_record_get "$file" status)"      "status updated"
  assert_eq "T1"         "$(almanac_loop_record_get "$file" finished_at)" "finished_at set"
  echo "  PASS: record_set round-trips untouched fields"
}

test_record_get_absent_field_returns_nonzero() {
  local tmp file rc
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"
  printf 'id\tr1\n' > "$file"   # a partial record missing most keys

  rc=0; almanac_loop_record_get "$file" "summary" >/dev/null || rc=$?
  assert_eq "1" "$rc" "record_get must return 1 for an absent field"
  echo "  PASS: record_get returns non-zero for an absent field"
}

test_record_set_rejects_unknown_field() {
  local tmp file rc
  new_tmpdir; tmp="$NEW_TMPDIR"; file="$tmp/status.tsv"

  rc=0; almanac_loop_record_set "$file" "bogus=x" || rc=$?
  assert_eq "2" "$rc" "record_set must reject a non-canonical field"
  if [ -f "$file" ]; then
    fail "record_set must not write the file when an override is rejected"
  fi
  echo "  PASS: record_set rejects unknown fields"
}

test_record_set_requires_file_arg() {
  local rc
  rc=0; almanac_loop_record_set "" "status=done" || rc=$?
  assert_eq "2" "$rc" "record_set must require a file path"
  echo "  PASS: record_set requires a file argument"
}

test_records_share_identical_key_set_by_construction() {
  local tmp ralph harden ralph_keys harden_keys
  new_tmpdir; tmp="$NEW_TMPDIR"
  ralph="$tmp/ralph.tsv"; harden="$tmp/harden.tsv"

  # Two loops set DIFFERENT subsets — the key set must still be identical because
  # both writes iterate the one canonical field list.
  almanac_loop_record_set "$ralph" \
    "id=a" "type=ralph" "target=prd.md" "status=running"
  almanac_loop_record_set "$harden" \
    "id=b" "type=harden" "target=src/x.js" "status=running" "round=1" "summary=lenses=security"

  ralph_keys="$(cut -f1 "$ralph")"
  harden_keys="$(cut -f1 "$harden")"
  assert_eq "$ralph_keys" "$harden_keys" \
    "ralph and harden records must carry an identical key set by construction"
  assert_eq "$(almanac_loop_record_fields)" "$ralph_keys" \
    "the shared key set must be the canonical schema"
  echo "  PASS: records share an identical key set by construction"
}

test_record_fields_is_canonical_schema
test_record_has_field_recognises_only_canonical
test_record_set_initialises_full_key_set
test_record_set_round_trips_untouched_fields
test_record_get_absent_field_returns_nonzero
test_record_set_rejects_unknown_field
test_record_set_requires_file_arg
test_records_share_identical_key_set_by_construction

echo ""
echo "All run-status record tests passed."
