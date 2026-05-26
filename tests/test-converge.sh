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

  plan="$tmp/docs/plans/converge/say-hello"
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

  plan="$tmp/docs/plans/converge/prompt-mode-smoke"
  reports="$plan/agent-reports.log"

  [ -f "$plan/goal.md" ] || fail "prompt-mode should scaffold plan dir"
  [ -f "$reports" ] || fail "prompt-mode should write agent-reports.log"
  assert_file_contains "$reports" "mode=prompt" "prompt-mode report header should tag mode=prompt"
  assert_file_contains "$reports" "===== tick=1 ts=" "prompt-mode report should have a tick header"
  assert_file_contains "$prompt_log" "/almanac:codebase-improve" \
    "agent should see the verbatim --prompt text"
  # The driver auto-committed; assert the CONVERGE prefix and slug appear on HEAD.
  local commit_msg
  commit_msg="$(git -C "$tmp" log -1 --format=%s 2>/dev/null || true)"
  case "$commit_msg" in
    "CONVERGE(prompt-mode-smoke): round 1") : ;;
    *) fail "expected auto-commit with CONVERGE(prompt-mode-smoke): round 1 prefix; got: $commit_msg" ;;
  esac

  echo "  PASS: prompt-mode invokes agent verbatim and driver auto-commits"
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
  plan="$tmp/docs/plans/converge/round-count"
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
  reports="$tmp/docs/plans/converge/exec-failure/agent-reports.log"
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
  plan="$tmp/docs/plans/converge/editable-template"

  almanac_converge_ensure_prompt_template "$tmp" "Editable Template"
  [ -f "$plan/prompt.md" ] || fail "prompt.md should be created when absent"
  printf '%s\n' "CUSTOM TEMPLATE EDIT" >> "$plan/prompt.md"

  prompt="$(almanac_converge_worker_prompt "$tmp" "Editable Template" "true" 2)"
  assert_contains "$prompt" "CUSTOM TEMPLATE EDIT" "worker prompt should re-read edited prompt.md"

  echo "  PASS: prompt template is created once and re-read"
}

test_worker_prompt_consumes_steer_once() {
  local tmp prompt
  new_tmpdir
  tmp="$NEW_TMPDIR"

  almanac_converge_scaffold "$tmp" "Steered Goal"
  printf '%s\n' "focus the parser" > "$tmp/.converge-steer"

  prompt="$(almanac_converge_worker_prompt "$tmp" "Steered Goal" "true" 1)"

  assert_contains "$prompt" "===== STEER =====" "worker prompt should include steer block"
  assert_contains "$prompt" "focus the parser" "worker prompt should embed steer directive"
  [ ! -f "$tmp/.converge-steer" ] || fail ".converge-steer should be consumed after prompt render"

  echo "  PASS: worker prompt consumes one-shot steer"
}

test_worker_agent_invoked_with_role_config() {
  local tmp args
  new_tmpdir
  tmp="$NEW_TMPDIR"

  CONVERGE_AGENT_PROVIDER=codex CONVERGE_AGENT_MODEL=gpt-test CONVERGE_AGENT_EFFORT=high \
    run_converge "$tmp" --goal "Role Config" --exec "true" --rounds 1 >/dev/null

  args="$(cat "$tmp/.almanac/test-worker-args.log")"
  assert_contains "$args" "--sandbox workspace-write" "worker agent should run write-capable"
  assert_contains "$args" "--model gpt-test" "worker agent should receive CONVERGE_AGENT_MODEL"
  assert_contains "$args" "model_reasoning_effort=\"high\"" "worker agent should receive CONVERGE_AGENT_EFFORT"

  echo "  PASS: worker agent uses converge role config and workspace-write sandbox"
}

test_structured_report_parser_accepts_worker_block() {
  local tmp reports
  new_tmpdir
  tmp="$NEW_TMPDIR"

  run_converge "$tmp" --goal "Report Parser" --exec "true" --rounds 1 >/dev/null

  reports="$tmp/docs/plans/converge/report-parser/agent-reports.log"
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
  plan="$(almanac_converge_plan_dir "$tmp" "Overseer Goal")"
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
  assert_contains "$prompt" "GOAL_UPDATE: <new goal.md content, or 'unchanged'>" \
    "overseer prompt should specify goal update contract"

  echo "  PASS: overseer prompt embeds goal, bounded reports, commits, and contract"
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

  almanac_converge_overseer_parse "VERDICT: STOP"
  assert_eq "CONTINUE" "$ALMANAC_CONVERGE_VERDICT" "partial parser input should continue"
  assert_eq "none" "$ALMANAC_CONVERGE_STEER" "partial parser input should not steer"
  assert_eq "unchanged" "$ALMANAC_CONVERGE_GOAL_UPDATE" "partial parser input should not update goal"

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

  [ -f "$tmp/.converge-stop" ] || fail "CONVERGED should write .converge-stop"
  reports="$tmp/docs/plans/converge/converged-goal/agent-reports.log"
  assert_eq "1" "$(grep -c '^===== tick=[0-9][0-9]* ts=.* =====$' "$reports")" \
    "CONVERGED should stop after current round"
  row="$(awk -F'\t' 'NR > 1 && $2 == "converge" { print; exit }' "$tmp/.almanac/runs/index.tsv")"
  status_file="$tmp/.almanac/runs/$(printf '%s' "$row" | cut -f1)/status.tsv"
  assert_file_contains "$status_file" $'status\tdone' "CONVERGED should mark registry done"

  convergence="$tmp/docs/plans/converge/converged-goal/convergence.md"
  [ -f "$convergence" ] || fail "convergence.md should be written on terminal exit"
  assert_file_contains "$convergence" "## Final verdict" "convergence.md should include final verdict section"
  assert_file_contains "$convergence" "CONVERGED" "convergence.md should include verdict value"
  assert_file_contains "$convergence" "## Tick count" "convergence.md should include tick count section"
  assert_file_contains "$convergence" "## Time elapsed" "convergence.md should include elapsed section"
  assert_file_contains "$convergence" "## Final goal" "convergence.md should include final goal section"
  assert_file_contains "$convergence" "## Final reason" "convergence.md should include final reason section"

  echo "  PASS: CONVERGED verdict stops loop, marks done, writes convergence.md"
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

test_overseer_steer_writes_directive() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: STEER
REASON: needs focus
STEER: focus the parser
GOAL_UPDATE: new goal text for later slice" \
    run_converge "$tmp" --goal "Steer Goal" --exec "true" --rounds 1 >/dev/null

  assert_file_contains "$tmp/.converge-steer" "focus the parser" \
    "STEER verdict should write .converge-steer"
  assert_file_contains "$tmp/docs/plans/converge/steer-goal/overseer.log" \
    "GOAL_UPDATE: new goal text for later slice" \
    "overseer log should record raw GOAL_UPDATE"
  assert_file_contains "$tmp/docs/plans/converge/steer-goal/goal.md" "new goal text for later slice" \
    "STEER verdict should still apply goal mutation"

  echo "  PASS: STEER verdict writes directive and applies GOAL_UPDATE"
}

test_overseer_continue_writes_no_signal() {
  local tmp
  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: keep going
STEER: noisy non-authoritative text
GOAL_UPDATE: unchanged" \
    run_converge "$tmp" --goal "Continue Goal" --exec "true" --rounds 1 >/dev/null

  [ ! -f "$tmp/.converge-steer" ] || fail "CONTINUE verdict should not write .converge-steer"
  [ ! -f "$tmp/.converge-stop" ] || fail "CONTINUE verdict should not write .converge-stop"

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

  plan="$tmp/docs/plans/converge/mutable-goal"
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

  plan="$tmp/docs/plans/converge/stable-goal"
  assert_eq "Stable Goal" "$(cat "$plan/goal.md")" \
    "GOAL_UPDATE unchanged should leave goal.md untouched"
  [ ! -s "$plan/goal.history.log" ] || fail "GOAL_UPDATE unchanged should not append history"

  new_tmpdir
  tmp="$NEW_TMPDIR"

  FAKE_CONVERGE_OVERSEER_RESPONSE="VERDICT: CONTINUE
REASON: missing update stays conservative
STEER: none" \
    run_converge "$tmp" --goal "Missing Update Goal" --exec "true" --rounds 1 >/dev/null

  plan="$tmp/docs/plans/converge/missing-update-goal"
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

  plan="$tmp/docs/plans/converge/accumulating-goal"
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

  plan="$tmp/docs/plans/converge/fallback-goal"
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
  assert_eq ".converge-stop" "$(almanac_loop_run_signal_file converge stop)" \
    "converge stop file basename"
  assert_eq ".converge-steer" "$(almanac_loop_run_signal_file converge steer)" \
    "converge steer file basename"

  echo "  PASS: converge adapter exposes stop and steer signals"
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

  [ -f "$tmp/.converge-stop" ] || fail "converge --stop should write .converge-stop"
  [ -f "$tmp/docs/plans/converge/self-stop/.converge-stop" ] || \
    fail "converge --stop should also record stop signal in the plan dir"
  reports="$tmp/docs/plans/converge/self-stop/agent-reports.log"
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
  [ -f "$tmp/.converge-stop" ] || fail "hub --stop should write converge stop signal"

  echo "  PASS: hub --stop writes converge signal"
}

test_cli_requires_goal_and_action
test_plan_dir_scaffold_and_exec_smoke
test_prompt_mode_invokes_agent_and_commits
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
test_overseer_agent_invoked_read_only_with_role_config
test_overseer_converged_stops_loop_and_writes_convergence
test_overseer_stop_marks_aborted
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
