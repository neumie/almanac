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

# Observer-cadence push: pushes any unpushed local commits on the current
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
      echo "===== OBSERVER PUSH $(date -Iseconds) — setting upstream ====="
    } >> "$OBSERVE_LOG"
    if _ralph_push >> "$OBSERVE_LOG" 2>&1; then
      return 0
    fi
    echo "[observer] initial push failed" >> "$OBSERVE_LOG"
    return 1
  fi
  ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
  [ "$ahead" -gt 0 ] || return 1
  {
    echo ""
    echo "===== OBSERVER PUSH $(date -Iseconds) — $ahead commit(s) ahead of $upstream ====="
  } >> "$OBSERVE_LOG"
  if _ralph_push >> "$OBSERVE_LOG" 2>&1; then
    return 0
  fi
  echo "[observer] push failed" >> "$OBSERVE_LOG"
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
  } >> "$OBSERVE_LOG"

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
          } >> "$OBSERVE_LOG"
          return 0
          ;;
      esac
    fi
    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  {
    echo "===== CI WAIT TIMEOUT $(date -Iseconds) (${timeout}s) — proceeding without resolution ====="
  } >> "$OBSERVE_LOG"
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
        } >> "$OBSERVE_LOG"
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
      } >> "$OBSERVE_LOG"
      ;;
  esac
}

# Build a prompt prefix injected before the iteration template. Currently
# only used to redirect the next agent to fix CI when .ralph-ci-failed exists.
build_prompt_prefix() {
  [ -f .ralph-ci-failed ] || return 0
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
}

# Observer: periodic drift detection. Runs in a background subshell, polls every
# RALPH_OBSERVE_INTERVAL seconds (default 900 = 15min). On HIGH drift, writes
# .ralph-stop so the next iteration exits gracefully. Set RALPH_NO_OBSERVE=1 to
# disable.
OBSERVE_INTERVAL="${RALPH_OBSERVE_INTERVAL:-900}"
OBSERVE_LOG="plans/observer-${PRD_NAME}.log"
OBSERVER_PID=""

run_observer_once() {
  local recent_commits
  recent_commits=$(git log --grep="RALPH(${PRD_NAME})" -n 10 --format="%h %ad %s%n%b---" --date=short 2>/dev/null || echo "No RALPH commits yet")

  local observer_prompt
  observer_prompt="Read the PRD context at @${PROMPT}. You are an observer watching an autonomous coding loop named ralph(${PRD_NAME}).

Recent RALPH commits (last 10):
${recent_commits}

Detect drift. Drift includes (non-exhaustive):
- Repeated tasks or task ping-pong
- Off-PRD topics — work unrelated to the PRD
- ABORT loops — repeated aborts on the same blocker
- Vague 'no real progress' commits
- Scope creep beyond the PRD
- Test rot or growing failures
- Anything else that suggests wasted effort

Output exactly two lines, no preamble:
DRIFT_LEVEL: <low|medium|high>
REASON: <one paragraph explaining the assessment>

Be conservative. Only output 'high' with clear evidence — when 'high', the loop will be stopped via .ralph-stop."

  local result
  result=$(claude \
    --print \
    --permission-mode plan \
    "${MODEL_ARG[@]}" \
    "$observer_prompt" 2>&1 || true)

  {
    echo ""
    echo "===== OBSERVE $(date -Iseconds) ====="
    echo "$result"
  } >> "$OBSERVE_LOG"

  if echo "$result" | grep -qiE '^[[:space:]]*DRIFT_LEVEL:[[:space:]]*high'; then
    {
      echo ""
      echo "======= OBSERVER: HIGH DRIFT DETECTED — writing .ralph-stop ======="
      echo "$result"
    } >&2
    touch .ralph-stop
  fi
}

start_observer() {
  if [ "${RALPH_NO_OBSERVE:-}" = "1" ]; then
    echo "[observer] disabled (RALPH_NO_OBSERVE=1)"
    return
  fi
  mkdir -p "$(dirname "$OBSERVE_LOG")"
  {
    echo ""
    echo "===== OBSERVER STARTED $(date -Iseconds) interval=${OBSERVE_INTERVAL}s ====="
  } >> "$OBSERVE_LOG"
  (
    while true; do
      sleep "$OBSERVE_INTERVAL"
      [ -f .ralph-stop ] && exit 0
      # Sequential tick: push -> wait for CI to resolve (only if we pushed) ->
      # record CI verdict (writes/clears .ralph-ci-failed) -> spawn drift agent.
      if push_if_unpushed; then
        wait_for_ci "$(git rev-parse HEAD)"
      fi
      check_ci_status
      run_observer_once
    done
  ) &
  OBSERVER_PID=$!
  echo "[observer] started (PID $OBSERVER_PID, interval ${OBSERVE_INTERVAL}s, log $OBSERVE_LOG)"
}

stop_observer() {
  if [ -n "${OBSERVER_PID:-}" ]; then
    kill "$OBSERVER_PID" 2>/dev/null || true
    wait "$OBSERVER_PID" 2>/dev/null || true
  fi
}

cleanup_all() {
  stop_observer
  [ -n "${tmpfile:-}" ] && rm -f "$tmpfile"
}
trap cleanup_all EXIT INT TERM

# Pick up any pre-existing CI failure (e.g. from a prior AFK run or a manual
# push) so iteration #1 can fix it before any new task work.
check_ci_status

start_observer

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
