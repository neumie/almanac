#!/usr/bin/env bash
# converge-core.sh - Generic convergence loop core

# Source focused deps idempotently so tests can source this file directly.
# core.sh owns the helper, so it's pulled in via the literal pattern.
if ! declare -F _error >/dev/null 2>&1; then
  __converge_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  # shellcheck source=lib/core.sh
  source "$__converge_core_dir/core.sh"
  unset __converge_core_dir
fi

_almanac_source_sibling run.sh    almanac_loop_register_run
_almanac_source_sibling agent.sh  almanac_loop_agent_capture
_almanac_source_sibling role.sh   almanac_loop_role_config

almanac_converge_plan_dir() {
  local root="$1"
  local slug="$2"

  almanac_loop_plan_dir converge "$root" "$slug"
}

almanac_converge_scaffold() {
  local root="$1"
  local goal="$2"
  local plan_dir

  plan_dir="$(almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")")"

  if ! mkdir -p "$plan_dir"; then
    _die "Could not create converge plan dir: ${plan_dir#"$root"/}"
  fi
  if ! printf '%s\n' "$goal" > "$plan_dir/goal.md"; then
    _die "Could not write converge goal: ${plan_dir#"$root"/}/goal.md"
  fi
  if ! : > "$plan_dir/agent-reports.log"; then
    _die "Could not write converge report log: ${plan_dir#"$root"/}/agent-reports.log"
  fi
  if ! : > "$plan_dir/goal.history.log"; then
    _die "Could not write converge goal history: ${plan_dir#"$root"/}/goal.history.log"
  fi
}

almanac_converge_role() {
  local role="$1"

  case "$role" in
    agent|overseer) ;;
    *) return 2 ;;
  esac

  almanac_loop_role_config "converge" "$role" "" "$(almanac_provider_default)" "" ""
}

almanac_converge_role_field() {
  local role="$1"
  local field="$2"

  almanac_converge_role "$role" | almanac_loop_role_tsv_field "$field"
}

almanac_converge_ensure_prompt_template() {
  local root="$1"
  local goal="$2"
  local plan_dir prompt_file

  plan_dir="$(almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")")"
  prompt_file="$plan_dir/prompt.md"
  [ -f "$prompt_file" ] && return 0

  cat > "$prompt_file" <<'EOF'
# Converge Worker

You are one worker round in a generic convergence loop.

Read current goal, follow one-shot steer directive if present, run exact exec
command, then leave clear evidence in git history and agent-reports.log.

Do not edit the goal unless explicitly asked by the exec command. Do not commit
.almanac or converge state files under docs/plans/converge/.
EOF
}

almanac_converge_worker_prompt() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local round="$4"
  local slug plan_dir rel_plan steer_file

  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  rel_plan="${plan_dir#"$root"/}"
  steer_file="$(almanac_loop_run_control_file converge "$root" steer)"

  almanac_converge_ensure_prompt_template "$root" "$goal"

  cat "$plan_dir/prompt.md"
  cat <<EOF

CONVERGE_TICK=$round
CONVERGE_SLUG=$slug
CONVERGE_PLAN_DIR=$rel_plan
CONVERGE_REPORT_LOG=$rel_plan/agent-reports.log

Commit user-visible worktree changes, excluding .almanac and $rel_plan, with:
CONVERGE($slug): <one-line summary>

Append one structured self-report to $rel_plan/agent-reports.log. Use this exact
header shape and these exact section labels:

===== tick=<N> ts=<ISO> =====
summary:
concerns:
next:

For this round, N is $round.

===== GOAL.md =====
EOF
  cat "$plan_dir/goal.md"
  cat <<EOF
===== END GOAL.md =====

===== EXEC COMMAND =====
$exec_cmd
===== END EXEC COMMAND =====
EOF

  if [ -f "$steer_file" ]; then
    cat <<'EOF'

===== STEER =====
EOF
    cat "$steer_file"
    cat <<'EOF'
===== END STEER =====
EOF
    rm -f "$steer_file"
  fi
}

almanac_converge_report_log_has_structured_block() {
  local file="$1"

  [ -f "$file" ] || return 1
  awk '
    /^===== tick=[0-9][0-9]* ts=.* =====$/ {
      seen = 1
      summary = 0
      concerns = 0
      next_seen = 0
      next
    }
    seen && /^summary:$/ { summary = 1; next }
    seen && /^concerns:$/ { concerns = 1; next }
    seen && /^next:$/ { next_seen = 1; ok = summary && concerns && next_seen; next }
    END { exit ok ? 0 : 1 }
  ' "$file"
}

almanac_converge_trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

almanac_converge_overseer_prompt() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local slug plan_dir rel_plan reports_file reports commits

  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  rel_plan="${plan_dir#"$root"/}"
  reports_file="$plan_dir/agent-reports.log"

  if [ -f "$reports_file" ]; then
    reports="$(tail -c 8192 "$reports_file")"
  else
    reports="(no agent reports yet)"
  fi

  commits="$(git -C "$root" log --fixed-strings --grep="CONVERGE($slug):" -n 10 \
    --format='%H%n%ad%n%B%n---' --date=short 2>/dev/null || true)"
  [ -n "$commits" ] || commits="No CONVERGE commits yet"

  cat <<EOF
You are the overseer for converge($slug), a synchronous convergence loop.

CONVERGE_TICK=$round
CONVERGE_SLUG=$slug
CONVERGE_PLAN_DIR=$rel_plan

Judge whether the current goal is satisfied, whether the next worker needs a
one-shot steering directive, or whether the loop should stop.

===== GOAL.md =====
EOF
  cat "$plan_dir/goal.md"
  cat <<EOF
===== END GOAL.md =====

===== RECENT AGENT SELF-REPORTS (last ~8KB) =====
$reports
===== END RECENT AGENT SELF-REPORTS =====

===== RECENT CONVERGE COMMITS (last 10) =====
$commits
===== END RECENT CONVERGE COMMITS =====

Output these fields in order with no preamble:
VERDICT: <CONVERGED|CONTINUE|STEER|STOP>
REASON: <one paragraph>
STEER: <one paragraph, or 'none'>
GOAL_UPDATE: <new goal.md content, or 'unchanged'>

Be conservative. Malformed output is treated as CONTINUE with no steering and no
goal update. GOAL_UPDATE may span multiple lines because it is the final field.
EOF
}

almanac_converge_overseer_parse() {
  local input="${1:-}"
  local content line key_line current_key=""
  local raw_verdict="" raw_reason="" raw_steer="" raw_goal=""
  local found_verdict=0 found_reason=0 found_steer=0 found_goal=0

  if [ -f "$input" ]; then
    content="$(cat "$input")"
  else
    content="$input"
  fi

  ALMANAC_CONVERGE_VERDICT="CONTINUE"
  ALMANAC_CONVERGE_REASON=""
  ALMANAC_CONVERGE_STEER="none"
  ALMANAC_CONVERGE_GOAL_UPDATE="unchanged"

  # State-machine line walker. Each KEY: prefix switches the current field;
  # subsequent non-key lines append to whatever field is currently open. This
  # lets the LLM emit either inline values (`REASON: blah`) or values on the
  # next line (`REASON:\nblah`) or multi-line paragraphs that span until the
  # next KEY: marker — all parse correctly. Before this fix the parser only
  # captured the value text on the SAME line as KEY:, dropping continuation
  # lines and producing empty REASON / STEER for any LLM that emitted
  # paragraph-shaped values — the bug observed in the first --prompt converge
  # run (REASON empty, STEER none in the overseer.log entry despite the LLM
  # clearly being asked to produce both).
  while IFS= read -r line || [ -n "$line" ]; do
    key_line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    case "$key_line" in
      VERDICT:*)
        current_key="VERDICT"; found_verdict=1
        raw_verdict="${key_line#VERDICT:}"
        case "$raw_verdict" in " "*) raw_verdict="${raw_verdict# }" ;; esac
        ;;
      REASON:*)
        current_key="REASON"; found_reason=1
        raw_reason="${key_line#REASON:}"
        case "$raw_reason" in " "*) raw_reason="${raw_reason# }" ;; esac
        ;;
      STEER:*)
        current_key="STEER"; found_steer=1
        raw_steer="${key_line#STEER:}"
        case "$raw_steer" in " "*) raw_steer="${raw_steer# }" ;; esac
        ;;
      GOAL_UPDATE:*)
        current_key="GOAL_UPDATE"; found_goal=1
        raw_goal="${key_line#GOAL_UPDATE:}"
        case "$raw_goal" in " "*) raw_goal="${raw_goal# }" ;; esac
        ;;
      *)
        # Continuation line — append to whichever field is currently open.
        # Lines before the first KEY: marker (preamble noise) have current_key
        # empty and are dropped, matching the prompt's "no preamble" contract.
        # The original line (not the leading-whitespace-stripped key_line) is
        # preserved so multi-line paragraphs keep their indentation if any.
        case "$current_key" in
          VERDICT)     raw_verdict="${raw_verdict}"$'\n'"${line}" ;;
          REASON)      raw_reason="${raw_reason}"$'\n'"${line}" ;;
          STEER)       raw_steer="${raw_steer}"$'\n'"${line}" ;;
          GOAL_UPDATE) raw_goal="${raw_goal}"$'\n'"${line}" ;;
        esac
        ;;
    esac
  done <<< "$content"

  if [ "$found_verdict" -ne 1 ] || [ "$found_reason" -ne 1 ] || \
    [ "$found_steer" -ne 1 ] || [ "$found_goal" -ne 1 ]; then
    return 0
  fi

  # VERDICT is always a single token. A chatty LLM may put the token on its own
  # line and then ramble before REASON; the state-machine above will have
  # accumulated those ramble lines into raw_verdict. Reduce to the first
  # non-empty line so the case-match below still recognises the token.
  raw_verdict="$(printf '%s\n' "$raw_verdict" | awk 'NF{print; exit}')"
  raw_verdict="$(almanac_converge_trim "$raw_verdict")"
  case "$raw_verdict" in
    CONVERGED|CONTINUE|STEER|STOP) ALMANAC_CONVERGE_VERDICT="$raw_verdict" ;;
    *)
      ALMANAC_CONVERGE_VERDICT="CONTINUE"
      ALMANAC_CONVERGE_STEER="none"
      ALMANAC_CONVERGE_GOAL_UPDATE="unchanged"
      return 0
      ;;
  esac

  ALMANAC_CONVERGE_REASON="$(almanac_converge_trim "$raw_reason")"

  raw_steer="$(almanac_converge_trim "$raw_steer")"
  if [ -n "$raw_steer" ] && ! printf '%s\n' "$raw_steer" | grep -qiE '^none[[:space:]]*$'; then
    ALMANAC_CONVERGE_STEER="$raw_steer"
  fi

  if [ "$found_goal" -eq 1 ]; then
    local goal_check
    goal_check="$(almanac_converge_trim "$raw_goal")"
    if [ -n "$goal_check" ] && ! printf '%s\n' "$goal_check" | grep -qiE '^unchanged[[:space:]]*$'; then
      ALMANAC_CONVERGE_GOAL_UPDATE="$raw_goal"
    fi
  fi
}

# Write the convergence.md final record.
#
# Args:
#   root           — repo root
#   goal           — initial goal text (used to derive the plan dir)
#   outcome        — authoritative loop result, one of:
#                      CONVERGED       overseer said so → goal met
#                      NON_CONVERGED   round budget hit before overseer converged
#                      STOPPED         stop signal (overseer STOP verdict OR human
#                                      `.converge-stop`)
#                      FAILED          exec error with CONVERGE_FAIL_ON_EXEC_ERROR=1
#                      ABORTED         EXIT trap fired (mid-loop _die, signal, etc.)
#   last_verdict   — the overseer's last raw verdict, informational only
#                    (e.g. "CONTINUE" is meaningless as a FINAL answer — it just
#                    means the overseer was asked one more time and wanted more
#                    rounds). Pass "n/a" if no overseer ran (e.g. --no-oversee).
#   tick           — round number reached
#   budget         — round budget configured for the run
#   started_epoch  — UNIX timestamp the run started (or empty for "unknown")
#   reason         — one-line termination reason ("round budget exhausted (10/10)",
#                    "exec exit=2 round=4", "overseer verdict: CONVERGED").
#
# Pre-fix the writer took only a single `verdict` argument and wrote it as
# "Final verdict", which conflated three different things: the overseer's last
# raw say, the loop's actual outcome, and whether convergence was reached.
# A run that hit the round budget without convergence wrote "Final verdict:
# CONTINUE" — readable as a soft answer, actually meaning "the overseer wanted
# more rounds and we ran out". The split here makes the misread structurally
# impossible: outcome is the source of truth, last_verdict is metadata.
almanac_converge_write_convergence() {
  local root="$1"
  local goal="$2"
  local outcome="$3"
  local last_verdict="$4"
  local tick="$5"
  local budget="$6"
  local started_epoch="${7:-}"
  local reason="${8:-}"
  local plan_dir now_epoch elapsed status_summary

  plan_dir="$(almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")")"
  now_epoch="$(date +%s)"
  elapsed=""
  case "$started_epoch" in
    ''|*[!0-9]*) ;;
    *) elapsed="$((now_epoch - started_epoch))s" ;;
  esac

  # Human-readable headline for the Outcome section — one line that future
  # operators (and agents reading convergence.md as evidence) can act on
  # without parsing the rest.
  case "$outcome" in
    CONVERGED)
      status_summary="CONVERGED — overseer reached convergence at round $tick of $budget."
      ;;
    NON_CONVERGED)
      status_summary="NON_CONVERGED — round budget exhausted ($tick/$budget) without overseer reaching CONVERGED."
      ;;
    STOPPED)
      status_summary="STOPPED — halted by stop signal at round $tick of $budget."
      ;;
    FAILED)
      status_summary="FAILED — exec error at round $tick of $budget."
      ;;
    ABORTED)
      status_summary="ABORTED — loop exited unexpectedly at round $tick of $budget (signal, mid-loop _die, etc.)."
      ;;
    *)
      status_summary="UNKNOWN ($outcome) — round $tick of $budget."
      ;;
  esac

  {
    printf '# Convergence\n\n'
    printf '## Outcome\n\n%s\n\n' "$status_summary"
    printf '## Last overseer verdict\n\n%s\n\n' "${last_verdict:-n/a}"
    printf '## Tick count\n\n%s of %s\n\n' "$tick" "$budget"
    printf '## Time elapsed\n\n%s\n\n' "${elapsed:-unknown}"
    printf '## Final goal\n\n'
    if [ -f "$plan_dir/goal.md" ]; then
      cat "$plan_dir/goal.md"
    fi
    printf '\n\n## Termination reason\n\n%s\n' "${reason:-none}"
  } > "$plan_dir/convergence.md"
}

almanac_converge_goal_summary() {
  printf '%s' "$1" | tr '\n' ' ' | cut -c 1-80
}

almanac_converge_latest_run_id() {
  local root="$1"
  local slug="$2"
  local rows id type target pid status_rel started status match=""

  rows="$(almanac_loop_list_runs "$root" 2>/dev/null)" || return 1
  while IFS=$'\t' read -r id type target pid status_rel started status; do
    [ -n "$id" ] || continue
    [ "$type" = "converge" ] || continue
    [ "$target" = "$slug" ] || continue
    match="$id"
  done <<< "$rows"

  [ -n "$match" ] || return 1
  printf '%s\n' "$match"
}

almanac_converge_worker_health() {
  local root="$1"
  local run_id="$2"
  local status_file status

  status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
  [ -f "$status_file" ] || { printf '%s\n' "dead"; return 0; }

  status="$(almanac_loop_status_field "$status_file" "status" || true)"
  if [ "$status" = "running" ] && ! almanac_loop_run_is_stale "$root" "$run_id"; then
    printf '%s\n' "alive"
  else
    printf '%s\n' "dead"
  fi
}

almanac_converge_last_verdict_line() {
  local log_file="$1"

  [ -f "$log_file" ] || return 1
  awk '
    /^===== tick=/ { verdict = ""; reason = "" }
    /^VERDICT: / { verdict = substr($0, 10) }
    /^REASON: / { reason = substr($0, 9) }
    END {
      if (verdict != "" || reason != "") {
        printf "%s\t%s\n", verdict, reason
      }
    }
  ' "$log_file"
}

almanac_converge_last_report_header() {
  local reports_file="$1"

  [ -f "$reports_file" ] || return 1
  grep -E '^===== tick=[0-9][0-9]* ts=.* =====$' "$reports_file" 2>/dev/null | tail -n 1
}

almanac_converge_goal_mutation_count() {
  local history_file="$1"

  [ -f "$history_file" ] || { printf '%s\n' "0"; return 0; }
  awk '/^===== tick=[0-9][0-9]* ts=.* overseer=/ { c++ } END { print c + 0 }' "$history_file"
}

almanac_converge_dashboard_frame() {
  local root="$1"
  local slug="$2"
  local plan_dir goal_file reports_file history_file log_file
  local run_id="" status_file round="" rounds="" health="dead"
  local verdict="none" reason="none" verdict_line report_header goal_text goal_summary mutations
  local tab=$'\t'

  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  [ -d "$plan_dir" ] || return 1

  goal_file="$plan_dir/goal.md"
  reports_file="$plan_dir/agent-reports.log"
  history_file="$plan_dir/goal.history.log"
  log_file="$plan_dir/overseer.log"

  if run_id="$(almanac_converge_latest_run_id "$root" "$slug" 2>/dev/null)"; then
    status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
    round="$(almanac_loop_status_field "$status_file" "round" 2>/dev/null || true)"
    rounds="$(almanac_loop_status_field "$status_file" "rounds" 2>/dev/null || true)"
    health="$(almanac_converge_worker_health "$root" "$run_id")"
  fi
  [ -n "$round" ] || round="0"
  [ -n "$rounds" ] || rounds="?"

  if verdict_line="$(almanac_converge_last_verdict_line "$log_file" 2>/dev/null)"; then
    verdict="${verdict_line%%$tab*}"
    reason="${verdict_line#*$tab}"
    [ "$reason" != "$verdict_line" ] || reason="none"
    [ -n "$verdict" ] || verdict="none"
    [ -n "$reason" ] || reason="none"
  fi

  report_header="$(almanac_converge_last_report_header "$reports_file" 2>/dev/null || true)"
  [ -n "$report_header" ] || report_header="none"

  goal_text=""
  [ -f "$goal_file" ] && goal_text="$(cat "$goal_file")"
  goal_summary="$(almanac_converge_goal_summary "$goal_text")"
  [ -n "$goal_summary" ] || goal_summary="none"
  mutations="$(almanac_converge_goal_mutation_count "$history_file")"

  printf 'converge %s\n' "$slug"
  printf 'current round: %s/%s\n' "$round" "$rounds"
  printf 'last verdict: %s\n' "$verdict"
  printf 'reason: %s\n' "$reason"
  printf 'last report: %s\n' "$report_header"
  printf 'goal: %s\n' "$goal_summary"
  printf 'goal mutations: %s\n' "$mutations"
  printf 'worker health: %s\n' "$health"
}

almanac_converge_status() {
  local root="$1"
  local slug="$2"
  local frame

  frame="$(almanac_converge_dashboard_frame "$root" "$slug")" || return 1
  printf '%s\n' "$frame" | almanac_loop_ui_render
}

almanac_converge_watch() {
  local root="$1"
  local slug="$2"
  local mode="${3:-}"
  local interval="${CONVERGE_WATCH_INTERVAL:-${ALMANAC_HUB_WATCH_INTERVAL:-2}}"
  local run_id status_file status

  if [ "$mode" != "follow" ] || [ ! -t 1 ]; then
    almanac_converge_status "$root" "$slug"
    return
  fi

  while :; do
    almanac_loop_ui_clear
    almanac_converge_status "$root" "$slug"
    if run_id="$(almanac_converge_latest_run_id "$root" "$slug" 2>/dev/null)"; then
      status_file="$(almanac_loop_run_status_file "$root" "$run_id")"
      status="$(almanac_loop_status_field "$status_file" "status" 2>/dev/null || true)"
      case "$status" in
        done|failed|aborted) break ;;
      esac
    fi
    sleep "$interval"
  done
}

almanac_converge_stop() {
  local root="$1"
  local slug="$2"
  local plan_dir root_stop plan_stop

  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  [ -d "$plan_dir" ] || return 1
  root_stop="$(almanac_loop_run_control_file converge "$root" stop)"
  plan_stop="$(almanac_loop_run_control_file converge "$plan_dir" stop)"
  printf 'stop requested via almanac converge: %s\n' "$slug" > "$root_stop"
  printf 'stop requested via almanac converge: %s\n' "$slug" > "$plan_stop"
}

almanac_converge_apply_goal_update() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local provider="$4"
  local reason="$5"
  local new_goal="$6"
  local plan_dir goal_file history_file log_file ts old_goal old_file new_file diff_output diff_status summary

  plan_dir="$(almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")")"
  goal_file="$plan_dir/goal.md"
  history_file="$plan_dir/goal.history.log"
  log_file="$plan_dir/overseer.log"
  ts="$(almanac_loop_now_utc)"
  old_goal=""
  [ -f "$goal_file" ] && old_goal="$(cat "$goal_file")"

  old_file="$plan_dir/.goal.old.$$"
  new_file="$plan_dir/.goal.new.$$"
  printf '%s\n' "$old_goal" > "$old_file"
  printf '%s\n' "$new_goal" > "$new_file"

  diff_output=""
  diff_status=127
  if command -v diff >/dev/null 2>&1; then
    if diff_output="$(diff -u "$old_file" "$new_file" 2>/dev/null)"; then
      diff_status=0
    else
      diff_status=$?
    fi
  fi

  {
    printf '===== tick=%s ts=%s overseer=%s =====\n' "$round" "$ts" "$provider"
    printf 'REASON: %s\n' "$reason"
    if [ "$diff_status" -le 1 ]; then
      printf -- '--- DIFF ---\n'
      printf '%s\n' "$diff_output"
    else
      printf -- '--- AFTER ---\n'
      printf '%s\n' "$new_goal"
    fi
  } >> "$history_file"

  printf '%s\n' "$new_goal" > "$goal_file"
  rm -f "$old_file" "$new_file"

  summary="$(almanac_converge_goal_summary "$new_goal")"
  printf '[tick=%s] goal updated: %s\n' "$round" "$summary" >> "$log_file"
}

almanac_converge_run_finalize() {
  local root="$1"
  local run_id="$2"
  local status="$3"
  local reason="${4:-}"

  trap - EXIT INT TERM
  [ -n "$run_id" ] || return 0
  almanac_loop_mark_run_status "$root" "$run_id" "$status" "" "$reason" >/dev/null 2>&1 || true
}

almanac_converge_git_user_status() {
  local root="$1"
  local plan_dir="$2"
  local rel_plan

  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  rel_plan="${plan_dir#"$root"/}"

  if [ "$rel_plan" = "$plan_dir" ]; then
    git -C "$root" status --porcelain -- . ':!.almanac'
  else
    git -C "$root" status --porcelain -- . ':!.almanac' ":!$rel_plan"
  fi
}

almanac_converge_run_worker() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local round="$4"
  local provider model effort prompt_file result_file events_file plan_dir slug rc

  provider="$(almanac_converge_role_field "agent" "provider")"
  model="$(almanac_converge_role_field "agent" "model")"
  effort="$(almanac_converge_role_field "agent" "effort")"
  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-worker-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-worker-result.XXXXXX")"
  # Persistent per-round session log under the plan dir (mirrors ralph's
  # docs/plans/<name>/ralph-codex-iteration-N.log). The full raw event stream
  # tees here while the filtered agent-message text streams live to the
  # terminal — operator sees progress, durable log is kept for forensics.
  events_file="$plan_dir/converge-${provider}-iteration-${round}.log"

  almanac_converge_worker_prompt "$root" "$goal" "$exec_cmd" "$round" > "$prompt_file"

  _info "Converge round $round — exec-mode worker (provider=$provider, log: ${events_file#"$root"/})"

  # danger-full-access sandbox: converge runs are autonomous-by-design.
  # `claude --print` has no human to answer a permission prompt, so anything
  # less than full access dies on every un-allowlisted Bash call ("This
  # command requires approval"). For codex this drops the sandbox; for claude
  # it maps to --permission-mode bypassPermissions (per the provider adapter).
  rc=0
  almanac_loop_agent_stream "$provider" "$model" "$effort" "danger-full-access" \
    "$prompt_file" "$result_file" "$events_file" merge-stderr || rc=$?

  rm -f "$prompt_file" "$result_file"
  return "$rc"
}

# Prompt-mode round: the user's --prompt text IS the agent invocation. No worker
# template wrapper — the agent receives the prompt verbatim, prefixed only with
# a one-shot .converge-steer directive if one is queued. This is the dominant
# mode for "run skill X in a convergence loop" workflows; the loop driver
# handles the bookkeeping (auto-commit + agent-reports.log entry) after the
# agent exits, instead of asking the agent to know about CONVERGE conventions.
#
# Returns the agent's exit code; commit and report writes are best-effort and
# never alter the return.
# List every currently-dirty path in $root, one per line, sorted+deduped.
# Output is the union of:
#   - tracked-modified paths (`git diff --name-only HEAD`)
#   - untracked-not-ignored paths (`git ls-files --others --exclude-standard`)
# Used by the prompt-mode auto-commit to distinguish PRE-EXISTING dirty work
# (untouched by the agent) from AGENT-TOUCHED paths (commit candidates). Empty
# string on git failure or non-repo. Pure read-only — safe to call multiple
# times per round.
almanac_converge_dirty_paths() {
  local root="$1"
  ( cd "$root" \
      && { git diff --name-only HEAD 2>/dev/null; \
           git ls-files --others --exclude-standard 2>/dev/null; } \
      | sort -u
  )
}

# Auto-commit ONLY the paths the agent newly touched this round, computed as
# (dirty-after) - (dirty-before). Pre-existing dirty paths are left alone so a
# concurrent unrelated edit never gets swept into a CONVERGE commit (the bug
# that caused commit 4526a58 to misattribute the developer's in-flight edits
# to the agent). Files that were pre-existing dirty AND also touched by the
# agent stay dirty — conservative; the agent's change in that file isn't
# committed by this round, but no false attribution happens. Best-effort:
# commit failure logs a warn and never alters the caller's return code.
#
# Args: ROOT SLUG ROUND PRE_DIRTY (newline-separated pre-existing dirty paths)
almanac_converge_commit_agent_paths() {
  local root="$1" slug="$2" round="$3" pre_dirty="$4"
  local post_dirty agent_paths

  post_dirty="$(almanac_converge_dirty_paths "$root")"
  # comm needs sorted inputs; both producers (almanac_converge_dirty_paths +
  # the snapshot taken before the agent ran) emit sorted-unique.
  agent_paths="$(comm -23 <(printf '%s\n' "$post_dirty") <(printf '%s\n' "$pre_dirty") | sed '/^$/d')"

  if [ -z "$agent_paths" ]; then
    # Either the agent didn't change anything OR every change was on a path
    # that was already dirty (so the change stays uncommitted on purpose).
    return 0
  fi

  # Stage each agent-touched path individually (handles deletions, new files,
  # and modifications — `git add` accepts paths to files that no longer exist
  # by recording the deletion).
  local path failed=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    (cd "$root" && git add -- "$path" >/dev/null 2>&1) || failed=1
  done <<< "$agent_paths"

  if [ "$failed" -eq 1 ]; then
    _warn "Converge round $round: staging one or more agent-touched paths failed (changes left in worktree)"
    return 0
  fi

  if ! (cd "$root" \
          && git -c user.email=converge@almanac -c user.name=converge \
                 commit -m "CONVERGE($slug): round $round" --no-verify >/dev/null 2>&1); then
    _warn "Converge round $round: auto-commit failed (changes left in worktree)"
  fi
}

almanac_converge_run_worker_prompt() {
  local root="$1"
  local goal="$2"
  local prompt="$3"
  local round="$4"
  local provider model effort prompt_file result_file events_file rc
  local slug plan_dir log_file steer_path ts result_summary

  provider="$(almanac_converge_role_field "agent" "provider")"
  model="$(almanac_converge_role_field "agent" "model")"
  effort="$(almanac_converge_role_field "agent" "effort")"
  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  log_file="$plan_dir/agent-reports.log"
  steer_path="$(almanac_loop_run_control_file converge "$root" steer)"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-result.XXXXXX")"
  # Persistent per-round session log under the plan dir (same shape as
  # exec-mode + ralph's per-iteration logs). Streams live to terminal so the
  # operator sees the agent working; tees the raw stream here for forensics.
  events_file="$plan_dir/converge-${provider}-iteration-${round}.log"

  # Steer (one-shot): emitted by the overseer in the prior round, consumed and
  # removed here so the next overseer tick can re-emit if the issue persists.
  # Steer prefix comes BEFORE the user prompt so a slash command sees the
  # directive as context before its own work.
  {
    if [ -f "$steer_path" ]; then
      printf '# Steer directive (from previous overseer tick):\n'
      cat "$steer_path"
      printf '\n\n'
      rm -f "$steer_path"
    fi
    printf '%s\n' "$prompt"
  } > "$prompt_file"

  _info "Converge round $round — prompt-mode worker (provider=$provider, log: ${events_file#"$root"/})"

  # Snapshot the dirty worktree BEFORE the agent runs so the auto-commit below
  # can stage only the paths the agent newly touches — not whatever unrelated
  # work the operator had in-flight. (Without this snapshot, an earlier `git
  # add -A` swept up the developer's uncommitted edits and committed them
  # under the agent's name — bug observed in commit 4526a58.)
  local pre_dirty
  pre_dirty="$(almanac_converge_dirty_paths "$root")"

  # danger-full-access: same rationale as exec-mode worker — converge agents
  # need to run arbitrary shell (tests, git status, lint) the prompt asks for.
  rc=0
  (cd "$root" && almanac_loop_agent_stream "$provider" "$model" "$effort" "danger-full-access" \
    "$prompt_file" "$result_file" "$events_file" merge-stderr) || rc=$?

  # Auto-commit only the agent-touched paths. A smart prompt may have committed
  # itself (worktree clean, nothing to do); a slash command like
  # /almanac:codebase-improve typically doesn't commit, so the driver does it.
  # Best-effort: a failed commit logs a warn but never alters the return code —
  # the agent's work itself succeeded or failed, the commit is bookkeeping.
  almanac_converge_commit_agent_paths "$root" "$slug" "$round" "$pre_dirty"

  # Auto-write a minimal self-report. Format mirrors slice-03's worker block
  # (===== tick=N ts=ISO mode=prompt exit=N =====) so the overseer's parser
  # treats it the same. result_summary is the first 500 bytes of the agent's
  # final message — enough for the overseer to see "what the agent said it
  # did" without dragging the full transcript through the prompt budget.
  ts="$(almanac_loop_now_utc)"
  result_summary="(no agent output)"
  if [ -s "$result_file" ]; then
    result_summary="$(head -c 500 "$result_file")"
  fi
  {
    printf '\n===== tick=%s ts=%s mode=prompt exit=%s =====\n' "$round" "$ts" "$rc"
    printf 'summary:\n'
    printf '%s\n' "$result_summary"
    printf 'concerns:\n(none captured — prompt mode does not enforce structured self-report)\n'
    printf 'next:\n(driven by overseer / next-round prompt)\n'
  } >> "$log_file"

  # events_file is the persistent per-round session log under the plan dir —
  # NOT removed here. prompt/result are still scratch.
  rm -f "$prompt_file" "$result_file"
  return "$rc"
}

almanac_converge_run_overseer() {
  local root="$1"
  local goal="$2"
  local round="$3"
  local provider model effort prompt_file result_file events_file result rc plan_dir log_file ts

  provider="$(almanac_converge_role_field "overseer" "provider")"
  model="$(almanac_converge_role_field "overseer" "model")"
  effort="$(almanac_converge_role_field "overseer" "effort")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")")"
  log_file="$plan_dir/overseer.log"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-result.XXXXXX")"
  events_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-events.XXXXXX")"

  almanac_converge_overseer_prompt "$root" "$goal" "$round" > "$prompt_file"

  rc=0
  (cd "$root" && almanac_loop_agent_capture "$provider" "$model" "$effort" "read-only" \
    "$prompt_file" "$result_file" "$events_file") >/dev/null || rc=$?

  result=""
  [ -s "$result_file" ] && result="$(cat "$result_file")"
  rm -f "$prompt_file" "$result_file" "$events_file"

  [ "$rc" -eq 0 ] || _warn "Converge overseer tick $round exited $rc; continuing"
  almanac_converge_overseer_parse "$result"

  ts="$(almanac_loop_now_utc)"
  {
    printf '\n===== tick=%s ts=%s overseer=%s exit=%s =====\n' "$round" "$ts" "$provider" "$rc"
    printf 'VERDICT: %s\n' "$ALMANAC_CONVERGE_VERDICT"
    printf 'REASON: %s\n' "$ALMANAC_CONVERGE_REASON"
    printf 'STEER: %s\n' "$ALMANAC_CONVERGE_STEER"
    printf 'GOAL_UPDATE: %s\n' "$ALMANAC_CONVERGE_GOAL_UPDATE"
  } >> "$log_file"

  if [ "$ALMANAC_CONVERGE_GOAL_UPDATE" != "unchanged" ]; then
    almanac_converge_apply_goal_update "$root" "$goal" "$round" "$provider" \
      "$ALMANAC_CONVERGE_REASON" "$ALMANAC_CONVERGE_GOAL_UPDATE"
  fi

  case "$ALMANAC_CONVERGE_VERDICT" in
    CONVERGED|STOP)
      : > "$(almanac_loop_run_control_file converge "$root" stop)"
      ;;
    STEER)
      if [ "$ALMANAC_CONVERGE_STEER" != "none" ]; then
        printf '%s\n' "$ALMANAC_CONVERGE_STEER" > "$(almanac_loop_run_control_file converge "$root" steer)"
      fi
      ;;
    CONTINUE) ;;
  esac
}

almanac_converge_run() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local rounds="${4:-${CONVERGE_ROUND_BUDGET:-10}}"
  local no_oversee="${5:-0}"
  local oversee_every="${6:-1}"
  local prompt="${7:-}"
  local slug plan_dir run_id pid exec_rc round started_epoch final_status final_verdict final_reason action_mode

  # Mode dispatch: prompt-mode (agent invocation, dominant) vs exec-mode (shell
  # command in a wrapping worker, escape hatch). cmd/converge.sh enforces the
  # mutex; here we just pick a label for run-config + dispatch.
  if [ -n "$prompt" ]; then
    action_mode="prompt"
  else
    action_mode="exec"
  fi

  case "$rounds" in
    ''|*[!0-9]*) _die "--rounds must be a positive integer: $rounds" ;;
  esac
  [ "$rounds" -ge 1 ] || _die "--rounds must be at least 1: $rounds"

  case "$oversee_every" in
    ''|*[!0-9]*) _die "--oversee-every must be a positive integer: $oversee_every" ;;
  esac
  [ "$oversee_every" -ge 1 ] || _die "--oversee-every must be at least 1: $oversee_every"

  case "$no_oversee" in
    1|true|yes|on) no_oversee=1 ;;
    *) no_oversee=0 ;;
  esac

  slug="$(almanac_loop_slug "$goal")"
  pid="${BASHPID:-$$}"
  started_epoch="$(date +%s)"
  run_id="$(almanac_loop_register_run "$root" "converge" "$slug" "$pid")" \
    || _die "Could not register converge run"

  local _converge_run_finalize_cmd
  printf -v _converge_run_finalize_cmd 'almanac_converge_run_finalize %q %q aborted' "$root" "$run_id"
  trap "${_converge_run_finalize_cmd}; exit 130" INT TERM
  trap "${_converge_run_finalize_cmd}" EXIT

  almanac_loop_set_run_config "$root" "$run_id" \
    "rounds=$rounds" \
    "oversee=$([ "$no_oversee" -eq 1 ] && printf off || printf 'every-%s' "$oversee_every")" \
    >/dev/null 2>&1 || true

  almanac_converge_scaffold "$root" "$goal"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"

  final_status="done"
  if [ "$no_oversee" -eq 1 ]; then
    final_verdict="NO_OVERSEE"
    final_reason="overseer disabled; round budget exhausted"
  else
    final_verdict="CONTINUE"
    final_reason="round budget exhausted"
  fi

  local _converge_stop_file
  _converge_stop_file="$(almanac_loop_run_control_file converge "$root" stop)"

  round=0
  while [ "$round" -lt "$rounds" ]; do
    if [ -f "$_converge_stop_file" ]; then
      final_status="aborted"
      final_verdict="STOP"
      final_reason="stop signal present before round $((round + 1))"
      break
    fi

    round=$((round + 1))
    case "$action_mode" in
      prompt)
        if almanac_converge_run_worker_prompt "$root" "$goal" "$prompt" "$round"; then
          exec_rc=0
        else
          exec_rc=$?
        fi
        ;;
      *)
        if (cd "$root" && almanac_converge_run_worker "$root" "$goal" "$exec_cmd" "$round"); then
          exec_rc=0
        else
          exec_rc=$?
        fi
        ;;
    esac

    # In exec-mode the worker is authoritative for commits (slice 03 contract).
    # In prompt-mode the driver already attempted the auto-commit inside the
    # worker function and will have warned on failure, so the check is skipped
    # to avoid a duplicate / misleading "driver will not commit" message.
    if [ "$action_mode" = "exec" ] \
       && [ -n "$(almanac_converge_git_user_status "$root" "$plan_dir" 2>/dev/null || true)" ]; then
      _warn "Converge round $round: worker left uncommitted changes; driver will not commit"
    fi

    if [ "$exec_rc" -ne 0 ]; then
      if [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
        _warn "Converge round $round exec exited $exec_rc; stopping"
      else
        _warn "Converge round $round exec exited $exec_rc; continuing"
      fi
    fi

    almanac_loop_update_run_progress "$root" "$run_id" "$round" "goal=$slug" >/dev/null 2>&1 || true

    if [ "$exec_rc" -ne 0 ] && [ "${CONVERGE_FAIL_ON_EXEC_ERROR:-0}" = "1" ]; then
      almanac_converge_write_convergence "$root" "$goal" "FAILED" "$round" "$started_epoch" "exec exit=$exec_rc round=$round"
      almanac_converge_run_finalize "$root" "$run_id" "failed" "exec exit=$exec_rc round=$round"
      return "$exec_rc"
    fi

    if [ "$no_oversee" -eq 0 ] && [ $((round % oversee_every)) -eq 0 ]; then
      almanac_converge_run_overseer "$root" "$goal" "$round"
      final_verdict="$ALMANAC_CONVERGE_VERDICT"
      final_reason="$ALMANAC_CONVERGE_REASON"
      case "$ALMANAC_CONVERGE_VERDICT" in
        CONVERGED)
          final_status="done"
          break
          ;;
        STOP)
          final_status="aborted"
          break
          ;;
      esac
    fi
  done

  almanac_converge_write_convergence "$root" "$goal" "$final_verdict" "$round" "$started_epoch" "$final_reason"
  almanac_converge_run_finalize "$root" "$run_id" "$final_status"
}
