#!/usr/bin/env bash
# test-harden-cli.sh - Harden CLI bootstrap behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC="$ROOT/bin/almanac"

# Source the libs for pure-function unit tests (parser/formatter). harden-core
# pulls in loop-core + core itself.
source "$ROOT/lib/harden-core.sh"

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message" ;;
  esac
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

# Fake codex that writes canned JSON-Lines findings to --output-last-message and
# logs its args, so the reviewer path is exercised without a real model call.
write_fake_reviewer_codex() {
  local fakebin="$1"
  local args_log="$2"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "\$*" > "$args_log"
result_file=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message)
      shift
      result_file="\${1:-}"
      ;;
  esac
  shift || true
done

if [ -n "\$result_file" ]; then
  {
    printf '%s\n' '{"lens":"correctness","severity":"high","location":"src/app.js:10","claim":"off-by-one in loop bound","demonstration":"input [] returns -1"}'
    printf '%s\n' '{"lens":"correctness","severity":"low","location":"src/app.js:22","claim":"unused variable x","demonstration":"lint flags x"}'
  } > "\$result_file"
fi
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"reviewing"}}'
EOF
  chmod +x "$fakebin/codex"
}

test_creates_draft_rubric_for_target_and_goal() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/lib"
  touch "$tmp/lib/loop-core.sh"

  (cd "$tmp" && "$ALMANAC" harden lib/loop-core.sh --goal "prove feedback detection cannot regress" >/dev/null)

  rubric="$tmp/docs/plans/harden/lib-loop-core-sh/rubric.md"
  [ -f "$rubric" ] || fail "harden should create default rubric path"
  assert_file_contains "$rubric" "# Harden Rubric" "rubric should have title"
  assert_file_contains "$rubric" "Target: lib/loop-core.sh" "rubric should record target"
  assert_file_contains "$rubric" "Status: draft" "rubric should start as draft"
  assert_file_contains "$rubric" "prove feedback detection cannot regress" "rubric should record goal"
  assert_file_contains "$rubric" "## Acceptance" "rubric should include acceptance section"
  assert_file_contains "$rubric" "## Context" "rubric should include context section"
  echo "  PASS: creates draft rubric for target and goal"
}

# Criterion (60.1): the conductor drafts a rubric with ALL required sections from
# target + goal. Pins every heading the rubric-contract module mandates (PRD:
# Goal, Acceptance, In/Out scope, Severity, Context) so a future edit that drops
# a section fails loudly instead of silently shrinking the contract.
test_draft_rubric_includes_all_required_sections() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  (cd "$tmp" && "$ALMANAC" harden src/widget.js --goal "no crash on empty input" >/dev/null)

  rubric="$tmp/docs/plans/harden/src-widget-js/rubric.md"
  [ -f "$rubric" ] || fail "draft should create the rubric"
  assert_file_contains "$rubric" "## Goal" "rubric must include Goal section"
  assert_file_contains "$rubric" "## Acceptance" "rubric must include Acceptance section"
  assert_file_contains "$rubric" "## In Scope" "rubric must include In Scope section"
  assert_file_contains "$rubric" "## Out of Scope" "rubric must include Out of Scope section"
  assert_file_contains "$rubric" "## Severity" "rubric must include Severity section"
  assert_file_contains "$rubric" "## Context" "rubric must include Context section"
  echo "  PASS: draft rubric includes all required sections"
}

# Criterion (60.6): works on an ad-hoc target with no prior docs/plans entry —
# the rubric is created on the fly (PRD story 26). Asserts the plan tree does NOT
# exist before the run (truly ad-hoc) and is materialised by the draft.
test_draft_rubric_created_on_the_fly_for_adhoc_target() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  [ ! -e "$tmp/docs/plans" ] || fail "ad-hoc target must start with no docs/plans entry"

  (cd "$tmp" && "$ALMANAC" harden some/adhoc/module.py --goal "harden ad-hoc module" >/dev/null)

  rubric="$tmp/docs/plans/harden/some-adhoc-module-py/rubric.md"
  [ -f "$rubric" ] || fail "rubric should be created on the fly for an ad-hoc target"
  assert_file_contains "$rubric" "Status: draft" "on-the-fly rubric should start as draft"
  assert_file_contains "$rubric" "Target: some/adhoc/module.py" "on-the-fly rubric should record the ad-hoc target"
  echo "  PASS: draft rubric created on the fly for ad-hoc target"
}

test_review_runs_single_reviewer_and_prints_findings() {
  local tmp fakebin output args
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/src"
  printf '%s\n' "code" > "$tmp/src/app.js"
  fakebin="$tmp/bin"
  write_fake_reviewer_codex "$fakebin" "$tmp/codex-args.txt"

  # HARDEN_LENSES=correctness pins the fan-out to a single reviewer so the
  # one-lens path is exercised (and the fake's single args log doesn't race).
  output="$(cd "$tmp" && HARDEN_LENSES=correctness HARDEN_REVIEWER_PROVIDER=codex PATH="$fakebin:$PATH" "$ALMANAC" harden src/app.js 2>&1)"

  assert_contains "$output" "off-by-one in loop bound" "review should print the parsed finding claim"
  assert_contains "$output" "unused variable x" "review should print all parsed findings"
  args="$(cat "$tmp/codex-args.txt")"
  assert_contains "$args" "--sandbox read-only" "reviewer should run read-only via agent_run"
  echo "  PASS: review runs single reviewer and prints findings"
}

# Fake codex for fan-out: derives its lens from the reviewer prompt, records one
# spawn file per invocation (so the test can count concurrent reviewers without
# a shared-log race), and emits a lens-specific finding so aggregation across
# reviewers is observable in the ledger.
write_fake_fanout_codex() {
  local fakebin="$1"
  local spawn_dir="$2"

  mkdir -p "$fakebin" "$spawn_dir"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail

result_file=""
sandbox=""
prompt=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message) shift; result_file="\${1:-}" ;;
    --sandbox) shift; sandbox="\${1:-}" ;;
    -*) ;;
    *) prompt="\$1" ;;
  esac
  shift || true
done

lens="\$(printf '%s\n' "\$prompt" | sed -n 's/.*Lens: \([a-z][a-z-]*\)\..*/\1/p' | head -n1)"
[ -n "\$lens" ] || lens="unknown"

spawn="\$(mktemp "$spawn_dir/call.XXXXXX")"
printf 'lens=%s sandbox=%s\n' "\$lens" "\$sandbox" > "\$spawn"

if [ -n "\$result_file" ]; then
  printf '{"lens":"%s","severity":"high","location":"src/app.js:1","claim":"%s defect","demonstration":"%s repro"}\n' "\$lens" "\$lens" "\$lens" > "\$result_file"
fi
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"reviewing"}}'
EOF
  chmod +x "$fakebin/codex"
}

test_fanout_spawns_reviewer_per_lens_and_aggregates() {
  local tmp fakebin spawn_dir output ledger spawn_count ro_count wstatus
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/src"
  printf '%s\n' "code" > "$tmp/src/app.js"
  fakebin="$tmp/bin"
  spawn_dir="$tmp/spawns"
  write_fake_fanout_codex "$fakebin" "$spawn_dir"

  output="$(cd "$tmp" && \
    HARDEN_LENSES="correctness security perf" \
    HARDEN_REVIEWER_PROVIDER=codex \
    PATH="$fakebin:$PATH" "$ALMANAC" harden src/app.js 2>&1)"

  spawn_count="$(find "$spawn_dir" -type f | wc -l | tr -d ' ')"
  [ "$spawn_count" -eq 3 ] || fail "fan-out should spawn one reviewer per configured lens (got $spawn_count)"

  ro_count="$(grep -l 'sandbox=read-only' "$spawn_dir"/* | wc -l | tr -d ' ')"
  [ "$ro_count" -eq 3 ] || fail "every reviewer should run read-only (got $ro_count)"

  ledger="$tmp/docs/plans/harden/src-app-js/findings.md"
  [ -f "$ledger" ] || fail "fan-out should aggregate findings into the ledger"
  assert_file_contains "$ledger" "correctness defect" "ledger should hold the correctness reviewer's finding"
  assert_file_contains "$ledger" "security defect" "ledger should hold the security reviewer's finding"
  assert_file_contains "$ledger" "perf defect" "ledger should hold the perf reviewer's finding"

  # Worker orchestration must track each reviewer's per-worker status (pid/status).
  wstatus="$(find "$tmp/.almanac/runs" -path '*/workers/reviewer-security/status.tsv' 2>/dev/null | head -n1)"
  [ -n "$wstatus" ] && [ -f "$wstatus" ] || fail "worker orchestration should write per-reviewer status"
  assert_file_contains "$wstatus" $'provider\tcodex' "worker status should record the reviewer's provider"
  assert_file_contains "$wstatus" $'sandbox\tread-only' "worker status should record read-only sandbox"
  assert_file_contains "$wstatus" $'status\tdone' "worker status should mark reviewer completion"
  echo "  PASS: fan-out spawns one reviewer per lens and aggregates"
}

test_fanout_blocks_until_rubric_approved() {
  local tmp fakebin spawn_dir output spawn_count ledger
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/src"
  printf '%s\n' "code" > "$tmp/src/app.js"
  fakebin="$tmp/bin"
  spawn_dir="$tmp/spawns"
  write_fake_fanout_codex "$fakebin" "$spawn_dir"

  # Draft a rubric (Status: draft). A drafted-but-unlocked contract means the
  # human is still authoring the bar; the loop must not run reviewers against it.
  (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock parse behavior" >/dev/null)

  if output=$(cd "$tmp" && \
      HARDEN_LENSES="correctness security perf" \
      HARDEN_REVIEWER_PROVIDER=codex \
      PATH="$fakebin:$PATH" "$ALMANAC" harden src/app.js 2>&1); then
    fail "fan-out must refuse to run against an unapproved rubric"
  fi
  assert_contains "$output" "not approved" "harden should report the rubric is unapproved"

  spawn_count="$(find "$spawn_dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$spawn_count" -eq 0 ] || fail "no reviewer should spawn before the rubric is approved (got $spawn_count)"

  # Lock the rubric, then the same bare run proceeds and aggregates.
  (cd "$tmp" && "$ALMANAC" harden src/app.js --approve >/dev/null)

  output="$(cd "$tmp" && \
    HARDEN_LENSES="correctness security perf" \
    HARDEN_REVIEWER_PROVIDER=codex \
    PATH="$fakebin:$PATH" "$ALMANAC" harden src/app.js 2>&1)"

  spawn_count="$(find "$spawn_dir" -type f | wc -l | tr -d ' ')"
  [ "$spawn_count" -eq 3 ] || fail "an approved rubric should let reviewers fan out (got $spawn_count)"

  ledger="$tmp/docs/plans/harden/src-app-js/findings.md"
  [ -f "$ledger" ] || fail "an approved run should aggregate findings into the ledger"
  echo "  PASS: fan-out blocks until the rubric is approved"
}

test_review_errors_on_missing_target() {
  local tmp output
  new_tmpdir
  tmp="$NEW_TMPDIR"

  if output=$(cd "$tmp" && "$ALMANAC" harden src/missing.js 2>&1); then
    fail "review should reject a missing target"
  fi
  assert_contains "$output" "not found" "review should report the missing target via _die"
  echo "  PASS: review errors on missing target"
}

test_format_findings_skips_malformed_lines() {
  local tmp result output
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"

  {
    printf '%s\n' '{"lens":"security","severity":"high","location":"a.js:1","claim":"sql injection","demonstration":"payload OR 1=1"}'
    printf '%s\n' 'this is not json'
    printf '%s\n' ''
  } > "$result"

  output="$(almanac_harden_format_findings "$result")"

  assert_contains "$output" "sql injection" "parser should surface a well-formed finding"
  case "$output" in
    *"this is not json"*) fail "parser should drop malformed lines" ;;
    *) ;;
  esac
  echo "  PASS: format findings skips malformed lines"
}

test_format_findings_reports_empty() {
  local tmp result output
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"
  : > "$result"

  output="$(almanac_harden_format_findings "$result")"
  assert_contains "$output" "No findings" "empty reviewer output should report no findings"
  echo "  PASS: format findings reports empty"
}

# Two well-formed findings, one per line, for ledger/parser exercises.
write_two_findings() {
  local result="$1"
  {
    printf '%s\n' '{"lens":"correctness","severity":"high","location":"src/app.js:10","claim":"off-by-one in loop bound","demonstration":"input [] returns -1"}'
    printf '%s\n' '{"lens":"security","severity":"medium","location":"src/auth.js:3","claim":"weak token check","demonstration":"forged token passes"}'
  } > "$result"
}

test_parse_findings_emits_ledger_entries() {
  local tmp result rows count
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"
  write_two_findings "$result"

  rows="$(almanac_harden_parse_findings "$result" 2)"

  count="$(printf '%s\n' "$rows" | grep -c '^f-')"
  [ "$count" -eq 2 ] || fail "parse should emit one ledger row per well-formed finding (got $count)"
  assert_contains "$rows" "off-by-one in loop bound" "parse should carry the claim"
  assert_contains "$rows" $'\topen\t2\t' "parse should mark new findings open at the given round"
  echo "  PASS: parse findings emits ledger entries"
}

test_parse_findings_skips_malformed() {
  local tmp result rows count
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"
  {
    printf '%s\n' '{"lens":"correctness","severity":"high","location":"a.js:1","claim":"real bug","demonstration":"repro"}'
    printf '%s\n' 'not json at all'
    printf '%s\n' ''
  } > "$result"

  rows="$(almanac_harden_parse_findings "$result" 1)"

  count="$(printf '%s\n' "$rows" | grep -c '^f-')"
  [ "$count" -eq 1 ] || fail "parse should drop malformed lines and keep the valid one (got $count)"
  case "$rows" in
    *"not json at all"*) fail "parse should not emit malformed input" ;;
    *) ;;
  esac
  echo "  PASS: parse findings skips malformed lines"
}

test_ledger_appends_and_queries_open_blocking() {
  local tmp result ledger open
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"
  ledger="$tmp/findings.md"
  write_two_findings "$result"

  almanac_harden_ledger_record "$ledger" "$result" 1 >/dev/null

  assert_file_contains "$ledger" "# Findings Ledger" "ledger should have a header"
  assert_file_contains "$ledger" "off-by-one in loop bound" "ledger should record the claim"
  assert_file_contains "$ledger" "- status: open" "ledger entries should default to open"
  assert_file_contains "$ledger" "- round: 1" "ledger entries should record the round"

  open="$(almanac_harden_ledger_open_blocking "$ledger")"
  assert_contains "$open" "off-by-one in loop bound" "open-blocking should return open findings"
  assert_contains "$open" "weak token check" "open-blocking should return every open finding"
  echo "  PASS: ledger appends and queries open blocking"
}

test_ledger_dedupes_prior_adjudicated() {
  local tmp result ledger id added open dup_count
  new_tmpdir
  tmp="$NEW_TMPDIR"
  result="$tmp/result.txt"
  ledger="$tmp/findings.md"
  write_two_findings "$result"

  # Pre-adjudicate the off-by-one finding as rejected-subjective.
  id="$(almanac_harden_finding_id "correctness" "src/app.js:10" "off-by-one in loop bound")"
  almanac_harden_ledger_append_entry "$ledger" "$id" "correctness" "high" \
    "src/app.js:10" "off-by-one in loop bound" "old demo" "rejected-subjective" 1 "opinion only" >/dev/null

  # Recording the reviewer output must skip the already-adjudicated finding.
  added="$(almanac_harden_ledger_record "$ledger" "$result" 2)"
  [ "$added" -eq 1 ] || fail "record should add only the genuinely new finding (got $added)"

  dup_count="$(grep -c "^## $id\$" "$ledger")"
  [ "$dup_count" -eq 1 ] || fail "duplicate finding should not be re-added (got $dup_count entries)"

  open="$(almanac_harden_ledger_open_blocking "$ledger")"
  case "$open" in
    *"off-by-one in loop bound"*) fail "rejected-subjective finding must not be open-blocking" ;;
    *) ;;
  esac
  assert_contains "$open" "weak token check" "the new finding should be open-blocking"
  echo "  PASS: ledger dedupes prior adjudicated finding"
}

# Ratification engine: override the execution seam so a demonstration only
# "reproduces" when its text contains the word reproduce. Logs each call so
# tests can assert the seam actually executed the demonstration.
ratify_seam_repro_on_keyword() {
  almanac_harden_demo_reproduces() {
    printf '%s\n' "$1" >> "$SEAM_LOG"
    case "$1" in
      *reproduce*) return 0 ;;
      *) return 1 ;;
    esac
  }
}

test_ratify_new_reproducing_finding_is_blocking() {
  local tmp ledger id verdict open
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ledger="$tmp/findings.md"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword

  id="$(almanac_harden_finding_id "correctness" "a.js:1" "real bug")"
  verdict="$(almanac_harden_ratify "$ledger" "$id" "correctness" "high" \
    "a.js:1" "real bug" "input X reproduce the crash" 1)"

  [ "$verdict" = "blocking" ] || fail "reproducing finding should ratify as blocking (got $verdict)"
  assert_file_contains "$SEAM_LOG" "reproduce" "ratify should execute the demonstration via the seam"
  assert_file_contains "$ledger" "- status: open" "ratified finding should be open/blocking"
  assert_file_contains "$ledger" "reproduced" "ratify should record that the demonstration reproduced"
  open="$(almanac_harden_ledger_open_blocking "$ledger")"
  assert_contains "$open" "real bug" "ratified blocking finding should appear in open-blocking"
  echo "  PASS: ratify marks a reproducing finding blocking"
}

test_ratify_nonreproducing_finding_is_note() {
  local tmp ledger id verdict open
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ledger="$tmp/findings.md"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword

  id="$(almanac_harden_finding_id "style" "a.js:2" "prefer composition")"
  verdict="$(almanac_harden_ratify "$ledger" "$id" "style" "low" \
    "a.js:2" "prefer composition" "I would prefer composition here" 1)"

  [ "$verdict" = "note" ] || fail "non-reproducing/opinion finding should be a note (got $verdict)"
  assert_file_contains "$SEAM_LOG" "prefer composition" "ratify should execute the demonstration via the seam"
  assert_file_contains "$ledger" "- status: rejected-subjective" "non-reproducing finding should be a non-blocking note"
  open="$(almanac_harden_ledger_open_blocking "$ledger")"
  case "$open" in
    *"prefer composition"*) fail "a note must not appear in open-blocking" ;;
    *) ;;
  esac
  echo "  PASS: ratify records a non-reproducing finding as a note"
}

test_ratify_adjudicated_not_relitigated_when_not_reproducing() {
  local tmp ledger id verdict dup
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ledger="$tmp/findings.md"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword

  id="$(almanac_harden_finding_id "style" "a.js:2" "prefer composition")"
  # Pre-adjudicate as rejected-subjective in a prior round.
  almanac_harden_ledger_append_entry "$ledger" "$id" "style" "low" \
    "a.js:2" "prefer composition" "opinion" "rejected-subjective" 1 "opinion only" >/dev/null

  verdict="$(almanac_harden_ratify "$ledger" "$id" "style" "low" \
    "a.js:2" "prefer composition" "still just an opinion" 2)"

  [ "$verdict" = "dropped" ] || fail "already-rejected finding that doesn't reproduce should drop (got $verdict)"
  assert_file_contains "$ledger" "- status: rejected-subjective" "dropped finding stays adjudicated"
  dup="$(grep -c "^## $id\$" "$ledger")"
  [ "$dup" -eq 1 ] || fail "ratify must not re-add an adjudicated finding (got $dup)"
  echo "  PASS: ratify does not re-litigate a non-reproducing adjudicated finding"
}

test_ratify_adjudicated_reopens_when_newly_reproducing() {
  local tmp ledger id verdict open
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ledger="$tmp/findings.md"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword

  id="$(almanac_harden_finding_id "correctness" "a.js:3" "race condition")"
  # Previously rejected as unreproducible; the code has since changed.
  almanac_harden_ledger_append_entry "$ledger" "$id" "correctness" "high" \
    "a.js:3" "race condition" "old demo" "rejected-subjective" 1 "could not reproduce" >/dev/null

  verdict="$(almanac_harden_ratify "$ledger" "$id" "correctness" "high" \
    "a.js:3" "race condition" "new input reproduce the race" 2)"

  [ "$verdict" = "reopened" ] || fail "adjudicated finding that newly reproduces should reopen (got $verdict)"
  assert_file_contains "$ledger" "- status: open" "reopened finding should be open/blocking"
  open="$(almanac_harden_ledger_open_blocking "$ledger")"
  assert_contains "$open" "race condition" "reopened finding should appear in open-blocking"
  echo "  PASS: ratify reopens an adjudicated finding when it newly reproduces"
}

test_refuses_to_overwrite_existing_rubric() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock behavior" >/dev/null)
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  printf '%s\n' "DO NOT OVERWRITE" >> "$rubric"

  if (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock behavior" >/dev/null 2>&1); then
    fail "harden should refuse existing rubric"
  fi
  assert_file_contains "$rubric" "DO NOT OVERWRITE" "existing rubric should not be overwritten"
  echo "  PASS: refuses to overwrite existing rubric"
}

test_approves_existing_draft_rubric() {
  local tmp rubric
  new_tmpdir
  tmp="$NEW_TMPDIR"

  (cd "$tmp" && "$ALMANAC" harden src/app.js --goal "lock behavior" >/dev/null)
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  printf '%s\n' "- Existing context survives approval." >> "$rubric"

  (cd "$tmp" && "$ALMANAC" harden src/app.js --approve >/dev/null)

  assert_file_contains "$rubric" "Status: approved" "approval should mark rubric approved"
  assert_file_contains "$rubric" "## Approval" "approval should append approval section"
  assert_file_contains "$rubric" "Approved:" "approval should record timestamp"
  assert_file_contains "$rubric" "Existing context survives approval." "approval should preserve edited rubric content"
  echo "  PASS: approves existing draft rubric"
}

test_approve_requires_existing_rubric() {
  local tmp output
  new_tmpdir
  tmp="$NEW_TMPDIR"

  if output=$(cd "$tmp" && "$ALMANAC" harden src/app.js --approve 2>&1); then
    fail "harden should reject approval without an existing rubric"
  fi
  case "$output" in
    *"Rubric not found"*) ;;
    *) fail "approval should report missing rubric" ;;
  esac
  echo "  PASS: approve requires existing rubric"
}

# --- Rubric as the bar (draft -> consume -> grow) ----------------------------

test_rubric_acceptance_lists_only_acceptance_criteria() {
  local tmp rubric acc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  rubric="$tmp/rubric.md"
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"

  acc="$(almanac_harden_rubric_acceptance "$rubric")"

  assert_contains "$acc" "Project feedback loops pass after fixes." "acceptance should list the rubric's criteria"
  case "$acc" in
    *"## In Scope"*) fail "acceptance should stop at the next section heading" ;;
    *) ;;
  esac
  case "$acc" in
    *"- src/app.js"*) fail "acceptance should not bleed into the In Scope bullets" ;;
    *) ;;
  esac
  echo "  PASS: rubric acceptance lists only acceptance criteria"
}

test_rubric_append_criterion_is_append_only_and_idempotent() {
  local tmp rubric body count
  new_tmpdir
  tmp="$NEW_TMPDIR"
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"

  almanac_harden_rubric_append_criterion "$rubric" "null input must not crash parse()"
  assert_file_contains "$rubric" "- [ ] null input must not crash parse()" "criterion should be appended"
  # Original acceptance criteria survive (append-only, never rewritten).
  assert_file_contains "$rubric" "Project feedback loops pass after fixes." "append must preserve existing criteria"
  # The new criterion lands inside the Acceptance section, before In Scope.
  body="$(almanac_harden_rubric_acceptance "$rubric")"
  assert_contains "$body" "null input must not crash parse()" "new criterion should be inside the Acceptance section"

  # Idempotent: re-appending the same criterion is a no-op (returns 1, no dup).
  if almanac_harden_rubric_append_criterion "$rubric" "null input must not crash parse()"; then
    fail "re-appending an identical criterion should report a no-op"
  fi
  count="$(grep -c -- "- \[ \] null input must not crash parse()" "$rubric")"
  [ "$count" -eq 1 ] || fail "identical criterion must not be duplicated (got $count)"
  echo "  PASS: rubric append is append-only and idempotent"
}

test_reviewer_prompt_consumes_rubric_bar() {
  local tmp rubric prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  almanac_harden_rubric_append_criterion "$rubric" "tokens older than 1h are rejected"

  prompt="$(almanac_harden_reviewer_prompt "src/app.js" "security" "$rubric")"

  assert_contains "$prompt" "tokens older than 1h are rejected" "reviewer prompt should embed the rubric acceptance bar"
  # Without a rubric the prompt still builds (graceful for ad-hoc bare runs).
  prompt="$(almanac_harden_reviewer_prompt "src/app.js" "security")"
  assert_contains "$prompt" "read-only code reviewer" "reviewer prompt should build without a rubric"
  echo "  PASS: reviewer prompt consumes the rubric bar"
}

test_ratify_blocking_grows_rubric_acceptance() {
  local tmp rubric ledger id verdict
  new_tmpdir
  tmp="$NEW_TMPDIR"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  ledger="$tmp/findings.md"

  id="$(almanac_harden_finding_id "correctness" "a.js:1" "off-by-one")"
  verdict="$(almanac_harden_ratify "$ledger" "$id" "correctness" "high" \
    "a.js:1" "off-by-one" "input X reproduce the crash" 1 "" "$rubric")"

  [ "$verdict" = "blocking" ] || fail "reproducing finding should ratify blocking (got $verdict)"
  assert_file_contains "$rubric" "off-by-one — must not reproduce (lens: correctness, at a.js:1)" \
    "a ratified blocking finding should append a criterion to the rubric"
  # Original criteria are untouched (monotonic growth, not rewrite).
  assert_file_contains "$rubric" "Project feedback loops pass after fixes." "rubric growth must be append-only"
  echo "  PASS: ratify blocking grows rubric acceptance"
}

test_ratify_note_leaves_rubric_unchanged() {
  local tmp rubric ledger id verdict before after
  new_tmpdir
  tmp="$NEW_TMPDIR"
  SEAM_LOG="$tmp/seam.log"
  : > "$SEAM_LOG"
  ratify_seam_repro_on_keyword
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  ledger="$tmp/findings.md"
  before="$(cat "$rubric")"

  id="$(almanac_harden_finding_id "style" "a.js:2" "prefer composition")"
  verdict="$(almanac_harden_ratify "$ledger" "$id" "style" "low" \
    "a.js:2" "prefer composition" "I would prefer composition here" 1 "" "$rubric")"

  [ "$verdict" = "note" ] || fail "opinion finding should be a note (got $verdict)"
  after="$(cat "$rubric")"
  [ "$before" = "$after" ] || fail "a non-reproducing note must not grow the rubric bar"
  echo "  PASS: ratify note leaves rubric unchanged"
}

# --- Rubric immutability (agents cannot move the goalposts during a run) -------

test_rubric_guard_reverts_agent_edit() {
  local tmp rubric snap before after warn rc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  before="$(cat "$rubric")"

  snap="$(almanac_harden_rubric_snapshot "$rubric")"
  [ -n "$snap" ] && [ -f "$snap" ] || fail "snapshot should create a protected copy of the rubric"

  # Simulate an agent rewriting the contract mid-run (e.g. lowering the bar).
  printf '%s\n' "# Hijacked" "## Acceptance" "- [ ] agent lowered the bar" > "$rubric"

  warn="$(almanac_harden_rubric_verify "$rubric" "$snap" 2>&1)" && rc=0 || rc=$?

  [ "$rc" -eq 1 ] || fail "verify should report a reverted modification (got $rc)"
  after="$(cat "$rubric")"
  [ "$before" = "$after" ] || fail "an agent edit to the rubric must be reverted byte-for-byte"
  assert_contains "$warn" "immutable to agents" "verify should warn that the rubric was reverted"
  [ ! -f "$snap" ] || fail "verify should discard the snapshot after reverting"
  echo "  PASS: rubric guard reverts an agent edit during a run"
}

test_rubric_guard_keeps_untouched_rubric() {
  local tmp rubric snap before after rc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  almanac_harden_write_rubric "$tmp" "src/app.js" "lock behavior"
  rubric="$tmp/docs/plans/harden/src-app-js/rubric.md"
  before="$(cat "$rubric")"

  snap="$(almanac_harden_rubric_snapshot "$rubric")"
  almanac_harden_rubric_verify "$rubric" "$snap" && rc=0 || rc=$?

  [ "$rc" -eq 0 ] || fail "verify should report no change for an untouched rubric (got $rc)"
  after="$(cat "$rubric")"
  [ "$before" = "$after" ] || fail "an untouched rubric must be left exactly as-is"
  [ ! -f "$snap" ] || fail "verify should discard the snapshot"
  echo "  PASS: rubric guard leaves an untouched rubric unchanged"
}

echo "=== Harden CLI Tests ==="
test_creates_draft_rubric_for_target_and_goal
test_draft_rubric_includes_all_required_sections
test_draft_rubric_created_on_the_fly_for_adhoc_target
test_refuses_to_overwrite_existing_rubric
test_approves_existing_draft_rubric
test_approve_requires_existing_rubric
test_rubric_acceptance_lists_only_acceptance_criteria
test_rubric_append_criterion_is_append_only_and_idempotent
test_reviewer_prompt_consumes_rubric_bar
test_ratify_blocking_grows_rubric_acceptance
test_ratify_note_leaves_rubric_unchanged
test_rubric_guard_reverts_agent_edit
test_rubric_guard_keeps_untouched_rubric
test_review_runs_single_reviewer_and_prints_findings
test_fanout_spawns_reviewer_per_lens_and_aggregates
test_fanout_blocks_until_rubric_approved
test_review_errors_on_missing_target
test_format_findings_skips_malformed_lines
test_format_findings_reports_empty
test_parse_findings_emits_ledger_entries
test_parse_findings_skips_malformed
test_ledger_appends_and_queries_open_blocking
test_ledger_dedupes_prior_adjudicated
test_ratify_new_reproducing_finding_is_blocking
test_ratify_nonreproducing_finding_is_note
test_ratify_adjudicated_not_relitigated_when_not_reproducing
test_ratify_adjudicated_reopens_when_newly_reproducing
