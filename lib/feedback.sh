#!/usr/bin/env bash
# feedback.sh - Project feedback-loop detection + runner
#
# The feedback loops are a project's objective gate: the test/typecheck/lint
# commands implied by its marker files (package.json, Cargo.toml, …). Detection
# maps marker files to commands (shared by Ralph's prompt and harden's fixer, so
# both run the same gate with no per-project config); the runner executes them
# and reports a pass/fail verdict per loop.
#
# Self-contained like lib/role.sh / lib/run.sh: uses only printf/tr/mkdir/eval
# and a subshell cd (no lib/core.sh dependency), so this file's interface is its
# own test surface (tests/test-feedback.sh). Callers source it directly.

# Single source of truth: marker → list of (command, description) rows. Each
# marker block emits TAB-separated rows, so adding a marker is a single block
# carrying both the command and its description — no parallel case-statement to
# keep in sync. Private — public surface is almanac_loop_feedback_commands +
# _markdown derived below.
_almanac_loop_feedback_rows() {
  local root="${1:-.}"

  if [ -f "$root/package.json" ]; then
    printf '%s\t%s\n' "npm run test"      "run npm tests"
    printf '%s\t%s\n' "npm run typecheck" "run TypeScript type checks"
    printf '%s\t%s\n' "npm run lint"      "run lint checks"
  fi

  if [ -f "$root/Makefile" ]; then
    printf '%s\t%s\n' "make test"  "run Makefile test target"
    printf '%s\t%s\n' "make check" "run Makefile check target"
  fi

  if [ -f "$root/Cargo.toml" ]; then
    printf '%s\t%s\n' "cargo test"  "run Rust tests"
    printf '%s\t%s\n' "cargo check" "run Rust compiler checks"
  fi

  if [ -f "$root/go.mod" ]; then
    printf '%s\t%s\n' "go test ./..." "run Go tests"
    printf '%s\t%s\n' "go vet ./..."  "run Go vet checks"
  fi

  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ]; then
    printf '%s\t%s\n' "pytest" "run Python tests"
    printf '%s\t%s\n' "mypy"   "run Python type checks"
  fi

  if [ -f "$root/tests/test-skills.sh" ]; then
    printf '%s\t%s\n' "bash tests/test-skills.sh" "validate skill format/content"
  fi

  if [ -f "$root/tests/test-structure.sh" ]; then
    printf '%s\t%s\n' "bash tests/test-structure.sh" "validate repo layout"
  fi
}

# Emit one feedback command per line, detected from the project marker files
# present at $root. The order is fixed so the prompt/runner output is stable.
almanac_loop_feedback_commands() {
  local cmd desc
  while IFS=$'\t' read -r cmd desc; do
    [ -n "$cmd" ] || continue
    printf '%s\n' "$cmd"
  done < <(_almanac_loop_feedback_rows "${1:-.}")
}

almanac_loop_feedback_markdown() {
  local root="${1:-.}"
  local cmd desc found=0

  while IFS=$'\t' read -r cmd desc; do
    [ -n "$cmd" ] || continue
    printf -- '- `%s` to %s\n' "$cmd" "$desc"
    found=1
  done < <(_almanac_loop_feedback_rows "$root")

  if [ "$found" -eq 0 ]; then
    printf '%s\n' "- (none detected)"
  fi
}

# Run every detected feedback loop for the project at $root and emit one TSV
# verdict row per loop: <command>\t<pass|fail>. Each command runs from $root
# (combined output captured to $log_dir/<slug>.log when a log dir is given,
# else discarded). Returns 0 only when every loop passed and non-zero when any
# failed, so a caller can gate on the aggregate while still reading the per-loop
# verdicts. This is the runner half of the shared feedback engine; detection is
# almanac_loop_feedback_commands, shared with Ralph, so both consumers run the
# same objective gate without per-project config.
almanac_loop_feedback_run() {
  local root="${1:-.}"
  local log_dir="${2:-}"
  local command verdict log_file slug
  local any_fail=0

  if [ -n "$log_dir" ]; then
    mkdir -p "$log_dir"
  fi

  while IFS= read -r command; do
    [ -n "$command" ] || continue

    if [ -n "$log_dir" ]; then
      slug="$(printf '%s' "$command" | tr -cs 'A-Za-z0-9' '-')"
      log_file="$log_dir/${slug}.log"
    else
      log_file="/dev/null"
    fi

    if ( cd "$root" && eval "$command" ) > "$log_file" 2>&1; then
      verdict="pass"
    else
      verdict="fail"
      any_fail=1
    fi

    printf '%s\t%s\n' "$command" "$verdict"
  done < <(almanac_loop_feedback_commands "$root")

  return "$any_fail"
}
