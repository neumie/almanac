#!/usr/bin/env bash
# test-ralph-smoke.sh — End-to-end smoke run of the `almanac ralph` CLI.
#
# Unlike test-ralph-run-registry.sh (which drives once.sh/afk.sh DIRECTLY), these
# tests exercise the FULL user-facing command chain — bin/almanac -> cmd/ralph.sh
# -> the launcher ralph.sh (arg parsing, provider validation, env export, PRD/
# prompt checks, mode dispatch) -> once.sh/afk.sh — behind a fake provider, with
# NO real model calls (per the PRD's testing discipline: "tested behind a fake
# provider, no real model calls"). This is the criterion-5 proof for #66 (ralph
# migration onto the shared engine): a smoke run of `almanac ralph` behaves as
# before — same iteration, commit, and overseer behavior.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC="$ROOT/bin/almanac"

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
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

# grep -F based so needles with shell-glob metacharacters (e.g. "[overseer]")
# match literally, unlike a case-glob `*"$needle"*`.
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if ! printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "$message"
  fi
}

refute_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "$message"
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

# Create the docs/plans/<demo> PRD + prompt the launcher requires under $1.
seed_prd() {
  local base="$1"
  mkdir -p "$base/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$base/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$base/docs/plans/demo/prompt.md"
}

# Fake codex: writes its final message (overridable via $FAKE_CODEX_RESULT, so a
# test can inject a <promise> token) to --output-last-message, emits one
# agent_message stream event, and exits ($FAKE_CODEX_EXIT, default 0). No real
# model call.
write_fake_codex_smoke() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) shift; result_file="${1:-}" ;;
  esac
  shift || true
done

[ -n "$result_file" ] && printf '%s\n' "${FAKE_CODEX_RESULT:-fake codex progress (no promise)}" > "$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"smoke iteration"}}'
exit "${FAKE_CODEX_EXIT:-0}"
EOF
  chmod +x "$fakebin/codex"
}

# Fake codex that also makes a RALPH commit in its cwd (the work repo), so the
# end-to-end push path — afk's end-of-loop push_ralph_commits — has a real commit
# to share. Stands in for the iteration agent committing during a real run.
write_fake_codex_committing() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) shift; result_file="${1:-}" ;;
  esac
  shift || true
done

printf 'agent change\n' > ralph-agent-change.txt
git add ralph-agent-change.txt >/dev/null 2>&1
git commit -q -m "RALPH(demo): fake agent change" >/dev/null 2>&1

[ -n "$result_file" ] && printf '%s\n' "fake codex progress (no promise)" > "$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"committed"}}'
exit 0
EOF
  chmod +x "$fakebin/codex"
}

test_afk_ci_monitor_noops_without_jq() {
  local body
  body="$(sed -n '/^check_ci_status()/,/^}/p' "$ROOT/skills/loop/ralph-loop/scripts/afk.sh")"
  assert_contains "$body" "command -v jq >/dev/null 2>&1 || return 0" \
    "AFK CI monitor should no-op when gh returns runs but jq is unavailable"
  echo "  PASS: AFK CI monitor no-ops without jq"
}

# `almanac ralph --mode once` dispatches end-to-end through the launcher to
# once.sh, runs the single iteration, and registers a run marked done.
test_almanac_ralph_once_smoke() {
  local tmp fakebin out index
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  seed_prd "$tmp"
  write_fake_codex_smoke "$fakebin"

  out="$(cd "$tmp" && PATH="$fakebin:$PATH" "$ALMANAC" ralph \
    --prd demo --mode once --provider codex --model default --effort default </dev/null 2>&1)"

  assert_contains "$out" "RALPH ONCE" "almanac ralph --mode once should dispatch through the launcher to once.sh"

  index="$tmp/.almanac/runs/index.tsv"
  [ -f "$index" ] || fail "almanac ralph once should register a run end-to-end"
  assert_file_contains "$index" $'ralph\tdocs/plans/demo/prd.md' "once run should record the ralph PRD target"
  assert_file_contains "$index" $'done' "once run should be marked done end-to-end"
  echo "  PASS: almanac ralph once smoke run registers and completes"
}

# `almanac ralph --mode afk --iterations N` runs exactly N iterations when the
# agent never signals completion (iteration behavior preserved).
test_almanac_ralph_afk_runs_requested_iterations() {
  local tmp fakebin out index
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  seed_prd "$tmp"
  write_fake_codex_smoke "$fakebin"

  out="$(cd "$tmp" && PATH="$fakebin:$PATH" "$ALMANAC" ralph \
    --prd demo --mode afk --iterations 2 --provider codex --model default --effort default \
    --no-oversee </dev/null 2>&1)"

  assert_contains "$out" "ITERATION 1 of 2" "afk should run the first iteration"
  assert_contains "$out" "ITERATION 2 of 2" "afk should run the full requested iteration budget"
  assert_contains "$out" "Ralph finished 2 iterations" "afk should report finishing the iteration budget"

  index="$tmp/.almanac/runs/index.tsv"
  assert_file_contains "$index" $'done' "afk run should be marked done end-to-end"
  echo "  PASS: almanac ralph afk runs the requested iteration count"
}

# afk stops as soon as the agent's result carries <promise>COMPLETE</promise> —
# it does not exhaust the budget (commit/completion-lifecycle behavior preserved).
test_almanac_ralph_afk_stops_on_completion_promise() {
  local tmp fakebin out index
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  seed_prd "$tmp"
  write_fake_codex_smoke "$fakebin"

  out="$(cd "$tmp" && PATH="$fakebin:$PATH" \
    FAKE_CODEX_RESULT='all done <promise>COMPLETE</promise>' "$ALMANAC" ralph \
    --prd demo --mode afk --iterations 5 --provider codex --model default --effort default \
    --no-oversee </dev/null 2>&1)"

  assert_contains "$out" "ITERATION 1 of 5" "afk should run the first iteration"
  assert_contains "$out" "Ralph complete after 1 iterations" "afk should stop when the agent signals <promise>COMPLETE</promise>"
  refute_contains "$out" "ITERATION 2 of 5" "afk must not run further iterations after the completion promise"

  index="$tmp/.almanac/runs/index.tsv"
  assert_file_contains "$index" $'done' "completed afk run should be marked done"
  echo "  PASS: almanac ralph afk stops on the completion promise"
}

# The launcher wires the overseer through to afk both ways: on by default (stdin
# EOF -> the launcher's 'on' default) and off with --no-oversee. Interval=1 so any
# orphaned overseer sleep dies within a second; output is captured to a file (the
# overseer backgrounds a subshell, so a live pipe could block on the orphan).
test_almanac_ralph_afk_overseer_wiring() {
  local tmp fakebin out_on out_off
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  seed_prd "$tmp"
  write_fake_codex_smoke "$fakebin"

  out_on="$tmp/oversee-on.out"
  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_OVERSEE_INTERVAL=1 "$ALMANAC" ralph \
    --prd demo --mode afk --iterations 1 --provider codex --model default --effort default \
    </dev/null > "$out_on" 2>&1)
  assert_file_contains "$out_on" "[overseer] started" "almanac ralph afk should start the overseer by default"

  out_off="$(cd "$tmp" && PATH="$fakebin:$PATH" "$ALMANAC" ralph \
    --prd demo --mode afk --iterations 1 --provider codex --model default --effort default \
    --no-oversee </dev/null 2>&1)"
  assert_contains "$out_off" "[overseer] disabled" "almanac ralph afk --no-oversee should disable the overseer"
  echo "  PASS: almanac ralph afk wires the overseer (on by default, off with --no-oversee)"
}

# End-to-end commit behavior: `almanac ralph` afk pushes the iteration agent's
# RALPH commit to the remote at end-of-loop, exactly as before the migration.
test_almanac_ralph_afk_pushes_agent_commits() {
  local tmp fakebin work remote_head work_head subj
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"
  work="$tmp/work"

  git init --bare "$tmp/origin.git" >/dev/null 2>&1
  git clone "$tmp/origin.git" "$work" >/dev/null 2>&1
  (
    cd "$work"
    git config user.email "test@example.com"
    git config user.name "Almanac Test"
    git config commit.gpgsign false
    printf 'base\n' > README.md
    git add README.md
    git commit -q -m "base"
    git branch -M main
    git push -q -u origin main
    seed_prd "$work"
  )
  write_fake_codex_committing "$fakebin"

  (cd "$work" && PATH="$fakebin:$PATH" "$ALMANAC" ralph \
    --prd demo --mode afk --iterations 1 --provider codex --model default --effort default \
    --no-oversee </dev/null >/dev/null 2>&1)

  remote_head="$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/main)"
  work_head="$(cd "$work" && git rev-parse HEAD)"
  assert_eq "$work_head" "$remote_head" "almanac ralph afk should push the agent's commit to origin (commit behavior preserved)"

  subj="$(git --git-dir="$tmp/origin.git" log -1 --format=%s refs/heads/main)"
  assert_contains "$subj" "RALPH(demo)" "the pushed commit should be the agent's RALPH commit"
  echo "  PASS: almanac ralph afk pushes the agent's commit end-to-end"
}

echo "=== Ralph CLI Smoke Tests ==="
test_afk_ci_monitor_noops_without_jq
test_almanac_ralph_once_smoke
test_almanac_ralph_afk_runs_requested_iterations
test_almanac_ralph_afk_stops_on_completion_promise
test_almanac_ralph_afk_overseer_wiring
test_almanac_ralph_afk_pushes_agent_commits
