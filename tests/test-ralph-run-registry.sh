#!/usr/bin/env bash
# test-ralph-run-registry.sh - Ralph launcher run registry tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ONCE_SCRIPT="$ROOT/skills/loop/ralph-loop/scripts/once.sh"
AFK_SCRIPT="$ROOT/skills/loop/ralph-loop/scripts/afk.sh"

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

new_tmpdir() {
  NEW_TMPDIR=$(mktemp -d)
  TMPDIRS+=("$NEW_TMPDIR")
}

write_fake_codex() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
exit_code="${FAKE_CODEX_EXIT:-0}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
      ;;
  esac
  shift || true
done

[ -n "$result_file" ] && printf '%s\n' "fake codex complete" > "$result_file"
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_message","message":"fake codex event"}}'
exit "$exit_code"
EOF
  chmod +x "$fakebin/codex"
}

test_once_registers_and_marks_run_done() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex bash "$ONCE_SCRIPT" demo >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "ralph once should write run index"
  assert_file_contains "$index_file" $'id\ttype\ttarget\tpid\tstatus_file\tstarted_at\tstatus' "index should include header"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record ralph PRD target"
  assert_file_contains "$index_file" $'done' "index should mark run done"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph once should write status file"
  assert_file_contains "$status_file" $'type\tralph' "status should record ralph type"
  assert_file_contains "$status_file" $'target\tdocs/plans/demo/prd.md' "status should record PRD target"
  assert_file_contains "$status_file" $'status\tdone' "status should mark run done"
  echo "  PASS: once registers and marks run done"
}

test_once_marks_run_failed_on_provider_error() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex FAKE_CODEX_EXIT=7 bash "$ONCE_SCRIPT" demo >/dev/null 2>&1); then
    fail "ralph once should fail when provider exits nonzero"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed ralph once should still write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record failed ralph PRD target"
  assert_file_contains "$index_file" $'failed' "index should mark run failed"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "failed ralph once should still write status file"
  assert_file_contains "$status_file" $'status\tfailed' "status should mark run failed"
  echo "  PASS: once marks run failed on provider error"
}

test_afk_registers_and_marks_run_done() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 bash "$AFK_SCRIPT" demo 1 >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "ralph afk should write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record afk PRD target"
  assert_file_contains "$index_file" $'done' "index should mark afk run done"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph afk should write status file"
  assert_file_contains "$status_file" $'type\tralph' "status should record ralph type"
  assert_file_contains "$status_file" $'target\tdocs/plans/demo/prd.md' "status should record PRD target"
  assert_file_contains "$status_file" $'status\tdone' "status should mark afk run done"
  echo "  PASS: afk registers and marks run done"
}

test_afk_marks_run_failed_on_provider_error() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  if (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 FAKE_CODEX_EXIT=9 bash "$AFK_SCRIPT" demo 1 >/dev/null 2>&1); then
    fail "ralph afk should fail when provider exits nonzero"
  fi

  index_file="$tmp/.almanac/runs/index.tsv"
  [ -f "$index_file" ] || fail "failed ralph afk should still write run index"
  assert_file_contains "$index_file" $'ralph\tdocs/plans/demo/prd.md' "index should record failed afk PRD target"
  assert_file_contains "$index_file" $'failed' "index should mark afk run failed"

  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "failed ralph afk should still write status file"
  assert_file_contains "$status_file" $'status\tfailed' "status should mark afk run failed"
  echo "  PASS: afk marks run failed on provider error"
}

test_once_emits_live_run_progress_contract() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex bash "$ONCE_SCRIPT" demo >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph once should write status file"
  assert_file_contains "$status_file" $'round\t1' "once should record the live iteration as round in the run-status contract"
  assert_file_contains "$status_file" $'summary\tprovider=codex iteration=1/1' "once should record the live iteration summary in the run-status contract"
  echo "  PASS: once emits the live run-status progress contract"
}

test_afk_emits_live_run_progress_contract() {
  local tmp fakebin index_file status_file status_rel
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/bin"

  mkdir -p "$tmp/docs/plans/demo"
  printf '%s\n' "# Demo PRD" > "$tmp/docs/plans/demo/prd.md"
  printf '%s\n' "# Demo Prompt" > "$tmp/docs/plans/demo/prompt.md"
  write_fake_codex "$fakebin"

  (cd "$tmp" && PATH="$fakebin:$PATH" RALPH_PROVIDER=codex RALPH_NO_OVERSEE=1 bash "$AFK_SCRIPT" demo 1 >/dev/null)

  index_file="$tmp/.almanac/runs/index.tsv"
  status_rel="$(awk 'BEGIN { FS = "\t" } NR == 2 { print $5 }' "$index_file")"
  status_file="$tmp/$status_rel"
  [ -f "$status_file" ] || fail "ralph afk should write status file"
  assert_file_contains "$status_file" $'round\t1' "afk should record the live iteration as round in the run-status contract"
  assert_file_contains "$status_file" $'summary\tprovider=codex iteration=1/1' "afk should record the live iteration summary in the run-status contract"
  echo "  PASS: afk emits the live run-status progress contract"
}

echo "=== Ralph Run Registry Tests ==="
test_once_registers_and_marks_run_done
test_once_marks_run_failed_on_provider_error
test_once_emits_live_run_progress_contract
test_afk_registers_and_marks_run_done
test_afk_marks_run_failed_on_provider_error
test_afk_emits_live_run_progress_contract
