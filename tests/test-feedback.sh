#!/usr/bin/env bash
# test-feedback.sh - feedback detection + runner tests (lib/feedback.sh)
#
# Sources lib/feedback.sh DIRECTLY (not through loop-core) so the feedback
# engine — almanac_loop_feedback_commands (detection) and
# almanac_loop_feedback_run (runner) — is its own test surface. These pin the
# marker-file → command mapping (shared by Loop's prompt and harden's fixer)
# and the per-loop pass/fail verdict + aggregate exit code the fixer gates on.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/feedback.sh"

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

echo "=== Feedback Detection + Runner Tests ==="

test_detects_project_marker_commands() {
  local tmp expected actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # package.json must define the npm scripts to emit them (a missing script is no
  # longer run — see test_npm_feedback_skips_undefined_scripts).
  printf '%s\n' '{"scripts":{"test":"x","typecheck":"tsc --noEmit","lint":"eslint ."}}' > "$tmp/package.json"
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

# Regression: a package.json that omits a feedback script must NOT emit it — else
# `npm run <missing>` exits "Missing script" every round, a phantom FAIL that jams
# the harden convergence gate. Only the scripts that actually exist are run.
test_npm_feedback_skips_undefined_scripts() {
  local tmp expected actual
  command -v node >/dev/null 2>&1 || { echo "  SKIP: node absent (gate falls back to emit-all)"; return 0; }
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Has `lint` + `test`, but NO `typecheck` (mirrors a real biome/tsc-build repo).
  printf '%s\n' '{"scripts":{"test":"node --test","lint":"biome lint .","build":"tsc --build"}}' > "$tmp/package.json"

  expected=$(cat <<'EOF'
npm run test
npm run lint
EOF
)
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "$expected" "$actual" "only npm scripts defined in package.json should be emitted"
  echo "  PASS: npm feedback skips scripts not defined in package.json"
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

test_no_markers_yields_no_commands() {
  local tmp actual
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # An empty project (no marker files at all) detects nothing — the runner then
  # has no objective gate to run rather than erroring.
  actual="$(almanac_loop_feedback_commands "$tmp")"

  assert_eq "" "$actual" "a project with no marker files should yield no feedback commands"
  echo "  PASS: no markers yields no commands"
}

test_feedback_run_reports_per_loop_verdict() {
  local tmp verdicts rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Two detectable repo test scripts: one green, one red, so the runner must
  # emit a distinct pass/fail verdict per loop and a non-zero aggregate.
  mkdir -p "$tmp/tests"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/tests/test-skills.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$tmp/tests/test-structure.sh"
  chmod +x "$tmp/tests/test-skills.sh" "$tmp/tests/test-structure.sh"

  rc=0
  verdicts="$(almanac_loop_feedback_run "$tmp")" || rc=$?

  assert_contains "$verdicts" $'bash tests/test-skills.sh\tpass' "a green loop should report pass"
  assert_contains "$verdicts" $'bash tests/test-structure.sh\tfail' "a red loop should report fail"
  [ "$rc" -ne 0 ] || fail "the aggregate must be non-zero when any loop fails"
  echo "  PASS: feedback run reports per-loop verdict"
}

test_feedback_run_passes_when_all_green() {
  local tmp verdicts rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/tests"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/tests/test-skills.sh"
  chmod +x "$tmp/tests/test-skills.sh"

  rc=0
  verdicts="$(almanac_loop_feedback_run "$tmp")" || rc=$?

  assert_contains "$verdicts" $'bash tests/test-skills.sh\tpass' "the green loop should report pass"
  [ "$rc" -eq 0 ] || fail "the aggregate must be zero when every loop passes"
  echo "  PASS: feedback run passes when all loops green"
}

test_detects_project_marker_commands
test_npm_feedback_skips_undefined_scripts
test_dedupes_python_markers
test_detects_repo_test_scripts
test_no_markers_yields_no_commands
test_feedback_run_reports_per_loop_verdict
test_feedback_run_passes_when_all_green

echo ""
echo "All feedback detection + runner tests passed."
