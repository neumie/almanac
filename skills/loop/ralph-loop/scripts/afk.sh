#!/bin/bash
set -e

# --- snapshot-exec guard ---------------------------------------------------
# Run from an immutable copy so a loop refactoring this runner cannot corrupt a
# live run mid-iteration (bash re-reads the main script by offset). Re-exec once
# — only when executed directly, never when sourced — from a temp copy; siblings
# and libs still load from the real dir via RALPH_REAL_DIR. The snapshot is
# removed by the EXIT trap (RALPH_SNAP_FILE).
if [ -z "${RALPH_SNAPSHOT:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  __real="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  __snap="$(mktemp "${TMPDIR:-/tmp}/almanac-runner.XXXXXX")"
  cp "${BASH_SOURCE[0]}" "$__snap"
  RALPH_SNAPSHOT=1 RALPH_REAL_DIR="$__real" RALPH_SNAP_FILE="$__snap" exec bash "$__snap" "$@"
fi

SCRIPT_DIR="${RALPH_REAL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
# ALMANAC_HOME bootstrap — same standardized snippet as the other entry points
# (mirrors almanac_resolve_home in lib/core.sh), resolved off SCRIPT_DIR rather
# than ${BASH_SOURCE[0]} because the snapshot-exec guard above runs us from an
# immutable temp copy; RALPH_REAL_DIR is the real scripts dir.
ALMANAC_HOME="${ALMANAC_HOME:-$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)}"
source "$SCRIPT_DIR/ralph-git.sh"
source "$SCRIPT_DIR/ralph-run-registry.sh"

# Provider seam (almanac_provider_*) — sourced directly so this runner's use of
# the seam (default-selection / availability / display) is an explicit
# dependency, not borrowed transitively.
if ! declare -F almanac_provider_default >/dev/null 2>&1; then
  source "$ALMANAC_HOME/lib/agent.sh"
fi

# Role config seam (almanac_loop_role_field) — sourced directly so this runner's
# per-role provider/model/effort resolution is an explicit dependency, not
# borrowed transitively.
if ! declare -F almanac_loop_role_field >/dev/null 2>&1; then
  source "$ALMANAC_HOME/lib/role.sh"
fi

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <prd-name> <iterations>"
  echo "Example: $0 auth-system 10"
  echo ""
  echo "Available PRDs:"
  for d in docs/plans/*/; do
    [ -f "$d/prd.md" ] && basename "$d"
  done 2>/dev/null | sed 's/^/  /'
  exit 1
fi

PRD_NAME="$1"
ITERATIONS="$2"
PROMPT="docs/plans/${PRD_NAME}/prompt.md"

# Iteration-agent role config resolves through the shared engine helper
# (almanac_loop_role_field): RALPH_AGENT_<FIELD> -> RALPH_<FIELD> -> default, the
# same precedence harden's roles use (#66 crit 3 — ralph uses the shared role
# config). RALPH_PROVIDER/RALPH_MODEL/RALPH_EFFORT still work (the fallback); the
# new RALPH_AGENT_* keys now override per-role. An explicit provider config wins;
# absent it, ralph's CLI auto-detection (CODEX_THREAD_ID, then installed CLI)
# stays — that runtime detection is ralph-specific, not a role-config concern.
detect_provider() {
  local configured default
  configured="$(almanac_loop_role_field ralph agent "" provider "")"
  if [ -n "$configured" ]; then
    echo "$configured"
  else
    default="$(almanac_provider_default)"
    echo "${default:-none}"
  fi
}

PROVIDER="$(detect_provider | tr '[:upper:]' '[:lower:]')"

# Model/effort overrides resolve through the same shared role-config helper.
# Unset = provider default. Every provider call — the iteration agent AND the
# overseer's read-only judge call — now routes through the shared agent_run seam
# (which takes these scalars directly), so afk no longer builds MODEL_ARG/
# EFFORT_ARG arrays; that arg-shaping lives in the seam (#66 crit 6).
AGENT_MODEL="$(almanac_loop_role_field ralph agent "" model "")"
AGENT_EFFORT="$(almanac_loop_role_field ralph agent "" effort "")"

if [ ! -f "$PROMPT" ]; then
  echo "Error: $PROMPT not found. Run /ralph-loop $PRD_NAME to set up first."
  exit 1
fi

# Availability + display route through the provider seam (no provider-name
# branching). The remaining case sets only the banner's cosmetic default-text.
if [ "$PROVIDER" = "none" ] || ! almanac_provider_known "$PROVIDER"; then
  echo "Error: no supported agent found. Install Claude Code or Codex, or set RALPH_PROVIDER."
  exit 1
fi
if ! almanac_provider_available "$PROVIDER"; then
  echo "Error: provider '$PROVIDER' selected but its CLI is not on PATH."
  exit 1
fi
PROVIDER_DISPLAY="$(almanac_provider_display "$PROVIDER")"
EFFORT_DISPLAY="${AGENT_EFFORT:-provider default}"
case "$PROVIDER" in
  claude)
    MODEL_DISPLAY="${AGENT_MODEL:-Claude Code default (resolved per session)}"
    ;;
  codex)
    MODEL_DISPLAY="${AGENT_MODEL:-Codex default}"
    ;;
esac

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
  ralph_push_current_branch
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
OVERSEE_LOG="docs/plans/${PRD_NAME}/overseer.log"
REPORTS_LOG="docs/plans/${PRD_NAME}/agent-reports.log"
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

  # The overseer's read-only judge call now routes through the shared agent_run
  # seam (#66 crit 6 — no inline provider exec remains in ralph scripts). The
  # `read-only` sandbox maps to claude --permission-mode plan / codex --sandbox
  # read-only — exactly the read-only modes the overseer used inline. This is a
  # non-stream seam call: the overseer parses the verdict (it never prints it
  # live), so the seam captures the model's response to a result file we read
  # back rather than streaming it. The overseer reuses the iteration agent's
  # role-resolved AGENT_MODEL/AGENT_EFFORT — its model/effort today. The seam
  # call is guarded with `|| true` so a flaky/missing provider can never kill the
  # overseer subshell, matching the old inline `|| true`.
  local result="" overseer_prompt_file overseer_result_file overseer_events_file overseer_full_prompt
  overseer_prompt_file=$(mktemp)
  overseer_result_file=$(mktemp)
  overseer_events_file=$(mktemp)

  case "$PROVIDER" in
    claude)
      # claude resolves the @${PROMPT} reference in the prompt itself.
      printf '%s' "$overseer_prompt" > "$overseer_prompt_file"
      ;;
    codex)
      # codex exec does not resolve @-references, so inline the PRD/iteration
      # prompt contents the same way the inline codex overseer call did.
      overseer_full_prompt="PRD/iteration prompt contents from ${PROMPT}:
$(cat "$PROMPT")

${overseer_prompt}"
      printf '%s' "$overseer_full_prompt" > "$overseer_prompt_file"
      ;;
  esac

  almanac_loop_agent_capture \
    "$PROVIDER" "$AGENT_MODEL" "$AGENT_EFFORT" read-only \
    "$overseer_prompt_file" "$overseer_result_file" "$overseer_events_file" \
    >/dev/null 2>&1 || true
  if [ -s "$overseer_result_file" ]; then
    result=$(cat "$overseer_result_file")
  fi
  rm -f "$overseer_prompt_file" "$overseer_result_file" "$overseer_events_file"

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
  local exit_code="${1:-0}"

  trap - EXIT INT TERM
  stop_overseer
  [ -n "${tmpfile:-}" ] && rm -f "$tmpfile"
  ralph_mark_run_finished "$exit_code"
  exit "$exit_code"
}
trap 'cleanup_all "$?"; rm -f "${RALPH_SNAP_FILE:-}"' EXIT INT TERM

if [ "${RALPH_NO_OVERSEE:-}" = "1" ]; then
  OVERSEER_DISPLAY="off (RALPH_NO_OVERSEE=1)"
else
  OVERSEER_DISPLAY="on (interval ${OVERSEE_INTERVAL}s)"
fi
CI_POLL="${RALPH_CI_POLL_INTERVAL:-30}"
CI_TIMEOUT="${RALPH_CI_WAIT_TIMEOUT:-1800}"

echo "======= RALPH AFK ======="
echo "PRD:         $PRD_NAME"
echo "Iterations:  $ITERATIONS"
echo "Prompt:      $PROMPT"
echo "Provider:    $PROVIDER_DISPLAY"
echo "Model:       $MODEL_DISPLAY"
echo "Effort:      $EFFORT_DISPLAY"
echo "Overseer:    $OVERSEER_DISPLAY"
echo "CI watch:    poll ${CI_POLL}s, timeout ${CI_TIMEOUT}s"
echo "Overseer log: $OVERSEE_LOG"
echo "Reports log: $REPORTS_LOG"
echo "========================="
echo ""

ralph_register_run "$PRD_NAME"
# Stamp launch config onto the run so `almanac hub --resume <id>` can rebuild it.
ralph_set_run_config \
  "provider=$PROVIDER" \
  "model=$AGENT_MODEL" \
  "effort=$AGENT_EFFORT" \
  "iterations=$ITERATIONS" \
  "oversee=$([ -n "${RALPH_NO_OVERSEE:-}" ] && echo off || echo on)"
echo "Run ID:      $RALPH_RUN_ID"
echo ""

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

  ralph_update_run_progress "$i" "provider=$PROVIDER iteration=$i/$ITERATIONS"

  ralph_commits=$(git log --grep="RALPH($PRD_NAME)" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

  prompt_prefix=$(build_prompt_prefix)

  case "$PROVIDER" in
    claude)
      # Default claude path routes through the shared agent_run seam in stream
      # mode rather than an inline claude exec (#66 — ralph migration onto the
      # engine). The seam builds the same invocation afk used (--print
      # --output-format stream-json --verbose, plus --model/--effort) and pipes
      # the live assistant text to stdout through the same jq filter — console
      # output is unchanged. afk's iteration agent has NEVER set --permission-mode,
      # so we pass the `default` sandbox sentinel: the seam omits --permission-mode
      # (claude's own default mode), unlike once.sh which uses acceptEdits.
      # The role-resolved AGENT_MODEL/AGENT_EFFORT feed the seam's model/effort.
      # The seam writes the extracted result to $tmpfile (its result_file), so the
      # <promise> extraction below reads it back via cat, like the codex branch.
      # Unlike the old inline pipe (no pipefail), the seam preserves claude's exit
      # via PIPESTATUS, so a provider failure now propagates instead of being
      # swallowed — matching the codex branch and once.sh's claude routing.
      prompt="${prompt_prefix}@$PROMPT Previous RALPH commits: $ralph_commits"
      claude_prompt_file=$(mktemp)
      claude_events_file=$(mktemp)
      printf '%s' "$prompt" > "$claude_prompt_file"
      if ! almanac_loop_agent_stream \
        claude "$AGENT_MODEL" "$AGENT_EFFORT" default \
        "$claude_prompt_file" "$tmpfile" "$claude_events_file"; then
        rm -f "$claude_prompt_file" "$claude_events_file"
        echo "Claude failed."
        exit 1
      fi
      rm -f "$claude_prompt_file" "$claude_events_file"

      result=$(cat "$tmpfile")
      ;;
    codex)
      prompt="${prompt_prefix}# OUTPUT STYLE

As you work, emit concise progress updates describing what you are doing and what you learned. Keep these updates short and useful. Do not manually paste command output; the runner logs raw tool output separately.

$(cat "$PROMPT")

Previous RALPH commits:
$ralph_commits"
      mkdir -p "docs/plans/${PRD_NAME}"
      codex_log="docs/plans/${PRD_NAME}/ralph-codex-iteration-${i}.log"
      echo "Codex session log: $codex_log"
      if [ "${RALPH_CODEX_VERBOSE:-}" = "1" ]; then
        # Raw-output mode now routes through the shared agent_run seam too, via its
        # raw passthrough mode (#66 crit 6 — no inline provider exec remains): raw
        # runs codex WITHOUT --json so its native output streams straight to the
        # terminal (no jq filter, no events capture); --output-last-message
        # captures the final message to $tmpfile, so the <promise> extraction
        # below reads it back unchanged. The role-resolved AGENT_MODEL/AGENT_EFFORT
        # feed the seam, which propagates codex's exit (run marked failed on
        # failure, as set -e did). (MODEL_ARG/EFFORT_ARG remain — the overseer
        # still uses them.)
        codex_prompt_file=$(mktemp)
        printf '%s' "$prompt" > "$codex_prompt_file"
        if ! almanac_loop_agent_raw \
          codex "$AGENT_MODEL" "$AGENT_EFFORT" danger-full-access \
          "$codex_prompt_file" "$tmpfile"; then
          rm -f "$codex_prompt_file"
          echo "Codex failed."
          exit 1
        fi
        rm -f "$codex_prompt_file"
      else
        # Default codex path routes through the shared agent_run seam in stream
        # mode rather than an inline codex exec (#66 — ralph migration onto the
        # engine). The seam builds the same invocation (--json
        # --output-last-message, --sandbox danger-full-access, plus --model/-c
        # effort), tees the raw stream to the per-iteration session log, and pipes
        # the live agent-message text through the same jq filter — console output
        # is unchanged. merge-stderr preserves afk's `codex ... 2>&1 | tee` so
        # codex's stderr still lands in the log. The role-resolved
        # AGENT_MODEL/AGENT_EFFORT feed the seam's model/effort, and the seam
        # preserves codex's exit via PIPESTATUS (afk kept pipefail before; the seam owns
        # that now). The result lands in $tmpfile (the seam's
        # --output-last-message target) so the <promise> extraction below reads it
        # back unchanged. On failure we print the same log tail.
        codex_prompt_file=$(mktemp)
        printf '%s' "$prompt" > "$codex_prompt_file"
        if ! almanac_loop_agent_stream \
          codex "$AGENT_MODEL" "$AGENT_EFFORT" danger-full-access \
          "$codex_prompt_file" "$tmpfile" "$codex_log" merge-stderr; then
          rm -f "$codex_prompt_file"
          echo "Codex failed. Last log lines:"
          tail -n 40 "$codex_log" || true
          exit 1
        fi
        rm -f "$codex_prompt_file"
        cat "$tmpfile"
      fi

      result=$(cat "$tmpfile")
      ;;
  esac

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
