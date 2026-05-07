#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <prd-name> <iterations>"
  echo "Example: $0 auth-system 10"
  echo ""
  echo "Available PRDs:"
  ls plans/*.md 2>/dev/null | grep -v prompt | grep -v brief | sed 's|plans/||;s|\.md||' | sed 's/^/  /'
  exit 1
fi

PRD_NAME="$1"
ITERATIONS="$2"
PROMPT="plans/prompt-${PRD_NAME}.md"

# Model override: set RALPH_MODEL env var (e.g. RALPH_MODEL=claude-opus-4-7).
# Unset = use Claude Code's default (currently Sonnet).
MODEL_ARG=()
if [ -n "${RALPH_MODEL:-}" ]; then
  MODEL_ARG=(--model "$RALPH_MODEL")
fi

if [ ! -f "$PROMPT" ]; then
  echo "Error: $PROMPT not found. Run /ralph-loop $PRD_NAME to set up first."
  exit 1
fi

stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

push_ralph_commits() {
  if git remote get-url origin >/dev/null 2>&1; then
    echo ""
    echo "======= PUSHING TO REMOTE ======="
    _ralph_push || echo "[warn] git push failed — push manually to share work."
  fi
}

# Push current branch, setting upstream if needed. Used both per-iteration
# (to trigger CI) and end-of-loop (safety net in case a per-iter push failed).
_ralph_push() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  if [ -z "$(git config "branch.${branch}.remote" 2>/dev/null)" ]; then
    git push -u origin "$branch" 2>&1
  else
    git push 2>&1
  fi
}

# Overseer-cadence push: pushes any unpushed local commits on the current
# branch so CI runs against the latest state. Returns 0 when a push happened,
# 1 when there was nothing to push or push failed. Caller uses the return
# value to decide whether to wait for CI.
push_if_unpushed() {
  git remote get-url origin >/dev/null 2>&1 || return 1
  local branch upstream ahead
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")
  if [ -z "$upstream" ]; then
    {
      echo ""
      echo "===== OVERSEER PUSH $(date -Iseconds) — setting upstream ====="
    } >> "$OVERSEE_LOG"
    if _ralph_push >> "$OVERSEE_LOG" 2>&1; then
      return 0
    fi
    echo "[overseer] initial push failed" >> "$OVERSEE_LOG"
    return 1
  fi
  ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
  [ "$ahead" -gt 0 ] || return 1
  {
    echo ""
    echo "===== OVERSEER PUSH $(date -Iseconds) — $ahead commit(s) ahead of $upstream ====="
  } >> "$OVERSEE_LOG"
  if _ralph_push >> "$OVERSEE_LOG" 2>&1; then
    return 0
  fi
  echo "[overseer] push failed" >> "$OVERSEE_LOG"
  return 1
}

# Block until the GitHub Actions run for $1 (head SHA) leaves in_progress/
# queued. Polls every RALPH_CI_POLL_INTERVAL seconds (default 30), times out
# after RALPH_CI_WAIT_TIMEOUT seconds (default 1800 = 30min). Exits early on
# .ralph-stop. No-ops gracefully if `gh` missing, no remote, no run yet
# materializes for the SHA within the timeout.
wait_for_ci() {
  local target_sha="$1"
  command -v gh >/dev/null 2>&1 || return 0
  git remote get-url origin >/dev/null 2>&1 || return 0
  [ -z "$target_sha" ] && return 0

  local branch poll_interval timeout elapsed run_json status
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  poll_interval="${RALPH_CI_POLL_INTERVAL:-30}"
  timeout="${RALPH_CI_WAIT_TIMEOUT:-1800}"
  elapsed=0

  {
    echo ""
    echo "===== CI WAIT $(date -Iseconds) sha=${target_sha:0:8} timeout=${timeout}s ====="
  } >> "$OVERSEE_LOG"

  while [ "$elapsed" -lt "$timeout" ]; do
    [ -f .ralph-stop ] && return 0
    run_json=$(gh run list --branch "$branch" --limit 5 \
      --json status,headSha,url 2>/dev/null) || return 0
    if [ -n "$run_json" ] && [ "$run_json" != "[]" ]; then
      status=$(echo "$run_json" | jq -r --arg sha "$target_sha" \
        '[.[] | select(.headSha == $sha)] | .[0].status // ""')
      case "$status" in
        "")
          : # run for our SHA hasn't appeared yet — keep polling
          ;;
        in_progress|queued|waiting|requested|pending)
          : # still running — keep polling
          ;;
        *)
          {
            echo "===== CI RESOLVED $(date -Iseconds) status=$status after ${elapsed}s ====="
          } >> "$OVERSEE_LOG"
          return 0
          ;;
      esac
    fi
    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  {
    echo "===== CI WAIT TIMEOUT $(date -Iseconds) (${timeout}s) — proceeding without resolution ====="
  } >> "$OVERSEE_LOG"
}

# CI monitor: checks the latest GitHub Actions run on the current branch via
# `gh`. Writes .ralph-ci-failed (consumed by next iteration) on failure;
# clears it when CI is green again. No-ops gracefully if `gh` is missing,
# the repo has no remote, or no run exists yet.
check_ci_status() {
  command -v gh >/dev/null 2>&1 || return 0
  git remote get-url origin >/dev/null 2>&1 || return 0

  local branch run_json status conclusion url name run_id
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  [ -z "$branch" ] && return 0

  run_json=$(gh run list --branch "$branch" --limit 1 \
    --json databaseId,status,conclusion,url,name 2>/dev/null) || return 0
  [ -z "$run_json" ] || [ "$run_json" = "[]" ] && return 0

  status=$(echo "$run_json" | jq -r '.[0].status // ""')
  conclusion=$(echo "$run_json" | jq -r '.[0].conclusion // ""')
  url=$(echo "$run_json" | jq -r '.[0].url // ""')
  name=$(echo "$run_json" | jq -r '.[0].name // ""')
  run_id=$(echo "$run_json" | jq -r '.[0].databaseId // ""')

  case "$status" in
    in_progress|queued|waiting|requested|pending)
      return 0
      ;;
  esac

  case "$conclusion" in
    success)
      if [ -f .ralph-ci-failed ]; then
        {
          echo ""
          echo "===== CI GREEN $(date -Iseconds) — clearing .ralph-ci-failed ====="
          echo "url=$url"
        } >> "$OVERSEE_LOG"
        rm -f .ralph-ci-failed
      fi
      ;;
    failure|cancelled|timed_out|action_required|startup_failure)
      cat > .ralph-ci-failed <<EOF
CI conclusion: $conclusion
Workflow: $name
Run URL: $url
Run ID: $run_id
Branch: $branch
Detected at: $(date -Iseconds)

Fetch failing logs with:
  gh run view $run_id --log-failed
EOF
      {
        echo ""
        echo "===== CI FAIL $(date -Iseconds) — wrote .ralph-ci-failed ====="
        echo "conclusion=$conclusion url=$url"
      } >> "$OVERSEE_LOG"
      ;;
  esac
}

# Build a prompt prefix injected before the iteration template. Two markers
# can be present and stack: .ralph-ci-failed (persistent — cleared by
# check_ci_status when CI is green) and .ralph-steer (one-shot — consumed
# and removed here).
build_prompt_prefix() {
  local emitted=0

  if [ -f .ralph-ci-failed ]; then
    cat <<'EOF'
# CI FAILURE — FIX BEFORE ANY NEW TASK WORK

The previous push broke CI. Do NOT pick a new PRD task this iteration.

1. Read `.ralph-ci-failed` in the working directory for the failing run URL, workflow name, and run ID.
2. Run `gh run view <run-id> --log-failed` to read the failure logs.
3. Identify the root cause and fix it. Follow the `ci-fix` skill if available.
4. Run all feedback loops locally to confirm the fix.
5. Commit with `RALPH(<name>): fix CI — <summary>` (still use the RALPH prefix so progress tracking stays consistent).
6. The push and CI re-check happen automatically after this iteration.

Skip the TASK SELECTION / EXPLORATION / EXECUTION steps below for this iteration only — fixing CI is the entire iteration.

---

EOF
    emitted=1
  fi

  if [ -f .ralph-steer ]; then
    echo "# OVERSEER STEER — read before picking a task"
    echo ""
    echo "The overseer reviewed recent agent reports and commits and emitted this directive for you. Treat it as authoritative steering — adjust your task selection or approach accordingly."
    echo ""
    cat .ralph-steer
    echo ""
    echo "---"
    echo ""
    rm -f .ralph-steer
    emitted=1
  fi

  return 0
}

# Overseer: periodic drift detection. Runs in a background subshell, polls every
# RALPH_OVERSEE_INTERVAL seconds (default 900 = 15min). On HIGH drift, writes
# .ralph-stop so the next iteration exits gracefully. Set RALPH_NO_OVERSEE=1 to
# disable.
OVERSEE_INTERVAL="${RALPH_OVERSEE_INTERVAL:-900}"
OVERSEE_LOG="plans/overseer-${PRD_NAME}.log"
REPORTS_LOG="plans/agent-reports-${PRD_NAME}.log"
OVERSEER_PID=""

run_overseer_once() {
  local recent_commits recent_reports
  recent_commits=$(git log --grep="RALPH(${PRD_NAME})" -n 10 --format="%h %ad %s%n%b---" --date=short 2>/dev/null || echo "No RALPH commits yet")
  # Tail the last ~8KB of agent reports — bounded so the overseer prompt
  # doesn't balloon. Reports are appended by iteration agents under headers
  # like `===== sha=<sha> ts=<iso> =====`.
  if [ -f "$REPORTS_LOG" ]; then
    recent_reports=$(tail -c 8192 "$REPORTS_LOG")
  else
    recent_reports="(no agent reports yet)"
  fi

  local overseer_prompt
  overseer_prompt="Read the PRD context at @${PROMPT}. You are an overseer watching an autonomous coding loop named ralph(${PRD_NAME}).

Recent RALPH commits (last 10):
${recent_commits}

Recent agent self-reports (concerns / errors / uncertainties they flagged after each iteration):
${recent_reports}

Detect drift. Drift includes (non-exhaustive):
- Repeated tasks or task ping-pong
- Off-PRD topics — work unrelated to the PRD
- ABORT loops — repeated aborts on the same blocker
- Vague 'no real progress' commits
- Scope creep beyond the PRD
- Test rot or growing failures
- Recurring concerns or errors in agent self-reports that indicate confusion, wrong assumptions, or a blocker the agents aren't solving on their own
- Anything else that suggests wasted effort

Decide whether the next iteration would benefit from a steering directive — concrete advice that redirects the agent (e.g. 'the assumption about X in the last 3 iterations is wrong, see file Y', 'stop adding tests for Z, the PRD scopes that out', 'try approach A instead of B'). Only emit a steer if you have specific, actionable advice grounded in the commits or reports — vague encouragement is not a steer.

Output exactly in this format, no preamble:
DRIFT_LEVEL: <low|medium|high>
REASON: <one paragraph>
STEER: <one paragraph of concrete steering for next iteration, OR the literal word 'none'>

Be conservative on DRIFT_LEVEL — only 'high' with clear evidence (the loop stops via .ralph-stop). Be conservative on STEER too — emit 'none' when agents are progressing fine."

  local result
  result=$(claude \
    --print \
    --permission-mode plan \
    "${MODEL_ARG[@]}" \
    "$overseer_prompt" 2>&1 || true)

  {
    echo ""
    echo "===== OVERSEE $(date -Iseconds) ====="
    echo "$result"
  } >> "$OVERSEE_LOG"

  if echo "$result" | grep -qiE '^[[:space:]]*DRIFT_LEVEL:[[:space:]]*high'; then
    {
      echo ""
      echo "======= OVERSEER: HIGH DRIFT DETECTED — writing .ralph-stop ======="
      echo "$result"
    } >&2
    touch .ralph-stop
  fi

  # Extract STEER directive — everything after `STEER:` until EOF, trimmed.
  # If it's empty or literally 'none' (case-insensitive), do nothing.
  local steer
  steer=$(echo "$result" | awk '
    /^[[:space:]]*STEER:[[:space:]]*/ { sub(/^[[:space:]]*STEER:[[:space:]]*/, ""); capture=1; print; next }
    capture { print }
  ' | sed -e 's/[[:space:]]*$//' -e '/^$/d')
  if [ -n "$steer" ] && ! echo "$steer" | grep -qiE '^none[[:space:]]*$'; then
    printf '%s\n' "$steer" > .ralph-steer
    {
      echo ""
      echo "===== STEER WRITTEN $(date -Iseconds) ====="
      echo "$steer"
    } >> "$OVERSEE_LOG"
  fi
}

start_overseer() {
  if [ "${RALPH_NO_OVERSEE:-}" = "1" ]; then
    echo "[overseer] disabled (RALPH_NO_OVERSEE=1)"
    return
  fi
  mkdir -p "$(dirname "$OVERSEE_LOG")"
  {
    echo ""
    echo "===== OVERSEER STARTED $(date -Iseconds) interval=${OVERSEE_INTERVAL}s ====="
  } >> "$OVERSEE_LOG"
  (
    while true; do
      sleep "$OVERSEE_INTERVAL"
      [ -f .ralph-stop ] && exit 0
      # Sequential tick: push -> wait for CI to resolve (only if we pushed) ->
      # record CI verdict (writes/clears .ralph-ci-failed) -> spawn drift agent.
      if push_if_unpushed; then
        wait_for_ci "$(git rev-parse HEAD)"
      fi
      check_ci_status
      run_overseer_once
    done
  ) &
  OVERSEER_PID=$!
  echo "[overseer] started (PID $OVERSEER_PID, interval ${OVERSEE_INTERVAL}s, log $OVERSEE_LOG)"
}

stop_overseer() {
  if [ -n "${OVERSEER_PID:-}" ]; then
    kill "$OVERSEER_PID" 2>/dev/null || true
    wait "$OVERSEER_PID" 2>/dev/null || true
  fi
}

cleanup_all() {
  stop_overseer
  [ -n "${tmpfile:-}" ] && rm -f "$tmpfile"
}
trap cleanup_all EXIT INT TERM

# Pick up any pre-existing CI failure (e.g. from a prior AFK run or a manual
# push) so iteration #1 can fix it before any new task work.
check_ci_status

start_overseer

for ((i=1; i<=$ITERATIONS; i++)); do
  if [ -f .ralph-stop ]; then
    echo ""
    echo "======= STOP SIGNAL DETECTED (.ralph-stop) ======="
    echo "Exiting after iteration $((i-1)) of $ITERATIONS."
    rm -f .ralph-stop
    push_ralph_commits
    exit 0
  fi

  tmpfile=$(mktemp)

  echo ""
  echo "======= ITERATION $i of $ITERATIONS ($PRD_NAME) ======="
  echo ""

  ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

  prompt_prefix=$(build_prompt_prefix)

  claude \
    --print \
    --output-format stream-json \
    --verbose \
    "${MODEL_ARG[@]}" \
    "${prompt_prefix}@$PROMPT Previous RALPH commits: $ralph_commits" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    echo "Ralph complete after $i iterations."
    push_ralph_commits
    exit 0
  fi

  if [[ "$result" == *"<promise>ABORT</promise>"* ]]; then
    echo ""
    echo "Ralph aborted at iteration $i. Check the last commit message for details."
    push_ralph_commits
    exit 1
  fi
done

echo ""
echo "Ralph finished $ITERATIONS iterations. Tasks may remain — check with: git log --grep='RALPH($PRD_NAME)' --oneline"
push_ralph_commits
