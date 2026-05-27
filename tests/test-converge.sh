#!/usr/bin/env bash
# test-converge.sh - Converge CLI skeleton behavior tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALMANAC="$ROOT/bin/almanac"

source "$ROOT/lib/converge-core.sh"

TMPDIRS=()
NEW_TMPDIR=""

cleanup() {
  local dir
  [ "${#TMPDIRS[@]}" -eq 0 ] && return 0
  for dir in "${TMPDIRS[@]}"; do
    chmod -R u+w "$dir" >/dev/null 2>&1 || true
    rm -rf "$dir"
  done
}
trap cleanup EXIT

fail() {
  echo "  FAIL: $1" >&2
  exit 1
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  case "$haystack" in
    *"$needle"*) fail "$message" ;;
  esac
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

new_tmpdir() {
  NEW_TMPDIR="$(mktemp -d)"
  TMPDIRS+=("$NEW_TMPDIR")
}

# Plan dirs now use timestamped names (YYYY-MM-DD-HHMMSS-<short-slug>) so
# multiple runs of the same goal can coexist. Tests that pre-date the
# refactor used hardcoded paths like "$tmp/docs/plans/converge/<slug>/...";
# this helper resolves a short slug to the LATEST matching plan dir so those
# assertions keep working without per-test path rewrites.
plan_dir_for_slug() {
  local tmp="$1" slug="$2" container="$tmp/docs/plans/converge" match
  [ -d "$container" ] || { printf '%s/%s' "$container" "$slug"; return 0; }
  match="$(ls -1 "$container" 2>/dev/null | grep -E -- "-${slug}\$" | sort | tail -1)"
  if [ -n "$match" ]; then
    printf '%s/%s' "$container" "$match"
  else
    # No timestamped match — return the legacy path so the caller's `[ -f ... ]`
    # produces a sensible "not found" failure rather than a glob expansion error.
    printf '%s/%s' "$container" "$slug"
  fi
}

run_converge() {
  local tmp="$1"
  shift

  ensure_fake_converge_worker "$tmp"

  (
    cd "$tmp"
    PATH="$tmp/.almanac/fakebin:$PATH" \
      CONVERGE_AGENT_PROVIDER="${CONVERGE_AGENT_PROVIDER:-codex}" \
      CONVERGE_AGENT_MODEL="${CONVERGE_AGENT_MODEL-}" \
      CONVERGE_AGENT_EFFORT="${CONVERGE_AGENT_EFFORT-}" \
      CONVERGE_OVERSEER_PROVIDER="${CONVERGE_OVERSEER_PROVIDER:-codex}" \
      CONVERGE_OVERSEER_MODEL="${CONVERGE_OVERSEER_MODEL-}" \
      CONVERGE_OVERSEER_EFFORT="${CONVERGE_OVERSEER_EFFORT-}" \
      CONVERGE_ROUND_BUDGET="${CONVERGE_ROUND_BUDGET-}" \
      CONVERGE_FAIL_ON_EXEC_ERROR="${CONVERGE_FAIL_ON_EXEC_ERROR-}" \
      FAKE_CONVERGE_WORKER_MODE="${FAKE_CONVERGE_WORKER_MODE:-exec-commit}" \
      FAKE_CONVERGE_OVERSEER_RESPONSE="${FAKE_CONVERGE_OVERSEER_RESPONSE-}" \
      FAKE_CONVERGE_ARGS_LOG="$tmp/.almanac/test-worker-args.log" \
      FAKE_CONVERGE_OVERSEER_ARGS_LOG="$tmp/.almanac/test-overseer-args.log" \
      FAKE_CONVERGE_OVERSEER_TICKS_LOG="$tmp/.almanac/test-overseer-ticks.log" \
      FAKE_CONVERGE_PROMPT_LOG_DIR="$tmp/.almanac/test-worker-prompts" \
      "$ALMANAC" converge "$@"
  )
}

ensure_fake_converge_worker() {
  local tmp="$1"
  local fakebin="$tmp/.almanac/fakebin"

  [ -x "$fakebin/codex" ] && return 0

  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args_log="${FAKE_CONVERGE_ARGS_LOG:?}"
prompt_log_dir="${FAKE_CONVERGE_PROMPT_LOG_DIR:?}"
mode="${FAKE_CONVERGE_WORKER_MODE:-exec-commit}"
result_file=""
prompt=""
sandbox=""

argv="$*"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
      ;;
    --sandbox)
      shift
      sandbox="${1:-}"
      ;;
    *)
      prompt="$1"
      ;;
  esac
  shift || true
done

mkdir -p "$prompt_log_dir"
tick="$(printf '%s\n' "$prompt" | awk -F= '$1 == "CONVERGE_TICK" { print $2; exit }')"
slug="$(printf '%s\n' "$prompt" | awk -F= '$1 == "CONVERGE_SLUG" { print $2; exit }')"
plan_rel="$(printf '%s\n' "$prompt" | awk -F= '$1 == "CONVERGE_PLAN_DIR" { print $2; exit }')"
report_rel="$(printf '%s\n' "$prompt" | awk -F= '$1 == "CONVERGE_REPORT_LOG" { print $2; exit }')"
tick="${tick:-0}"
slug="${slug:-unknown}"
plan_rel="${plan_rel:-docs/plans/converge/$slug}"
report_rel="${report_rel:-$plan_rel/agent-reports.log}"
role="worker"
if [ "$sandbox" = "read-only" ]; then
  role="overseer"
fi
printf '%s\n' "$prompt" > "$prompt_log_dir/$role-tick-$tick.md"

if [ "$role" = "overseer" ]; then
  [ -n "${FAKE_CONVERGE_OVERSEER_ARGS_LOG:-}" ] && printf '%s\n' "$argv" > "$FAKE_CONVERGE_OVERSEER_ARGS_LOG"
  [ -n "${FAKE_CONVERGE_OVERSEER_TICKS_LOG:-}" ] && printf '%s\n' "$tick" >> "$FAKE_CONVERGE_OVERSEER_TICKS_LOG"
  response="${FAKE_CONVERGE_OVERSEER_RESPONSE:-}"
  if [ -z "$response" ]; then
    response="VERDICT: CONTINUE
REASON: fake overseer says continue
STEER: none
GOAL_UPDATE: unchanged"
  fi
  [ -n "$result_file" ] && printf '%s\n' "$response" > "$result_file"
  printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"fake converge overseer"}}'
  exit 0
fi

printf '%s\n' "$argv" > "$args_log"

exec_cmd="$(
  printf '%s\n' "$prompt" | awk '
    $0 == "===== EXEC COMMAND =====" { capture = 1; next }
    $0 == "===== END EXEC COMMAND =====" { capture = 0 }
    capture { print }
  '
)"

rc=0
case "$mode" in
  fail-agent)
    rc=7
    ;;
  *)
    if [ -n "$exec_cmd" ]; then
      bash -c "$exec_cmd" || rc=$?
    fi
    ;;
esac

mkdir -p "$(dirname "$report_rel")"
{
  printf '===== tick=%s ts=%s =====\n' "$tick" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'summary:\n'
  printf -- '- fake worker exit=%s\n' "$rc"
  printf 'concerns:\n'
  printf -- '- (none)\n'
  printf 'next:\n'
  printf -- '- continue\n'
} >> "$report_rel"

if [ "$mode" != "leave-diff" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  status="$(git status --porcelain -- . ':!.almanac' ":!$plan_rel" 2>/dev/null || true)"
  if [ -n "$status" ]; then
    git add -A -- . ':!.almanac' ":!$plan_rel" >/dev/null 2>&1 || true
    if ! git diff --cached --quiet --exit-code >/dev/null 2>&1; then
      git commit -m "CONVERGE($slug): fake worker round $tick" --no-verify >/dev/null 2>&1 || true
    fi
  fi
fi

[ -n "$result_file" ] && printf '%s\n' "fake converge worker exit=$rc" > "$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"fake converge worker"}}'
exit "$rc"
EOF
  chmod +x "$fakebin/codex"
}

count_commits() {
  local repo="$1"
  git -C "$repo" rev-list --count HEAD 2>/dev/null || printf '%s\n' "0"
}

setup_git_repo() {
  local tmp="$1"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "test@example.com"
  git -C "$tmp" config user.name "Almanac Test"
  git -C "$tmp" config commit.gpgsign false
}

test_cli_requires_goal_and_action() {
  local tmp output rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  output="$(run_converge "$tmp" --exec "true" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing --goal should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing --goal should show usage hint"
  assert_contains "$output" "Missing required --goal" "missing --goal should name the missing arg"

  output="$(run_converge "$tmp" --goal "say hello" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing both --prompt and --exec should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing action should show usage hint"
  assert_contains "$output" "One of --prompt or --exec is required" \
    "missing action should name both alternatives"

  output="$(run_converge "$tmp" --goal "say hello" --prompt "/x" --exec "echo y" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "BOTH --prompt and --exec should exit non-zero"
  assert_contains "$output" "mutually exclusive" "both action flags should name the mutex"

  echo "  PASS: converge CLI requires --goal and exactly one of --prompt / --exec"
}

test_plan_dir_scaffold_and_exec_smoke() {
  local tmp marker plan reports
  new_tmpdir
  tmp="$NEW_TMPDIR"
  marker="$tmp/marker"

  run_converge "$tmp" --goal "Say Hello!" --exec "touch '$marker'" >/dev/null

  plan="$(plan_dir_for_slug "$tmp" "say-hello")"
  reports="$plan/agent-reports.log"

  [ -f "$plan/goal.md" ] || fail "goal.md should be scaffolded"
  [ -f "$reports" ] || fail "agent-reports.log should be scaffolded"
  [ -f "$plan/goal.history.log" ] || fail "goal.history.log should be scaffolded"
  [ -f "$marker" ] || fail "exec command should run through bash"
  assert_file_contains "$plan/goal.md" "Say Hello!" "goal.md should contain the goal text"
  [ ! -s "$plan/goal.history.log" ] || fail "goal.history.log should start empty"
  [ -f "$plan/prompt.md" ] || fail "prompt.md should be created on first round"
  assert_file_contains "$reports" "===== tick=1 ts=" "agent report should include tick 1 header"
  assert_file_contains "$reports" "summary:" "agent report should include summary section"
  assert_file_contains "$reports" "concerns:" "agent report should include concerns section"
  assert_file_contains "$reports" "next:" "agent report should include next section"
  assert_eq "1" "$(grep -c '^===== tick=1 ts=.* =====$' "$reports")" \
    "one structured report header should be appended for one round"

  echo "  PASS: converge scaffolds plan files and worker runs exec once"
}

# Prompt-mode E2E: --prompt sends the verbatim text to the agent each round
# (no worker template wrapper). The driver auto-commits any worktree changes
# with CONVERGE(<slug>): prefix and writes a minimal self-report tagged
# mode=prompt. This is the dominant slash-command convergence use case.
test_prompt_mode_invokes_agent_and_commits() {
  local tmp plan reports prompt_log fake_args
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  # Fake codex that writes a file (so we have a diff to auto-commit) and a
  # short result. The fake echoes its prompt to a log so we can assert the
  # agent saw the verbatim --prompt text, not a wrapped template.
  local fakebin="$tmp/.almanac/fakebin"
  mkdir -p "$fakebin"
  prompt_log="$tmp/.almanac/prompt-mode-prompts.log"
  fake_args="$tmp/.almanac/prompt-mode-args.log"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
prompt=""
result_file=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message) shift; result_file="\${1:-}" ;;
    --sandbox) shift ;;
    *) prompt="\$1" ;;
  esac
  shift || true
done
printf '%s\n' "\$prompt" > "$prompt_log"
printf '%s\n' "\$*" >> "$fake_args"
# Produce a diff in the working tree so the driver's auto-commit fires.
printf 'worker touch round\n' > "$tmp/worker-output.txt"
[ -n "\$result_file" ] && printf 'fake prompt-mode agent finished\n' > "\$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"fake"}}'
EOF
  chmod +x "$fakebin/codex"

  ( cd "$tmp" && \
      PATH="$fakebin:$PATH" \
      CONVERGE_AGENT_PROVIDER=codex \
      CONVERGE_OVERSEER_PROVIDER=codex \
      ALMANAC_HOME="$ROOT" \
      HOME="$tmp" \
      "$ALMANAC" converge \
        --goal "prompt-mode smoke" \
        --prompt "/almanac:codebase-improve" \
        --rounds 1 \
        --no-oversee \
  ) >/dev/null 2>&1 || fail "prompt-mode converge run should exit 0"

  plan="$(plan_dir_for_slug "$tmp" "prompt-mode-smoke")"
  reports="$plan/agent-reports.log"

  [ -f "$plan/goal.md" ] || fail "prompt-mode should scaffold plan dir"
  [ -f "$reports" ] || fail "prompt-mode should write agent-reports.log"
  assert_file_contains "$reports" "mode=prompt" "prompt-mode report header should tag mode=prompt"
  assert_file_contains "$reports" "===== tick=1 ts=" "prompt-mode report should have a tick header"
  assert_file_contains "$prompt_log" "/almanac:codebase-improve" \
    "agent should see the verbatim --prompt text"
  # The driver's fallback commit fires when the agent didn't commit itself
  # (this test's fake codex doesn't commit). The message is distinctive
  # ("driver-fallback") so a real run's git log shows clearly which commits
  # were AI-authored vs driver-fallback.
  local commit_msg
  commit_msg="$(git -C "$tmp" log -1 --format=%s 2>/dev/null || true)"
  case "$commit_msg" in
    "CONVERGE(prompt-mode-smoke): round 1 — driver-fallback"*) : ;;
    *) fail "expected driver-fallback auto-commit (CONVERGE(prompt-mode-smoke): round 1 — driver-fallback ...); got: $commit_msg" ;;
  esac

  echo "  PASS: prompt-mode invokes agent verbatim and driver auto-commits (fallback message)"
}

# The prompt-mode worker prepends commit instructions to the user's --prompt
# so the AGENT authors meaningful commit messages instead of the driver
# falling back to the generic "round N" message. Pre-fix the prompt-mode
# worker just wrote the user's prompt verbatim — slash commands like
# /almanac:codebase-improve don't know about CONVERGE conventions, so they
# never committed, and the driver fallback ("round 8" with no description)
# made git log opaque after several rounds. This test pins that the
# instructions reach the prompt.
test_prompt_mode_worker_instructs_agent_to_commit() {
  local tmp plan prompt_log
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  ensure_fake_converge_worker "$tmp"
  prompt_log="$tmp/.almanac/prompt-mode-prompt-capture.log"
  local fakebin="$tmp/.almanac/fakebin"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
prompt=""; result_file=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message) shift; result_file="\${1:-}" ;;
    --sandbox) shift ;;
    *) prompt="\$1" ;;
  esac
  shift || true
done
printf '%s\n' "\$prompt" > "$prompt_log"
[ -n "\$result_file" ] && printf 'fake\n' > "\$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"fake"}}'
EOF
  chmod +x "$fakebin/codex"

  ( cd "$tmp" && \
      PATH="$fakebin:$PATH" \
      CONVERGE_AGENT_PROVIDER=codex \
      CONVERGE_OVERSEER_PROVIDER=codex \
      ALMANAC_HOME="$ROOT" \
      HOME="$tmp" \
      "$ALMANAC" converge \
        --goal "Commit Instructions Test" \
        --prompt "do the work" \
        --rounds 1 \
        --no-oversee \
  ) >/dev/null 2>&1 || fail "prompt-mode converge with --prompt should run"

  # Verify the agent saw commit instructions PREPENDED to the user prompt
  [ -f "$prompt_log" ] || fail "prompt-mode worker should have invoked the agent"
  local agent_prompt
  agent_prompt="$(cat "$prompt_log")"

  # The ground-rules section must precede the user prompt
  case "$agent_prompt" in
    *"CONVERGE LOOP"*"do the work"*) : ;;
    *) fail "ground-rules block must appear BEFORE the user prompt (got: $agent_prompt)" ;;
  esac

  # The exact commit prefix the overseer's grep depends on must be named
  assert_contains "$agent_prompt" 'CONVERGE(commit-instructions-test):' \
    "ground rules must name the CONVERGE(<slug>): commit prefix"

  # The "what good looks like" examples that prevent generic messages
  assert_contains "$agent_prompt" "GOOD:" "ground rules must show good summary examples"
  assert_contains "$agent_prompt" "BAD:" "ground rules must show bad summary examples"
  assert_contains "$agent_prompt" "round" "ground rules must call out 'round N' as a BAD example"

  # The skip-list — what NOT to commit
  assert_contains "$agent_prompt" ".almanac/" "ground rules must list .almanac/ as do-not-commit"
  assert_contains "$agent_prompt" "docs/plans/converge/" \
    "ground rules must list the plan dir as do-not-commit"

  echo "  PASS: prompt-mode worker prepends commit instructions before user prompt"
}

# Regression: pre-existing dirty paths must NOT be swept into the CONVERGE
# auto-commit. Bug observed: `git add -A` greedily staged whatever was dirty in
# the worktree when the agent finished, including the developer's in-flight
# edits to unrelated files. The fix snapshots dirty paths before the agent
# runs and only stages paths the agent newly touched.
test_prompt_mode_auto_commit_skips_pre_existing_dirty() {
  local tmp plan reports
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  # Seed an unrelated tracked file in HEAD, then mark it dirty BEFORE the
  # converge run starts. This is the "developer was editing something else"
  # scenario.
  printf 'baseline\n' > "$tmp/unrelated.txt"
  git -C "$tmp" add unrelated.txt
  git -C "$tmp" -c user.email=t@t -c user.name=t commit -q -m "seed unrelated"
  printf 'developer in-flight edit\n' > "$tmp/unrelated.txt"

  # Fake codex that writes only to a SEPARATE file (agent-touched). Sandbox:
  # the agent's path must NOT overlap with unrelated.txt.
  local fakebin="$tmp/.almanac/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
result_file=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --output-last-message) shift; result_file="\${1:-}" ;;
    --sandbox) shift ;;
    *) : ;;
  esac
  shift || true
done
printf 'agent wrote this\n' > "$tmp/agent-output.txt"
[ -n "\$result_file" ] && printf 'fake agent finished\n' > "\$result_file"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"fake"}}'
EOF
  chmod +x "$fakebin/codex"

  ( cd "$tmp" && \
      PATH="$fakebin:$PATH" \
      CONVERGE_AGENT_PROVIDER=codex \
      CONVERGE_OVERSEER_PROVIDER=codex \
      ALMANAC_HOME="$ROOT" \
      HOME="$tmp" \
      "$ALMANAC" converge \
        --goal "dirty-isolation smoke" \
        --prompt "/almanac:codebase-improve" \
        --rounds 1 \
        --no-oversee \
  ) >/dev/null 2>&1 || fail "converge run with pre-existing dirty worktree should exit 0"

  # The auto-commit should ONLY contain the agent's file, not unrelated.txt.
  local files_in_commit
  files_in_commit="$(git -C "$tmp" show --name-only --format= HEAD)"
  if printf '%s\n' "$files_in_commit" | grep -Fxq 'unrelated.txt'; then
    fail "pre-existing dirty unrelated.txt must NOT be staged into the CONVERGE commit (got files: $files_in_commit)"
  fi
  if ! printf '%s\n' "$files_in_commit" | grep -Fxq 'agent-output.txt'; then
    fail "agent-output.txt should be in the CONVERGE commit (got files: $files_in_commit)"
  fi

  # unrelated.txt should STILL be dirty in the worktree (the developer's
  # in-flight edit is preserved, not lost).
  local porcelain
  porcelain="$(git -C "$tmp" status --porcelain unrelated.txt)"
  case "$porcelain" in
    " M unrelated.txt"|"M  unrelated.txt") : ;;
    *) fail "unrelated.txt must remain dirty after the round (got: '$porcelain')" ;;
  esac

  echo "  PASS: prompt-mode auto-commit isolates pre-existing dirty paths"
}

test_registry_records_converge_run_done() {
  local tmp row run_id status_file status_blob
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Registry Goal" --exec "true" >/dev/null

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  [ -n "$row" ] || fail "converge run should be indexed"
  assert_eq "converge" "$(printf '%s' "$row" | cut -f2)" "registry type should be converge"
  assert_eq "registry-goal" "$(printf '%s' "$row" | cut -f3)" "registry target should be the goal slug"
  assert_eq "done" "$(printf '%s' "$row" | cut -f7)" "clean run should be marked done"

  run_id="$(printf '%s' "$row" | cut -f1)"
  status_file="$tmp/.almanac/runs/$run_id/status.tsv"
  [ -f "$status_file" ] || fail "status.tsv should exist"
  status_blob="$(cat "$status_file")"
  assert_contains "$status_blob" $'type\tconverge' "status record should carry type"
  assert_contains "$status_blob" $'target\tregistry-goal' "status record should carry target slug"
  assert_contains "$status_blob" $'status\tdone' "status record should be done"
  assert_contains "$status_blob" $'rounds\t10' "--rounds default should be stored as 10"

  echo "  PASS: converge registers and marks run done"
}

test_run_aborts_cleanly_when_plan_dir_unwritable() {
  local tmp output rc row status
  new_tmpdir
  tmp="$NEW_TMPDIR"

  mkdir -p "$tmp/docs/plans/converge"
  chmod 500 "$tmp/docs/plans/converge"

  # Regression parity with harden commit 1467073: a mid-loop _die after run
  # registration must mark the run aborted without trap-time set -u crashes.
  output="$(run_converge "$tmp" --goal "Blocked Plan" --exec "true" 2>&1)" && rc=0 || rc=$?
  chmod 700 "$tmp/docs/plans/converge"

  [ "$rc" -ne 0 ] || fail "unwritable plan dir should exit non-zero"
  case "$output" in
    *"unbound variable"*) fail "EXIT trap must not crash on unbound variable (got: $output)" ;;
  esac
  assert_contains "$output" "Could not create converge plan dir" \
    "underlying _die message should reach the user"

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  [ -n "$row" ] || fail "run should register before scaffold _die"
  status="$(printf '%s' "$row" | cut -f7)"
  assert_eq "aborted" "$status" "mid-loop _die should mark run aborted"

  echo "  PASS: converge abort trap marks run aborted without set -u crash"
}

test_round_count_exactness() {
  local tmp counter plan reports
  new_tmpdir
  tmp="$NEW_TMPDIR"
  counter="$tmp/count"

  run_converge "$tmp" --goal "Round Count" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'" \
    --rounds 3 >/dev/null

  assert_eq "3" "$(cat "$counter")" "--rounds 3 should execute exactly three rounds"
  plan="$(plan_dir_for_slug "$tmp" "round-count")"
  reports="$plan/agent-reports.log"
  assert_eq "3" "$(grep -c '^===== tick=[0-9][0-9]* ts=.* =====$' "$reports")" \
    "--rounds 3 should append exactly three report headers"
  assert_file_contains "$reports" "===== tick=3 ts=" "reports should include tick 3"

  echo "  PASS: converge honors explicit round count"
}

test_default_round_budget_and_env_override() {
  local tmp counter
  new_tmpdir
  tmp="$NEW_TMPDIR"
  counter="$tmp/default-count"

  run_converge "$tmp" --goal "Default Budget" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'" \
    >/dev/null

  assert_eq "10" "$(cat "$counter")" "missing --rounds should default to 10 rounds"

  new_tmpdir
  tmp="$NEW_TMPDIR"
  counter="$tmp/env-count"

  CONVERGE_ROUND_BUDGET=2 run_converge "$tmp" --goal "Env Budget" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'" \
    >/dev/null

  assert_eq "2" "$(cat "$counter")" "CONVERGE_ROUND_BUDGET should override default rounds"

  echo "  PASS: converge uses default and env round budgets"
}

test_diff_rounds_commit_with_converge_prefix() {
  local tmp counter subjects
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"
  counter="$tmp/commit-count"

  run_converge "$tmp" --goal "Commit Goal" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'; printf 'round %s\n' \"\$n\" > '$tmp/change-\$n.txt'" \
    --rounds 2 >/dev/null

  assert_eq "2" "$(count_commits "$tmp")" "diff-producing rounds should create one commit per round"
  subjects="$(git -C "$tmp" log --reverse --format=%s)"
  assert_contains "$subjects" "CONVERGE(commit-goal): fake worker round 1" "first worker commit should use CONVERGE prefix"
  assert_contains "$subjects" "CONVERGE(commit-goal): fake worker round 2" "second worker commit should use CONVERGE prefix"

  echo "  PASS: converge worker commits diff-producing rounds"
}

test_zero_diff_rounds_skip_commit() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  run_converge "$tmp" --goal "No Diff" --exec "true" --rounds 2 >/dev/null

  assert_eq "0" "$(count_commits "$tmp")" "zero-diff rounds should not create commits"

  echo "  PASS: converge skips commits for zero-diff rounds"
}

test_worker_left_diff_warns_without_driver_commit() {
  local tmp output rc
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  output="$(FAKE_CONVERGE_WORKER_MODE=leave-diff run_converge "$tmp" \
    --goal "Worker Left Diff" --exec "printf x > '$tmp/change.txt'" --rounds 1 2>&1)" \
    && rc=0 || rc=$?

  assert_eq "0" "$rc" "worker leaving a diff should not abort converge loop"
  assert_contains "$output" "Converge round 1: worker left uncommitted changes; driver will not commit" \
    "driver should warn but not retry the worker commit"
  assert_eq "0" "$(count_commits "$tmp")" "driver should not create a fallback commit"

  echo "  PASS: converge warns without driver fallback commit"
}

test_registry_progress_updates_each_round() {
  local tmp row run_id status_file status_blob
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Progress Goal" --exec "true" --rounds 3 >/dev/null

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  [ -n "$row" ] || fail "converge run should be indexed"
  run_id="$(printf '%s' "$row" | cut -f1)"
  status_file="$tmp/.almanac/runs/$run_id/status.tsv"
  status_blob="$(cat "$status_file")"
  assert_contains "$status_blob" $'round\t3' "run progress should record latest round"
  assert_contains "$status_blob" $'summary\tgoal=progress-goal' "run progress should record goal summary"

  echo "  PASS: converge updates registry progress each round"
}

test_exec_failure_policy() {
  local tmp counter output rc reports status_file row run_id
  new_tmpdir
  tmp="$NEW_TMPDIR"
  counter="$tmp/fail-count"

  output="$(run_converge "$tmp" --goal "Exec Failure" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'; [ \"\$n\" -eq 1 ] && exit 7; exit 0" \
    --rounds 2 2>&1)" && rc=0 || rc=$?

  assert_eq "0" "$rc" "default exec failure mode should continue and exit 0"
  assert_eq "2" "$(cat "$counter")" "default exec failure mode should continue to next round"
  assert_contains "$output" "Converge round 1 exec exited 7; continuing" \
    "default worker failure should warn"
  reports="$(plan_dir_for_slug "$tmp" "exec-failure")/agent-reports.log"
  assert_file_contains "$reports" "===== tick=1 ts=" "failed exec should still append tick 1 report"
  assert_file_contains "$reports" "fake worker exit=7" "failed exec report should record non-zero exit"
  assert_file_contains "$reports" "===== tick=2 ts=" "default mode should append tick 2 report"
  assert_file_contains "$reports" "fake worker exit=0" "second exec report should record success"

  new_tmpdir
  tmp="$NEW_TMPDIR"
  counter="$tmp/fail-fast-count"

  output="$(CONVERGE_FAIL_ON_EXEC_ERROR=1 run_converge "$tmp" --goal "Fail Fast" \
    --exec "n=\$(cat '$counter' 2>/dev/null || printf 0); n=\$((n + 1)); printf '%s\n' \"\$n\" > '$counter'; exit 7" \
    --rounds 2 2>&1)" && rc=0 || rc=$?

  assert_eq "7" "$rc" "CONVERGE_FAIL_ON_EXEC_ERROR=1 should propagate exec exit code"
  assert_eq "1" "$(cat "$counter")" "fail-on-exec-error should stop after failed round"
  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  run_id="$(printf '%s' "$row" | cut -f1)"
  status_file="$tmp/.almanac/runs/$run_id/status.tsv"
  assert_file_contains "$status_file" $'status\tfailed' "fail-on-exec-error should mark run failed"

  echo "  PASS: converge handles exec failure policy"
}

test_worker_prompt_embeds_goal_exec_and_report_contract() {
  local tmp prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_converge_scaffold "$tmp" $'Fresh Goal\nsecond line'
  prompt="$(almanac_converge_worker_prompt "$tmp" $'Fresh Goal\nsecond line' "printf hi" 3)"

  assert_contains "$prompt" "===== GOAL.md =====" "worker prompt should mark goal block"
  assert_contains "$prompt" $'Fresh Goal\nsecond line' "worker prompt should embed goal.md verbatim"
  assert_contains "$prompt" "===== EXEC COMMAND =====" "worker prompt should mark exec block"
  assert_contains "$prompt" "printf hi" "worker prompt should include exec command"
  assert_contains "$prompt" "CONVERGE(" \
    "worker prompt should include CONVERGE commit prefix"
  assert_contains "$prompt" "<one-line summary>" \
    "worker prompt should instruct worker commit message format"
  assert_contains "$prompt" "===== tick=<N> ts=<ISO> =====" \
    "worker prompt should specify structured report header"
  assert_contains "$prompt" "summary:" "worker prompt should specify summary section"
  assert_contains "$prompt" "concerns:" "worker prompt should specify concerns section"
  assert_contains "$prompt" "next:" "worker prompt should specify next section"

  echo "  PASS: worker prompt embeds goal, exec, commit, report contract"
}

test_prompt_template_created_and_reread() {
  local tmp plan prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_converge_scaffold "$tmp" "Editable Template"
  plan="$(plan_dir_for_slug "$tmp" "editable-template")"

  almanac_converge_ensure_prompt_template "$tmp" "Editable Template"
  [ -f "$plan/prompt.md" ] || fail "prompt.md should be created when absent"
  printf '%s\n' "CUSTOM TEMPLATE EDIT" >> "$plan/prompt.md"

  prompt="$(almanac_converge_worker_prompt "$tmp" "Editable Template" "true" 2)"
  assert_contains "$prompt" "CUSTOM TEMPLATE EDIT" "worker prompt should re-read edited prompt.md"

  echo "  PASS: prompt template is created once and re-read"
}

test_worker_prompt_consumes_steer_once() {
  local tmp prompt plan_dir
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_converge_scaffold "$tmp" "Steered Goal"
  # Steer file lives in the run's plan dir now (per-run scope; see
  # lib/loops/converge.sh::almanac_loop_converge_signal_dir).
  plan_dir="$(plan_dir_for_slug "$tmp" "steered-goal")"
  printf '%s\n' "focus the parser" > "$plan_dir/.converge-steer"

  prompt="$(almanac_converge_worker_prompt "$tmp" "Steered Goal" "true" 1)"

  assert_contains "$prompt" "===== STEER =====" "worker prompt should include steer block"
  assert_contains "$prompt" "focus the parser" "worker prompt should embed steer directive"
  [ ! -f "$plan_dir/.converge-steer" ] || fail ".converge-steer should be consumed after prompt render"

  echo "  PASS: worker prompt consumes one-shot steer"
}

test_worker_agent_invoked_with_role_config() {
  local tmp args
  new_tmpdir
  tmp="$NEW_TMPDIR"

  CONVERGE_AGENT_PROVIDER=codex CONVERGE_AGENT_MODEL=gpt-test CONVERGE_AGENT_EFFORT=high \
    run_converge "$tmp" --goal "Role Config" --exec "true" --rounds 1 >/dev/null

  args="$(cat "$tmp/.almanac/test-worker-args.log")"
  # danger-full-access: converge runs are autonomous; the worker must be able
  # to run arbitrary shell (tests, git status, lint) the prompt asks for. For
  # codex this drops the sandbox; for claude the provider adapter maps it to
  # --permission-mode bypassPermissions. Pre-fix this was workspace-write, which
  # left claude workers dying on every un-allowlisted Bash call in --print mode.
  assert_contains "$args" "--sandbox danger-full-access" "worker agent should run with full access"
  assert_contains "$args" "--model gpt-test" "worker agent should receive CONVERGE_AGENT_MODEL"
  assert_contains "$args" "model_reasoning_effort=\"high\"" "worker agent should receive CONVERGE_AGENT_EFFORT"

  echo "  PASS: worker agent uses converge role config and danger-full-access sandbox"
}

test_structured_report_parser_accepts_worker_block() {
  local tmp reports
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Report Parser" --exec "true" --rounds 1 >/dev/null

  reports="$(plan_dir_for_slug "$tmp" "report-parser")/agent-reports.log"
  almanac_converge_report_log_has_structured_block "$reports" \
    || fail "structured worker report should be parseable"

  echo "  PASS: structured worker report is parseable"
}

test_overseer_prompt_embeds_goal_reports_commits_and_contract() {
  local tmp prompt reports plan
  new_tmpdir
  tmp="$NEW_TMPDIR"
  setup_git_repo "$tmp"

  almanac_converge_scaffold "$tmp" "Overseer Goal"
  plan="$(almanac_converge_plan_dir "$tmp" "$(almanac_loop_slug "Overseer Goal")")"
  reports="$plan/agent-reports.log"
  printf '%s\n' "old-report-sentinel" > "$reports"
  awk 'BEGIN { for (i = 0; i < 9000; i++) printf "x" }' >> "$reports"
  printf '\n%s\n' "recent-report-sentinel" >> "$reports"
  git -C "$tmp" commit --allow-empty -m "CONVERGE(overseer-goal): fake progress" --no-verify >/dev/null

  prompt="$(almanac_converge_overseer_prompt "$tmp" "Overseer Goal" 2)"

  assert_contains "$prompt" "CONVERGE_TICK=2" "overseer prompt should expose tick"
  assert_contains "$prompt" "Overseer Goal" "overseer prompt should embed goal.md verbatim"
  assert_contains "$prompt" "recent-report-sentinel" "overseer prompt should include recent reports tail"
  assert_not_contains "$prompt" "old-report-sentinel" "overseer prompt should bound report history"
  assert_contains "$prompt" "CONVERGE(overseer-goal): fake progress" "overseer prompt should include matching commit log"
  assert_contains "$prompt" "VERDICT: <CONVERGED|CONTINUE|STEER|STOP>" \
    "overseer prompt should specify verdict contract"
  assert_contains "$prompt" "GOAL_UPDATE: <complete new goal.md text, or the literal word 'unchanged'>" \
    "overseer prompt should specify goal update contract"
  # GOAL_UPDATE guidance: discourage editorial polish, demand a structural
  # reason for mutation. Without this, LLMs default to "unchanged" by path-
  # of-least-resistance — across 5 prior runs (20 ticks total) the field
  # never once moved, partly because the prompt didn't give criteria.
  assert_contains "$prompt" "structurally broken" \
    "overseer prompt should name when goal mutation is justified"
  assert_contains "$prompt" "editorial polish" \
    "overseer prompt should explicitly discourage editorial-only mutations"

  # Regression for the "skipped fields" bug: observed 10 consecutive ticks of
  # raw response = `GOAL_UPDATE: unchanged` only (zero VERDICT / REASON /
  # STEER lines). The LLM read the prompt's old "Be conservative. Malformed
  # output is treated as CONTINUE..." disclaimer as license to skip fields.
  # The fix removes that escape hatch + adds a literal example response so
  # the LLM has a concrete template to mimic.
  assert_contains "$prompt" "All four lines are REQUIRED" \
    "overseer prompt should demand all four lines (no skipping)"
  assert_contains "$prompt" "Example response" \
    "overseer prompt should anchor with a literal example response"
  # The example itself must contain a valid VERDICT-line + REASON-line +
  # STEER-line + GOAL_UPDATE-line so the LLM sees the full shape.
  assert_contains "$prompt" $'VERDICT: CONTINUE\nREASON:' \
    "example response should emit VERDICT then REASON"
  assert_contains "$prompt" $'STEER:'"$(printf ' ')""Implement" \
    "example response should emit a concrete STEER paragraph (not just 'none')"
  # The "Be conservative / malformed output → CONTINUE" disclaimer is gone —
  # it gave the LLM permission to skip fields.
  case "$prompt" in
    *"Be conservative. Malformed output"*)
      fail "old 'Be conservative. Malformed output...' disclaimer must not appear (gave LLM permission to skip fields)"
      ;;
  esac

  echo "  PASS: overseer prompt embeds goal, bounded reports, commits, contract, and anchoring example"
}

test_overseer_parse_verdicts_and_malformed_input() {
  local v

  for v in CONVERGED CONTINUE STEER STOP; do
    almanac_converge_overseer_parse "VERDICT: $v
REASON: because $v
STEER: focus $v
GOAL_UPDATE: unchanged"
    assert_eq "$v" "$ALMANAC_CONVERGE_VERDICT" "parser should preserve $v verdict"
    assert_eq "because $v" "$ALMANAC_CONVERGE_REASON" "parser should capture $v reason"
    assert_eq "focus $v" "$ALMANAC_CONVERGE_STEER" "parser should capture $v steer"
    assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "parser should capture unchanged goal update"
  done

  almanac_converge_overseer_parse "not a verdict"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "malformed parser input should continue"
  assert_eq "none" "$ALMANAC_CONVERGE_STEER" "malformed parser input should not steer"
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "malformed parser input should not update goal"

  # Partial input — only VERDICT present. Pre-leniency this reset to
  # CONTINUE on the theory "any missing field = throw away the verdict
  # too". New policy: VERDICT is honored when present (it's the LLM's
  # clearest signal); other fields fall to their conservative defaults.
  # The parse note records what was missing so the operator can see why.
  # See: test_overseer_parse_partial_output_keeps_verdict for the
  # full partial-output coverage.
  almanac_converge_overseer_parse "VERDICT: STOP"
  assert_eq "STOP" "$ALMANAC_CONVERGE_VERDICT" "partial parser input keeps VERDICT (new policy)"
  assert_eq "none" "$ALMANAC_CONVERGE_STEER" "partial parser input still defaults STEER to none"
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "partial parser input still defaults goal to unchanged"

  almanac_converge_overseer_parse "VERDICT: NOPE
REASON: bogus
STEER: do bad thing
GOAL_UPDATE: mutate"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "invalid verdict should continue"
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "invalid verdict should not mutate goal"

  echo "  PASS: overseer parser handles verdicts and malformed input conservatively"
}

# Regression: the LLM frequently emits multi-line REASON / STEER paragraphs.
# The original parser only captured the value text on the SAME line as KEY:,
# dropping continuation lines and producing empty REASON / STEER. Observed in
# the first --prompt converge run (overseer.log tick=1 showed empty REASON +
# 'none' STEER even though the LLM was asked for both). The state-machine
# parser must now capture multi-line values until the next KEY: marker.
test_overseer_parse_captures_multi_line_values() {
  # Multi-line REASON (two continuation lines, then STEER switches state)
  almanac_converge_overseer_parse "VERDICT: CONTINUE
REASON: Round 1 surveyed the codebase and found 8 friction points.
The agent stalled at AskUserQuestion and applied none.
Round 2 should pick the top finding and implement it.
STEER: Implement finding #1 first: split cmd/converge.sh into a launcher
front-end and a runner script, matching harden's shape.
GOAL_UPDATE: unchanged"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "multi-line parse keeps verdict"
  case "$ALMANAC_CONVERGE_REASON" in
    *"surveyed the codebase"*"applied none"*"pick the top finding"*) : ;;
    *) fail "multi-line REASON should capture all continuation lines (got: '$ALMANAC_CONVERGE_REASON')" ;;
  esac
  case "$ALMANAC_CONVERGE_STEER" in
    *"Implement finding #1"*"matching harden's shape"*) : ;;
    *) fail "multi-line STEER should capture all continuation lines (got: '$ALMANAC_CONVERGE_STEER')" ;;
  esac
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "GOAL_UPDATE unchanged on multi-line REASON"

  # Value-on-next-line shape: LLM puts the actual reason on the line AFTER
  # the KEY: marker. Parser must still capture it.
  almanac_converge_overseer_parse "VERDICT: CONTINUE
REASON:
Round 1 found 8 architectural friction points.
STEER:
focus on finding #1
GOAL_UPDATE:
unchanged"
  case "$ALMANAC_CONVERGE_REASON" in
    *"Round 1 found 8 architectural"*) : ;;
    *) fail "REASON value on line after KEY: must parse (got: '$ALMANAC_CONVERGE_REASON')" ;;
  esac
  case "$ALMANAC_CONVERGE_STEER" in
    *"focus on finding #1"*) : ;;
    *) fail "STEER value on line after KEY: must parse (got: '$ALMANAC_CONVERGE_STEER')" ;;
  esac
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "GOAL_UPDATE value on next line still recognised as unchanged"

  # Chatty VERDICT: token on its own line followed by extra preamble before
  # REASON. The first non-empty line of the VERDICT field is the token.
  almanac_converge_overseer_parse "VERDICT:
CONVERGED
Yes, this run has met its goal.
REASON: nothing major remains
STEER: none
GOAL_UPDATE: unchanged"
  assert_eq "CONVERGED" "$ALMANAC_CONVERGE_VERDICT" "VERDICT token on next line, with trailing chatter, still parses"

  # Empty REASON (KEY: with truly nothing after, no continuation) → empty
  # string is fine; conservative defaults still apply to the other fields.
  almanac_converge_overseer_parse "VERDICT: CONTINUE
REASON:
STEER: none
GOAL_UPDATE: unchanged"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "empty REASON does not malform the verdict"
  assert_eq "" "$ALMANAC_CONVERGE_REASON" "empty REASON remains empty (not a parse failure)"

  echo "  PASS: overseer parser captures multi-line REASON/STEER + value-on-next-line"
}

# Regression: real LLM responses often decorate KEY: markers with markdown
# bold (`**VERDICT:**`), markdown headings (`### VERDICT:`), or list-bullet
# styling (`- VERDICT:`). The pre-leniency parser failed every case because
# the case-match only accepted the literal `VERDICT:` prefix. Three converge
# runs in a row produced identical "VERDICT=CONTINUE, REASON='', STEER=none,
# GOAL_UPDATE=unchanged" overseer logs — the parser's silent fallback to
# defaults, NOT what the LLM actually said. The fix strips a tight whitelist
# of decorative prefixes before the case match.
test_overseer_parse_tolerates_markdown_decorated_keys() {
  # Markdown bold around the keys (the most common shape — `**VERDICT:** value`)
  almanac_converge_overseer_parse "**VERDICT:** CONTINUE
**REASON:** the run is healthy
**STEER:** focus on the test suite
**GOAL_UPDATE:** unchanged"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "**bold** keys: verdict captured"
  assert_eq "the run is healthy" "$ALMANAC_CONVERGE_REASON" "**bold** keys: reason captured"
  assert_eq "focus on the test suite" "$ALMANAC_CONVERGE_STEER" "**bold** keys: steer captured"

  # Markdown headings (rarer but seen)
  almanac_converge_overseer_parse "### VERDICT: CONVERGED
### REASON: done
### STEER: none
### GOAL_UPDATE: unchanged"
  assert_eq "CONVERGED" "$ALMANAC_CONVERGE_VERDICT" "### heading keys: verdict captured"
  assert_eq "done" "$ALMANAC_CONVERGE_REASON" "### heading keys: reason captured"

  # List-bullet styling
  almanac_converge_overseer_parse "- VERDICT: CONTINUE
- REASON: keep going
- STEER: none
- GOAL_UPDATE: unchanged"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "- bullet keys: verdict captured"
  assert_eq "keep going" "$ALMANAC_CONVERGE_REASON" "- bullet keys: reason captured"

  # Mix-and-match: some keys decorated, some plain — still captures all
  almanac_converge_overseer_parse "**VERDICT:** STOP
REASON: ship it
**STEER:** none
GOAL_UPDATE: unchanged"
  assert_eq "STOP" "$ALMANAC_CONVERGE_VERDICT" "mixed decoration: verdict captured"
  assert_eq "ship it" "$ALMANAC_CONVERGE_REASON" "mixed decoration: plain key still works"

  echo "  PASS: overseer parser tolerates **bold**, ### heading, and - bullet KEY decoration"
}

# Regression: partial-output policy. Pre-fix, if the LLM forgot to emit any
# one of REASON / STEER / GOAL_UPDATE, the parser bailed and reset ALL
# fields to defaults — including discarding the VERDICT the LLM DID emit
# clearly. Three converge runs all looked like "the LLM said CONTINUE,
# nothing else" when really the LLM might have emitted VERDICT + a prose
# paragraph (no `REASON:` marker). Now: bail only on missing VERDICT;
# default-fill the other fields and surface the gap in ALMANAC_CONVERGE_PARSE_NOTE
# so overseer.log records WHY the output was incomplete.
test_overseer_parse_partial_output_keeps_verdict() {
  # LLM emits VERDICT + free-form prose (no other KEY: markers). The
  # verdict should still be honored; the absent fields get defaults; the
  # parse note tells the operator what was missing.
  almanac_converge_overseer_parse "VERDICT: CONVERGED
The codebase has no major issues left. All findings from prior rounds
have been addressed. Ship it."
  assert_eq "CONVERGED" "$ALMANAC_CONVERGE_VERDICT" "partial: VERDICT honored even with no other keys"
  assert_eq "" "$ALMANAC_CONVERGE_REASON" "partial: REASON defaults to empty"
  assert_eq "none" "$ALMANAC_CONVERGE_STEER" "partial: STEER defaults to none"
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "partial: GOAL_UPDATE defaults to unchanged"
  case "$ALMANAC_CONVERGE_PARSE_NOTE" in
    *"missing fields"*"REASON"*"STEER"*"GOAL_UPDATE"*) : ;;
    *) fail "PARSE_NOTE should list missing fields (got: '$ALMANAC_CONVERGE_PARSE_NOTE')" ;;
  esac

  # Missing only one field — partial fill, parse note reflects only that one
  almanac_converge_overseer_parse "VERDICT: CONTINUE
REASON: keep going
GOAL_UPDATE: unchanged"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "one-missing: verdict captured"
  assert_eq "keep going" "$ALMANAC_CONVERGE_REASON" "one-missing: reason captured"
  case "$ALMANAC_CONVERGE_PARSE_NOTE" in
    *"missing fields"*"STEER"*) : ;;
    *) fail "PARSE_NOTE should call out STEER specifically (got: '$ALMANAC_CONVERGE_PARSE_NOTE')" ;;
  esac

  # Truly missing VERDICT — only case that still bails completely
  almanac_converge_overseer_parse "I don't see a problem here, the run looks done."
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "no-verdict: falls to CONTINUE default"
  case "$ALMANAC_CONVERGE_PARSE_NOTE" in
    *"no VERDICT marker found"*) : ;;
    *) fail "PARSE_NOTE should say no VERDICT marker (got: '$ALMANAC_CONVERGE_PARSE_NOTE')" ;;
  esac

  echo "  PASS: overseer parser keeps the verdict on partial output, surfaces gaps in PARSE_NOTE"
}

test_overseer_agent_invoked_read_only_with_role_config() {
  local tmp args
  new_tmpdir
  tmp="$NEW_TMPDIR"

  CONVERGE_OVERSEER_PROVIDER=codex CONVERGE_OVERSEER_MODEL=gpt-overseer CONVERGE_OVERSEER_EFFORT=medium \
    run_converge "$tmp" --goal "Overseer Role" --exec "true" --rounds 1 >/dev/null

  args="$(cat "$tmp/.almanac/test-overseer-args.log")"
  assert_contains "$args" "--sandbox read-only" "overseer agent should run read-only"
  assert_contains "$args" "--model gpt-overseer" "overseer agent should receive CONVERGE_OVERSEER_MODEL"
  assert_contains "$args" "model_reasoning_effort=\"medium\"" "overseer agent should receive CONVERGE_OVERSEER_EFFORT"

  echo "  PASS: overseer agent uses role config and read-only sandbox"
}

test_overseer_converged_stops_loop_and_writes_convergence() {
  local tmp reports row status_file convergence
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONVERGED
REASON: goal satisfied
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Converged Goal" --exec "true" --rounds 3 >/dev/null

  # CONVERGED writes the stop signal to the run's plan dir, NOT $root (the
  # signal_dir adapter scopes it per-run so unrelated runs sharing the
  # workspace aren't poisoned). See lib/loops/converge.sh.
  [ -f "$(plan_dir_for_slug "$tmp" "converged-goal")/.converge-stop" ] \
    || fail "CONVERGED should write .converge-stop to its plan dir"
  [ ! -f "$tmp/.converge-stop" ] \
    || fail "CONVERGED MUST NOT write .converge-stop to \$root (would poison sibling runs)"
  reports="$(plan_dir_for_slug "$tmp" "converged-goal")/agent-reports.log"
  assert_eq "1" "$(grep -c '^===== tick=[0-9][0-9]* ts=.* =====$' "$reports")" \
    "CONVERGED should stop after current round"
  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  status_file="$tmp/.almanac/runs/$(printf '%s' "$row" | cut -f1)/status.tsv"
  assert_file_contains "$status_file" $'status\tdone' "CONVERGED should mark registry done"

  convergence="$(plan_dir_for_slug "$tmp" "converged-goal")/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written on terminal exit"
  assert_file_contains "$convergence" "## Outcome" "convergence.md should include outcome section"
  assert_file_contains "$convergence" "CONVERGED" "convergence.md should label the outcome"
  assert_file_contains "$convergence" "## Last overseer verdict" "convergence.md should include the raw last verdict"
  assert_file_contains "$convergence" "## Tick count" "convergence.md should include tick count section"
  assert_file_contains "$convergence" "## Time elapsed" "convergence.md should include elapsed section"
  assert_file_contains "$convergence" "## Final goal" "convergence.md should include final goal section"
  assert_file_contains "$convergence" "## Termination reason" "convergence.md should include termination reason section"

  echo "  PASS: CONVERGED verdict stops loop, marks done, writes convergence.md"
}

# Regression for the misleading-format bug observed in run-the-prompt-…
# convergence.md: when the loop hit its 10-round budget without the overseer
# saying CONVERGED, the file wrote "Final verdict: CONTINUE" — which the next
# converge run's agent misread as "the system decided this is done; don't
# duplicate that work". Fix: the convergence.md now writes a distinct
# `## Outcome` field saying NON_CONVERGED explicitly, with a one-line summary
# noting the budget was exhausted. The raw last overseer verdict moves to a
# separate informational section.
test_convergence_md_labels_non_converged_when_budget_exhausted() {
  local tmp convergence
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ensure_fake_converge_worker "$tmp"

  # Drive 3 rounds where the overseer never says CONVERGED. The loop exits via
  # round budget; convergence.md must label that NON_CONVERGED, not echo back
  # the raw "CONTINUE" as if it were the outcome.
  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: keep going
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Budget Goal" --exec "true" --rounds 3 >/dev/null

  convergence="$(plan_dir_for_slug "$tmp" "budget-goal")/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written when budget hits"
  assert_file_contains "$convergence" "NON_CONVERGED" \
    "budget-exhausted runs must label the Outcome NON_CONVERGED"
  assert_file_contains "$convergence" "round budget exhausted" \
    "Outcome line should explain why the loop stopped"
  assert_file_contains "$convergence" "3/3" \
    "Tick count section should show consumed-of-budget"

  # The raw last overseer verdict still shows up — but in a SEPARATE section,
  # so an agent reading convergence.md can't confuse "Last overseer verdict:
  # CONTINUE" with "the system decided we're done".
  assert_file_contains "$convergence" "## Last overseer verdict" \
    "convergence.md must keep the raw last verdict (informational)"
  assert_file_contains "$convergence" "CONTINUE" \
    "Last overseer verdict should show what the overseer last said"

  echo "  PASS: convergence.md labels NON_CONVERGED on budget exhaustion (no CONTINUE-misread)"
}

# Same shape for the --no-oversee path: outcome must still be NON_CONVERGED on
# budget exhaustion (the loop ran out of attempts), with last-verdict "n/a"
# because no overseer ever ran. Regression for the case the labels-non-converged
# test doesn't exercise: the conditional branch that sets final_verdict=n/a.
test_convergence_md_labels_non_converged_when_no_oversee_budget_exhausted() {
  local tmp convergence
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Headless Goal" --exec "true" --rounds 2 --no-oversee >/dev/null

  convergence="$(plan_dir_for_slug "$tmp" "headless-goal")/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written when --no-oversee budget hits"
  assert_file_contains "$convergence" "NON_CONVERGED" \
    "--no-oversee budget-exhausted runs must label the Outcome NON_CONVERGED"
  assert_file_contains "$convergence" "overseer disabled" \
    "Termination reason should record that the overseer was disabled"
  assert_file_contains "$convergence" "n/a" \
    "Last overseer verdict should be n/a when --no-oversee was passed"

  echo "  PASS: convergence.md labels NON_CONVERGED on --no-oversee budget exhaustion"
}

# Outcome=FAILED on a hard exec failure under CONVERGE_FAIL_ON_EXEC_ERROR=1. The
# loop tears down mid-round, so the convergence.md must reflect that — not echo
# the last (possibly CONTINUE) overseer verdict as if it were the outcome.
test_convergence_md_labels_failed_on_hard_exec_failure() {
  local tmp convergence
  new_tmpdir
  tmp="$NEW_TMPDIR"

  CONVERGE_FAIL_ON_EXEC_ERROR=1 \
    run_converge "$tmp" --goal "Hard Fail Goal" --exec "exit 7" --rounds 3 >/dev/null 2>&1 || true

  convergence="$(plan_dir_for_slug "$tmp" "hard-fail-goal")/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written on hard exec failure"
  assert_file_contains "$convergence" "FAILED" \
    "hard exec failure must label the Outcome FAILED"
  assert_file_contains "$convergence" "exec exit=7" \
    "Termination reason should record the exec exit code"

  echo "  PASS: convergence.md labels FAILED on hard exec failure"
}

# Same shape for stop signal: outcome=STOPPED, with the raw STOP verdict kept
# in the informational section. Confirms the outcome / last-verdict split.
test_convergence_md_labels_stopped_on_overseer_stop() {
  local tmp convergence
  new_tmpdir
  tmp="$NEW_TMPDIR"
  ensure_fake_converge_worker "$tmp"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: STOP
REASON: ship it
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Stop Goal" --exec "true" --rounds 5 >/dev/null

  convergence="$(plan_dir_for_slug "$tmp" "stop-goal")/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written on STOP verdict"
  assert_file_contains "$convergence" "STOPPED" \
    "STOP verdict runs must label the Outcome STOPPED"
  assert_file_contains "$convergence" "## Last overseer verdict" \
    "Last overseer verdict section is present"

  echo "  PASS: convergence.md labels STOPPED on overseer STOP verdict"
}

test_overseer_stop_marks_aborted() {
  local tmp row status_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: STOP
REASON: operator-equivalent stop
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Stopped Goal" --exec "true" --rounds 3 >/dev/null

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  status_file="$tmp/.almanac/runs/$(printf '%s' "$row" | cut -f1)/status.tsv"
  assert_file_contains "$status_file" $'status\taborted' "STOP should mark registry aborted"

  echo "  PASS: STOP verdict marks run aborted"
}

# Regression: a previous converge run that ended with CONVERGED or STOP wrote
# .converge-stop to the repo root. Pre-fix the file was never cleaned up,
# so the NEXT `almanac converge` invocation found it at round-loop entry and
# immediately aborted with "stop signal present before round 1" in 0 seconds
# — zero rounds ever ran, no agent ever spawned. Observed when the user
# tried to launch a fresh converge moments after the previous one converged.
# Fix: clear .converge-stop AND .converge-steer at run start so a previous
# run's signals don't poison the new run.
test_run_clears_leftover_control_signals_at_start() {
  local tmp plan_dir stop_file steer_file row status_file iter_count
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # Two cross-contamination shapes the loop must defend against:
  #
  # 1. Legacy $root signals — a converge run on an older build wrote
  #    $root/.converge-stop. The current build watches plan_dir, but the
  #    leftover root file would still confuse the operator (seen in git
  #    status). Migration grace: clean it on run start.
  #
  # 2. Same-goal re-run — user runs converge with goal "X", overseer
  #    CONVERGED writes plan_dir/.converge-stop, run exits. User reruns
  #    converge with the same goal "X" expecting fresh work. Plan dir is
  #    the same (slug-derived), so the leftover stop file is still there.
  #    Cleared at run start so the same-goal re-run starts cleanly.
  #
  # The cross-RUN (different goal) contamination is structurally impossible
  # with the new plan-dir scoping — different goals get different plan dirs,
  # so the test focuses on (1) legacy migration and (2) same-goal re-run.

  # Pre-create a STALE plan dir simulating an old run that left signal files
  # behind. The new run scaffolds a FRESH timestamped dir (different from
  # this stale one) — so by construction the new run can't see the stale
  # signals. This test pins that structural guarantee.
  local stale_dir
  stale_dir="$tmp/docs/plans/converge/resume-goal"
  mkdir -p "$stale_dir"
  stop_file="$stale_dir/.converge-stop"
  steer_file="$stale_dir/.converge-steer"
  : > "$stop_file"
  printf 'stale directive from prior run\n' > "$steer_file"

  # Also plant a legacy $root signal — older builds wrote here; the loop
  # cleans it during migration.
  : > "$tmp/.converge-stop"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: alive
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Resume Goal" --exec "true" --rounds 2 >/dev/null

  # The NEW run scaffolded its own fresh timestamped dir; resolve it via the
  # helper (suffix-matches `-resume-goal` and picks the latest — the just-
  # created one wins because the stale dir doesn't match the timestamp
  # prefix pattern).
  local new_dir
  new_dir="$(plan_dir_for_slug "$tmp" "resume-goal")"
  [ "$new_dir" != "$stale_dir" ] || fail "new run should have scaffolded a fresh timestamped dir (got stale: $new_dir)"

  iter_count="$(grep -c '^===== tick=[0-9]' "$new_dir/agent-reports.log" 2>/dev/null || printf 0)"
  [ "$iter_count" -ge 1 ] || fail "new run must execute its rounds (got 0 ticks in $new_dir)"

  # The stale steer file in the OLD dir cannot reach the new run — different
  # dirs, different signal scopes.
  if [ -f "$new_dir/converge-codex-iteration-1.log" ]; then
    case "$(cat "$new_dir/converge-codex-iteration-1.log")" in
      *"stale directive from prior run"*)
        fail "stale .converge-steer from old dir must not bleed into the new run's round 1 prompt"
        ;;
    esac
  fi

  # Legacy $root signal should have been swept during migration cleanup
  [ ! -f "$tmp/.converge-stop" ] || fail "legacy \$root/.converge-stop should be cleaned on run start"

  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  status_file="$tmp/.almanac/runs/$(printf '%s' "$row" | cut -f1)/status.tsv"
  # With overseer always saying CONTINUE, the run hits the 2-round budget
  # and exits done (NOT aborted) — proving the leftover stop didn't poison it.
  assert_file_contains "$status_file" $'status\tdone' \
    "leftover .converge-stop must not cause the new run to register as aborted"

  echo "  PASS: run clears leftover plan-dir + legacy \$root control signals at start"
}

# Per-run signal scoping (the structural fix that closed the original bug):
# two converge runs with DIFFERENT goals get DIFFERENT plan dirs, so a
# CONVERGED verdict in one MUST NOT halt the other. Pre-fix the overseer
# wrote $root/.converge-stop on CONVERGED, which halted EVERY subsequent
# converge in the workspace until the operator manually rm'd the file.
test_converged_signal_scoped_to_plan_dir_not_root() {
  local tmp first_dir second_dir
  new_tmpdir
  tmp="$NEW_TMPDIR"

  # First run: overseer says CONVERGED. Should write the stop signal to its
  # OWN plan dir, not to $root.
  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONVERGED
REASON: first goal met
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "First Goal" --exec "true" --rounds 3 >/dev/null

  first_dir="$(plan_dir_for_slug "$tmp" "first-goal")"
  [ -f "$first_dir/.converge-stop" ] || fail "CONVERGED should write stop signal to its OWN plan dir"
  [ ! -f "$tmp/.converge-stop" ] || \
    fail "CONVERGED MUST NOT write stop signal to \$root (would poison unrelated runs)"

  # Second run with a different goal: should NOT be blocked by the first run's
  # stop signal. Its OWN plan dir is fresh; the first run's signal is in a
  # different plan dir, structurally invisible.
  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: keep going
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Second Goal" --exec "true" --rounds 2 >/dev/null

  second_dir="$(plan_dir_for_slug "$tmp" "second-goal")"
  local second_ticks
  second_ticks="$(grep -c '^===== tick=[0-9]' "$second_dir/agent-reports.log" 2>/dev/null || printf 0)"
  [ "$second_ticks" -ge 1 ] || \
    fail "second run with different goal must not be blocked by first run's CONVERGED signal (got 0 ticks)"

  echo "  PASS: CONVERGED stop signal stays in its own plan dir, doesn't poison sibling runs"
}

test_overseer_steer_writes_directive() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: STEER
REASON: needs focus
STEER: focus the parser
GOAL_UPDATE: new goal text for later slice" \
    run_converge "$tmp" --goal "Steer Goal" --exec "true" --rounds 1 >/dev/null

  # STEER directive lands in the run's plan dir (per-run scope) so a STEER
  # for one run can't bleed into another sharing the workspace.
  assert_file_contains "$(plan_dir_for_slug "$tmp" "steer-goal")/.converge-steer" "focus the parser" \
    "STEER verdict should write plan-dir scoped .converge-steer"
  [ ! -f "$tmp/.converge-steer" ] \
    || fail "STEER MUST NOT write to \$root (would poison sibling runs)"
  assert_file_contains "$(plan_dir_for_slug "$tmp" "steer-goal")/overseer.log" \
    "GOAL_UPDATE: new goal text for later slice" \
    "overseer log should record raw GOAL_UPDATE"
  assert_file_contains "$(plan_dir_for_slug "$tmp" "steer-goal")/goal.md" "new goal text for later slice" \
    "STEER verdict should still apply goal mutation"

  echo "  PASS: STEER verdict writes directive (plan-dir scoped) and applies GOAL_UPDATE"
}

test_overseer_continue_writes_no_signal() {
  local tmp plan_dir
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: keep going
STEER: noisy non-authoritative text
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Continue Goal" --exec "true" --rounds 1 >/dev/null

  # No signal files anywhere — neither at $root nor in the plan dir.
  plan_dir="$(plan_dir_for_slug "$tmp" "continue-goal")"
  [ ! -f "$plan_dir/.converge-steer" ] || fail "CONTINUE verdict should not write plan-dir .converge-steer"
  [ ! -f "$plan_dir/.converge-stop" ]  || fail "CONTINUE verdict should not write plan-dir .converge-stop"
  [ ! -f "$tmp/.converge-steer" ]      || fail "CONTINUE verdict should not write \$root .converge-steer"
  [ ! -f "$tmp/.converge-stop" ]       || fail "CONTINUE verdict should not write \$root .converge-stop"

  echo "  PASS: CONTINUE verdict writes no signal files"
}

test_no_oversee_skips_overseer_agent() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "No Overseer" --exec "true" --rounds 2 --no-oversee >/dev/null

  [ ! -f "$tmp/.almanac/test-overseer-args.log" ] || fail "--no-oversee should not invoke overseer agent"
  [ ! -f "$tmp/.converge-stop" ] || fail "--no-oversee should not write overseer stop signal"

  echo "  PASS: --no-oversee skips overseer work"
}

test_oversee_every_controls_cadence() {
  local tmp ticks
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Cadence Goal" --exec "true" --rounds 9 --oversee-every 3 >/dev/null

  ticks="$(tr '\n' ' ' < "$tmp/.almanac/test-overseer-ticks.log")"
  assert_eq "3 6 9 " "$ticks" "--oversee-every 3 should tick on rounds 3, 6, 9"

  echo "  PASS: --oversee-every controls overseer cadence"
}

test_goal_update_overwrites_goal_and_records_history() {
  local tmp plan history
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: narrow the scope
STEER: none
GOAL_UPDATE: New goal line 1
New goal line 2" \
    run_converge "$tmp" --goal "Mutable Goal" --exec "true" --rounds 1 >/dev/null

  plan="$(plan_dir_for_slug "$tmp" "mutable-goal")"
  history="$plan/goal.history.log"

  assert_eq $'New goal line 1\nNew goal line 2' "$(cat "$plan/goal.md")" \
    "GOAL_UPDATE should replace goal.md with complete new content"
  assert_file_contains "$history" "===== tick=1 ts=" "goal history should include tick header"
  assert_file_contains "$history" "overseer=codex" "goal history should include overseer provider"
  assert_file_contains "$history" "REASON: narrow the scope" "goal history should copy overseer reason"
  assert_file_contains "$history" "--- DIFF ---" "goal history should include diff marker"
  assert_file_contains "$history" "-Mutable Goal" "diff should include old goal"
  assert_file_contains "$history" "+New goal line 1" "diff should include new goal"
  assert_file_contains "$plan/overseer.log" "[tick=1] goal updated: New goal line 1 New goal line 2" \
    "overseer log should summarize goal mutation"

  echo "  PASS: GOAL_UPDATE overwrites goal.md and appends history diff"
}

test_goal_update_unchanged_leaves_goal_and_history_untouched() {
  local tmp plan
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: keep as is
STEER: none
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Stable Goal" --exec "true" --rounds 1 >/dev/null

  plan="$(plan_dir_for_slug "$tmp" "stable-goal")"
  assert_eq "Stable Goal" "$(cat "$plan/goal.md")" \
    "GOAL_UPDATE unchanged should leave goal.md untouched"
  [ ! -s "$plan/goal.history.log" ] || fail "GOAL_UPDATE unchanged should not append history"

  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: missing update stays conservative
STEER: none" \
    run_converge "$tmp" --goal "Missing Update Goal" --exec "true" --rounds 1 >/dev/null

  plan="$(plan_dir_for_slug "$tmp" "missing-update-goal")"
  assert_eq "Missing Update Goal" "$(cat "$plan/goal.md")" \
    "missing GOAL_UPDATE should leave goal.md untouched"
  [ ! -s "$plan/goal.history.log" ] || fail "missing GOAL_UPDATE should not append history"

  echo "  PASS: unchanged or missing GOAL_UPDATE is a no-op"
}

test_goal_history_accumulates_successive_updates() {
  local tmp plan history
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_converge_scaffold "$tmp" "Accumulating Goal"
  almanac_converge_apply_goal_update "$tmp" "Accumulating Goal" 1 "codex" "first reason" "first evolved goal"
  almanac_converge_apply_goal_update "$tmp" "Accumulating Goal" 2 "codex" "second reason" "second evolved goal"

  plan="$(plan_dir_for_slug "$tmp" "accumulating-goal")"
  history="$plan/goal.history.log"

  assert_eq "2" "$(grep -c '^===== tick=' "$history")" \
    "successive goal updates should append two history entries"
  assert_contains "$(awk '/^===== tick=1/{print; exit}' "$history")" "tick=1" \
    "first history entry should be first chronologically"
  assert_file_contains "$history" "REASON: first reason" "history should include first reason"
  assert_file_contains "$history" "REASON: second reason" "history should include second reason"
  assert_file_contains "$plan/goal.md" "second evolved goal" "last goal update should win"

  echo "  PASS: successive goal updates accumulate chronologically"
}

test_mutated_goal_reaches_next_worker_prompt() {
  local tmp prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: next worker needs narrower goal
STEER: none
GOAL_UPDATE: Mutated goal for round two" \
    run_converge "$tmp" --goal "Prompt Propagation" --exec "true" --rounds 2 >/dev/null

  prompt="$(cat "$tmp/.almanac/test-worker-prompts/worker-tick-2.md")"
  assert_contains "$prompt" "Mutated goal for round two" \
    "round N+1 worker prompt should read mutated goal.md"

  echo "  PASS: mutated goal propagates to next worker prompt"
}

test_goal_history_falls_back_when_diff_fails() {
  local tmp fakebin plan history
  new_tmpdir
  tmp="$NEW_TMPDIR"
  fakebin="$tmp/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/diff" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "$fakebin/diff"

  almanac_converge_scaffold "$tmp" "Fallback Goal"
  PATH="$fakebin:$PATH" almanac_converge_apply_goal_update "$tmp" "Fallback Goal" 1 "codex" "diff unavailable" "fallback evolved goal"

  plan="$(plan_dir_for_slug "$tmp" "fallback-goal")"
  history="$plan/goal.history.log"

  assert_not_contains "$(cat "$history")" "--- DIFF ---" "diff fallback should omit diff marker"
  assert_file_contains "$history" "--- AFTER ---" "diff fallback should include after marker"
  assert_file_contains "$history" "fallback evolved goal" "diff fallback should include full new goal"

  echo "  PASS: goal history falls back when diff command fails"
}

seed_converge_dashboard_fixture() {
  local tmp="$1"
  local slug="$2"
  local run_id="${3:-converge-dashboard}"
  local pid="${4:-$$}"
  local plan="$tmp/docs/plans/converge/$slug"

  mkdir -p "$plan"
  printf '%s\n' "Dashboard goal for $slug" > "$plan/goal.md"
  {
    printf '===== tick=1 ts=2026-05-26T10:00:00Z =====\n'
    printf 'summary:\n- first round\n'
    printf 'concerns:\n- (none)\n'
    printf 'next:\n- continue\n'
    printf '===== tick=2 ts=2026-05-26T10:01:00Z =====\n'
    printf 'summary:\n- second round\n'
    printf 'concerns:\n- watch this\n'
    printf 'next:\n- finish\n'
  } > "$plan/agent-reports.log"
  {
    printf '===== tick=1 ts=2026-05-26T10:00:30Z overseer=codex =====\n'
    printf 'REASON: narrowed once\n'
    printf -- '--- DIFF ---\n'
  } > "$plan/goal.history.log"
  {
    printf '===== tick=2 ts=2026-05-26T10:01:30Z overseer=codex exit=0 =====\n'
    printf 'VERDICT: CONTINUE\n'
    printf 'REASON: keep iterating\n'
    printf 'STEER: none\n'
    printf 'GOAL_UPDATE: unchanged\n'
  } > "$plan/overseer.log"

  almanac_loop_register_run "$tmp" "converge" "$slug" "$pid" "$run_id" "2026-05-26T10:00:00Z" >/dev/null
  almanac_loop_set_run_config "$tmp" "$run_id" "rounds=5" "oversee=every-1"
  almanac_loop_update_run_progress "$tmp" "$run_id" "2" "goal=$slug"
}

test_converge_adapter_exposes_stop_and_steer() {
  assert_eq ".converge-stop" "$(almanac_loop_signal_file converge stop)" \
    "converge stop file basename"
  assert_eq ".converge-steer" "$(almanac_loop_signal_file converge steer)" \
    "converge steer file basename"

  # signal_dir override: ralph and harden default to $root, but converge
  # scopes signals to the run's plan dir so CONVERGED in one run doesn't
  # halt sibling runs sharing the workspace.
  assert_eq "/r/docs/plans/converge/my-slug" \
    "$(almanac_loop_signal_dir converge "/r" "my-slug")" \
    "converge signal_dir routes to the run's plan dir"
  # Ralph and harden keep the default $root scoping — confirms the adapter
  # contract is opt-in deepening, not a forced regression for other loops.
  assert_eq "/r" "$(almanac_loop_signal_dir ralph "/r" "any-target")" \
    "ralph signal_dir defaults to \$root"
  assert_eq "/r" "$(almanac_loop_signal_dir harden "/r" "src/app.js")" \
    "harden signal_dir defaults to \$root"
  # Missing target falls back to $root rather than producing a malformed
  # path — defensive for the case where status.tsv is malformed.
  assert_eq "/r" "$(almanac_loop_signal_dir converge "/r" "")" \
    "converge signal_dir falls back to \$root when target is missing"

  echo "  PASS: converge adapter exposes stop and steer signals (plan-dir scoped)"
}

test_hub_lists_converge_run() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  seed_converge_dashboard_fixture "$tmp" "hub-goal" "converge-hub" "$$"

  out="$(cd "$tmp" && ALMANAC_NO_GUM=1 "$ALMANAC" hub </dev/null 2>&1)"
  assert_contains "$out" "Running" "hub should show running section"
  assert_contains "$out" "converge" "hub should list converge run type"
  assert_contains "$out" "hub-goal" "hub should list converge target slug"
  assert_contains "$out" "round 2" "hub should show converge live round"

  echo "  PASS: hub lists converge runs"
}

test_converge_status_summary_by_slug() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  seed_converge_dashboard_fixture "$tmp" "status-goal" "converge-status" "$$"

  out="$(cd "$tmp" && ALMANAC_NO_GUM=1 "$ALMANAC" converge status-goal </dev/null 2>&1)"
  assert_contains "$out" "converge status-goal" "status should name the converge slug"
  assert_contains "$out" "current round: 2/5" "status should show current round and budget"
  assert_contains "$out" "last verdict: CONTINUE" "status should show latest overseer verdict"
  assert_contains "$out" "reason: keep iterating" "status should show latest overseer reason"
  assert_contains "$out" "last report: ===== tick=2 ts=2026-05-26T10:01:00Z =====" \
    "status should show last self-report header"
  assert_contains "$out" "goal: Dashboard goal for status-goal" "status should show goal summary"
  assert_contains "$out" "goal mutations: 1" "status should count goal mutations"
  assert_contains "$out" "worker health: alive" "status should show live registry pid as alive"

  echo "  PASS: converge slug status prints dashboard summary"
}

test_converge_watch_plain_outputs_dashboard_fields() {
  local tmp out
  new_tmpdir
  tmp="$NEW_TMPDIR"

  seed_converge_dashboard_fixture "$tmp" "watch-goal" "converge-watch" "$$"

  out="$(cd "$tmp" && ALMANAC_NO_GUM=1 "$ALMANAC" converge watch-goal --watch </dev/null 2>&1)"
  assert_contains "$out" "current round: 2/5" "watch should show round budget"
  assert_contains "$out" "last verdict: CONTINUE" "watch should show last verdict"
  assert_contains "$out" "last report: ===== tick=2 ts=2026-05-26T10:01:00Z =====" \
    "watch should show latest report header"
  assert_contains "$out" "goal: Dashboard goal for watch-goal" "watch should show goal summary"
  assert_contains "$out" "goal mutations: 1" "watch should show mutation count"
  assert_contains "$out" "worker health: alive" "watch should show worker health"

  echo "  PASS: converge --watch renders plain dashboard fields"
}

test_converge_stop_signal_exits_running_loop() {
  local tmp reports row status_file
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Self Stop" \
    --exec "$ALMANAC converge self-stop --stop" \
    --rounds 3 --no-oversee >/dev/null

  # The round-start stop check routes through `almanac_loop_consume_signal`
  # (read+delete in one op) — same seam harden uses (see test-harden-cli.sh
  # ".harden-stop should be consumed"). Post-detection the file is gone; the
  # abort status below is the delivery proof. Plan-dir scoping of the WRITE
  # is covered by test_hub_stop_writes_converge_signal, which routes via the
  # same almanac_loop_run_control_file resolver as the CLI path.
  [ ! -f "$(plan_dir_for_slug "$tmp" "self-stop")/.converge-stop" ] || \
    fail ".converge-stop should be consumed by the round-start check"
  [ ! -f "$tmp/.converge-stop" ] \
    || fail "converge --stop MUST NOT write to \$root (would poison sibling runs)"
  reports="$(plan_dir_for_slug "$tmp" "self-stop")/agent-reports.log"
  assert_eq "1" "$(grep -c '^===== tick=[0-9][0-9]* ts=.* =====$' "$reports")" \
    "stop signal should halt before round 2"
  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  status_file="$tmp/.almanac/runs/$(printf '%s' "$row" | cut -f1)/status.tsv"
  assert_file_contains "$status_file" $'status\taborted' \
    "stop signal should mark running loop aborted at boundary"

  echo "  PASS: converge --stop signals and loop exits cleanly"
}

test_hub_stop_writes_converge_signal() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  seed_converge_dashboard_fixture "$tmp" "hub-stop" "converge-stop-cli" "2147483647"

  (cd "$tmp" && "$ALMANAC" hub --stop converge-stop-cli </dev/null >/dev/null 2>&1)
  # hub --stop routes through the signal_dir adapter — for converge it lands
  # in the run's plan dir, not at $root. This is the per-run scoping that
  # closed the cross-run-contamination bug (CONVERGED writing $root halted
  # unrelated sibling runs).
  [ -f "$(plan_dir_for_slug "$tmp" "hub-stop")/.converge-stop" ] \
    || fail "hub --stop should write converge stop signal to the plan dir"
  [ ! -f "$tmp/.converge-stop" ] \
    || fail "hub --stop MUST NOT write to \$root for converge runs"

  echo "  PASS: hub --stop writes converge signal to plan dir (per-run scope)"
}

test_cli_requires_goal_and_action
test_plan_dir_scaffold_and_exec_smoke
test_prompt_mode_invokes_agent_and_commits
test_prompt_mode_worker_instructs_agent_to_commit
test_prompt_mode_auto_commit_skips_pre_existing_dirty
test_registry_records_converge_run_done
test_run_aborts_cleanly_when_plan_dir_unwritable
test_converge_adapter_exposes_stop_and_steer
test_hub_lists_converge_run
test_converge_status_summary_by_slug
test_converge_watch_plain_outputs_dashboard_fields
test_converge_stop_signal_exits_running_loop
test_hub_stop_writes_converge_signal
test_worker_prompt_embeds_goal_exec_and_report_contract
test_prompt_template_created_and_reread
test_worker_prompt_consumes_steer_once
test_worker_agent_invoked_with_role_config
test_structured_report_parser_accepts_worker_block
test_overseer_prompt_embeds_goal_reports_commits_and_contract
test_overseer_parse_verdicts_and_malformed_input
test_overseer_parse_captures_multi_line_values
test_overseer_parse_tolerates_markdown_decorated_keys
test_overseer_parse_partial_output_keeps_verdict
test_overseer_agent_invoked_read_only_with_role_config
test_overseer_converged_stops_loop_and_writes_convergence
test_convergence_md_labels_non_converged_when_budget_exhausted
test_convergence_md_labels_non_converged_when_no_oversee_budget_exhausted
test_convergence_md_labels_failed_on_hard_exec_failure
test_convergence_md_labels_stopped_on_overseer_stop
test_overseer_stop_marks_aborted
test_run_clears_leftover_control_signals_at_start
test_converged_signal_scoped_to_plan_dir_not_root
test_overseer_steer_writes_directive
test_overseer_continue_writes_no_signal
test_no_oversee_skips_overseer_agent
test_oversee_every_controls_cadence
test_goal_update_overwrites_goal_and_records_history
test_goal_update_unchanged_leaves_goal_and_history_untouched
test_goal_history_accumulates_successive_updates
test_mutated_goal_reaches_next_worker_prompt
test_goal_history_falls_back_when_diff_fails
test_round_count_exactness
test_default_round_budget_and_env_override
test_diff_rounds_commit_with_converge_prefix
test_zero_diff_rounds_skip_commit
test_worker_left_diff_warns_without_driver_commit
test_registry_progress_updates_each_round
test_exec_failure_policy

echo "All converge tests passed."
