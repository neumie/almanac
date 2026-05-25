#!/usr/bin/env bash
# test-loop-core.sh - Shared loop engine behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/loop-core.sh"

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

test_detects_project_marker_commands() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  touch "$tmp/package.json"
  touch "$tmp/Makefile"
  touch "$tmp/Cargo.toml"
  touch "$tmp/go.mod"
  touch "$tmp/pyproject.toml"

  expected=$(cat <<'EOF'
npm run test
npm run typecheck
npm run lint
make test
make check
cargo test
cargo check
go test ./...
go vet ./...
pytest
mypy
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "marker files should map to feedback commands"
  echo "  PASS: detects project marker commands"
}

test_dedupes_python_markers() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  touch "$tmp/pyproject.toml"
  touch "$tmp/setup.py"

  expected=$(cat <<'EOF'
pytest
mypy
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "python markers should not duplicate commands"
  echo "  PASS: dedupes python markers"
}

test_detects_repo_test_scripts() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/tests"
  touch "$tmp/tests/test-skills.sh"
  touch "$tmp/tests/test-structure.sh"

  expected=$(cat <<'EOF'
bash tests/test-skills.sh
bash tests/test-structure.sh
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "repo test scripts should be feedback commands"
  echo "  PASS: detects repo test scripts"
}

test_registers_run_in_registry() {
  local tmp run_id status_file index_file expected_index
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_id="$(almanac_loop_register_run "$tmp" "harden" "src/app.js" "4242" "harden-src-app-js-001" "2026-05-25T12:00:00Z")"
  status_file="$tmp/.almanac/runs/harden-src-app-js-001/status.tsv"
  index_file="$tmp/.almanac/runs/index.tsv"

  expected_index=$(cat <<'EOF'
id	type	target	pid	status_file	started_at	status
harden-src-app-js-001	harden	src/app.js	4242	.almanac/runs/harden-src-app-js-001/status.tsv	2026-05-25T12:00:00Z	running
EOF
)

  assert_eq "harden-src-app-js-001" "$run_id" "register should print run id"
  [ -f "$status_file" ] || fail "register should write run status file"
  [ -f "$index_file" ] || fail "register should write run index"
  assert_eq "$expected_index" "$(cat "$index_file")" "run index should capture launched run"
  assert_file_contains "$status_file" $'id\tharden-src-app-js-001' "status should record id"
  assert_file_contains "$status_file" $'type\tharden' "status should record type"
  assert_file_contains "$status_file" $'target\tsrc/app.js' "status should record target"
  assert_file_contains "$status_file" $'pid\t4242' "status should record pid"
  assert_file_contains "$status_file" $'status\trunning' "status should start running"
  assert_file_contains "$status_file" $'started_at\t2026-05-25T12:00:00Z' "status should record start time"
  echo "  PASS: registers run in registry"
}

test_marks_registered_run_done() {
  local tmp status_file index_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_loop_register_run "$tmp" "ralph" "docs/plans/demo/prd.md" "31337" "ralph-demo-001" "2026-05-25T12:00:00Z" >/dev/null
  almanac_loop_mark_run_status "$tmp" "ralph-demo-001" "done" "2026-05-25T12:10:00Z"

  status_file="$tmp/.almanac/runs/ralph-demo-001/status.tsv"
  index_file="$tmp/.almanac/runs/index.tsv"

  assert_file_contains "$status_file" $'status\tdone' "status file should mark run done"
  assert_file_contains "$status_file" $'finished_at\t2026-05-25T12:10:00Z' "status file should record finish time"
  assert_file_contains "$index_file" $'ralph-demo-001\tralph\tdocs/plans/demo/prd.md\t31337\t.almanac/runs/ralph-demo-001/status.tsv\t2026-05-25T12:00:00Z\tdone' "index should mark run done"
  echo "  PASS: marks registered run done"
}

echo "=== Loop Core Tests ==="
test_detects_project_marker_commands
test_dedupes_python_markers
test_detects_repo_test_scripts
test_registers_run_in_registry
test_marks_registered_run_done
