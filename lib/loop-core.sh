#!/usr/bin/env bash
# loop-core.sh - Shared loop orchestration helpers

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
