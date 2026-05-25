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

# Emit one feedback command per line, detected from the project marker files
# present at $root. The order is fixed so the prompt/runner output is stable.
almanac_loop_feedback_commands() {
  local root="${1:-.}"

  if [ -f "$root/package.json" ]; then
    printf '%s\n' "npm run test"
    printf '%s\n' "npm run typecheck"
    printf '%s\n' "npm run lint"
  fi

  if [ -f "$root/Makefile" ]; then
    printf '%s\n' "make test"
    printf '%s\n' "make check"
  fi

  if [ -f "$root/Cargo.toml" ]; then
    printf '%s\n' "cargo test"
    printf '%s\n' "cargo check"
  fi

  if [ -f "$root/go.mod" ]; then
    printf '%s\n' "go test ./..."
    printf '%s\n' "go vet ./..."
  fi

  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ]; then
    printf '%s\n' "pytest"
    printf '%s\n' "mypy"
  fi

  if [ -f "$root/tests/test-skills.sh" ]; then
    printf '%s\n' "bash tests/test-skills.sh"
  fi

  if [ -f "$root/tests/test-structure.sh" ]; then
    printf '%s\n' "bash tests/test-structure.sh"
  fi
}

almanac_loop_feedback_command_description() {
  case "$1" in
    "npm run test") printf '%s\n' "run npm tests" ;;
    "npm run typecheck") printf '%s\n' "run TypeScript type checks" ;;
    "npm run lint") printf '%s\n' "run lint checks" ;;
    "make test") printf '%s\n' "run Makefile test target" ;;
    "make check") printf '%s\n' "run Makefile check target" ;;
    "cargo test") printf '%s\n' "run Rust tests" ;;
    "cargo check") printf '%s\n' "run Rust compiler checks" ;;
    "go test ./...") printf '%s\n' "run Go tests" ;;
    "go vet ./...") printf '%s\n' "run Go vet checks" ;;
    "pytest") printf '%s\n' "run Python tests" ;;
    "mypy") printf '%s\n' "run Python type checks" ;;
    "bash tests/test-skills.sh") printf '%s\n' "validate skill format/content" ;;
    "bash tests/test-structure.sh") printf '%s\n' "validate repo layout" ;;
    *) printf '%s\n' "run feedback loop" ;;
  esac
}

almanac_loop_feedback_markdown() {
  local root="${1:-.}"
  local command description found
  found=0

  while IFS= read -r command; do
    [ -n "$command" ] || continue
    description="$(almanac_loop_feedback_command_description "$command")"
    printf -- '- `%s` to %s\n' "$command" "$description"
    found=1
  done < <(almanac_loop_feedback_commands "$root")

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
