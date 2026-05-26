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
      CONVERGE_ROUND_BUDGET="${CONVERGE_ROUND_BUDGET-}" \
      CONVERGE_FAIL_ON_EXEC_ERROR="${CONVERGE_FAIL_ON_EXEC_ERROR-}" \
      FAKE_CONVERGE_WORKER_MODE="${FAKE_CONVERGE_WORKER_MODE:-exec-commit}" \
      FAKE_CONVERGE_ARGS_LOG="$tmp/.almanac/test-worker-args.log" \
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

printf '%s\n' "$*" > "$args_log"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      shift
      result_file="${1:-}"
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
printf '%s\n' "$prompt" > "$prompt_log_dir/tick-$tick.md"

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

test_cli_requires_goal_and_exec() {
  local tmp output rc
  new_tmpdir
  tmp="$NEW_TMPDIR"

  output="$(run_converge "$tmp" --exec "true" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing --goal should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing --goal should show usage hint"
  assert_contains "$output" "Missing required --goal" "missing --goal should name the missing arg"

  output="$(run_converge "$tmp" --goal "say hello" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || fail "missing --exec should exit non-zero"
  assert_contains "$output" "Usage: almanac converge" "missing --exec should show usage hint"
  assert_contains "$output" "Missing required --exec" "missing --exec should name the missing arg"

  echo "  PASS: converge CLI requires --goal and --exec"
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

test_cli_requires_goal_and_exec
test_plan_dir_scaffold_and_exec_smoke
test_registry_records_converge_run_done
test_run_aborts_cleanly_when_plan_dir_unwritable
test_worker_prompt_embeds_goal_exec_and_report_contract
test_prompt_template_created_and_reread
test_worker_prompt_consumes_steer_once
test_worker_agent_invoked_with_role_config
test_structured_report_parser_accepts_worker_block
test_round_count_exactness
test_default_round_budget_and_env_override
test_diff_rounds_commit_with_converge_prefix
test_zero_diff_rounds_skip_commit
test_worker_left_diff_warns_without_driver_commit
test_registry_progress_updates_each_round
test_exec_failure_policy

echo "All converge tests passed."
