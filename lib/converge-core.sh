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
_almanac_source_sibling role.sh   almanac_loop_role_resolve

# Plan-dir name discipline:
#
# Each converge run gets its own directory under docs/plans/converge/. Pre-fix
# the dir name was just the kebab'd goal text — so re-running with the same
# goal collided into the same directory, mixing agent-reports.log entries,
# overwriting convergence.md, and hiding which iteration log belonged to which
# run. The slugs also rendered as 60-90-char near-duplicates ("the-skill-
# codebase-improve-gives-no-real-improvements" vs "the-skill-almanac-codebase-
# improve-doesn-t-give-any-substantial-improvements-to-do") that were
# impossible to distinguish at a glance in `ls`.
#
# New format: `YYYY-MM-DD-HHMMSS-<short-slug>` where short-slug is the goal
# truncated to ~30 chars. Sortable chronologically by name, recognizable by
# the slug tail, and a fresh timestamp means a fresh dir even for the same
# goal — no more collisions.
#
# Two access patterns:
#   * Inside a run: almanac_converge_run captures the dir name ONCE at scaffold
#     time into a non-exported shell var (_almanac_converge_active_plan_dir_name).
#     Subshells and dynamic-scope helpers within the run see it; spawned
#     SUBPROCESS agents (claude/codex) do NOT — so a parallel converge whose
#     worker invokes a fresh agent can't poison that agent's environment with
#     the parent run's plan-dir. Pre-fix this was an EXPORTED env var, and the
#     leak silently steered tests/test-converge.sh inside a nested agent into
#     the wrong dir.
#   * Outside a run (CLI --watch / --stop / --status): the user types a slug
#     they remember; we resolve to the latest matching dir via the registry.

# Build the plan dir path. Accepts EITHER a full timestamped dir name (used
# inside an active run, where the run's scaffolded name is the source of
# truth — captured at scaffold time in _almanac_converge_active_plan_dir_name)
# OR a short slug (used by CLI lookups — `almanac converge <slug> --watch`).
#
# Resolution rules:
#   1. _almanac_converge_active_plan_dir_name is set  → use it (active run)
#   2. arg matches an existing dir exactly            → use it (already resolved)
#   3. arg matches an existing dir by suffix `-arg`   → use the latest match
#   4. nothing matches                                → use arg verbatim (caller
#                                                       is about to create it)
#
# Rule 1 is the "the active run owns its dir for its full lifetime" guarantee
# — without it, a concurrent run of the same short-slug could race and steal
# the lookup. The var is NEVER exported — dynamic-scope visibility within the
# run is enough; subprocess agents must not see it.
almanac_converge_plan_dir() {
  local root="$1"
  local query="$2"
  local resolved

  if [ -n "${_almanac_converge_active_plan_dir_name:-}" ]; then
    resolved="$_almanac_converge_active_plan_dir_name"
  elif resolved="$(almanac_converge_resolve_plan_dir_name "$root" "$query" 2>/dev/null)"; then
    :
  else
    resolved="$query"
  fi
  almanac_loop_plan_dir converge "$root" "$resolved"
}

# Goal-form sibling of almanac_converge_plan_dir: a caller that has a GOAL (not
# yet a slug) asks for its plan_dir directly. Composes slug + plan_dir in one
# call so internal helpers that own a goal stop repeating
# `almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")"` — five
# callsites used to spell that two-step pre-slug dance and one carried a dead
# `slug` local (computed but never read after the plan_dir lookup, because the
# inside-an-active-run path short-circuits to _almanac_converge_active_plan_dir_name
# and ignores the slug arg anyway). The query-form
# almanac_converge_plan_dir stays for callers that already have a slug in scope
# (CLI commands taking a user-typed slug; internal helpers that also need slug
# for other uses like `CONVERGE_SLUG=$slug`).
almanac_converge_plan_dir_for_goal() {
  local root="$1"
  local goal="$2"
  almanac_converge_plan_dir "$root" "$(almanac_loop_slug "$goal")"
}

# Truncate the goal's kebab slug to a length that's comfortable in `ls`.
# 30 chars is enough to recognize a goal at a glance ("codebase-improve-no-
# major" vs "fix-the-test-suite") without dominating the directory listing
# when a 90-char goal text gets passed in.
#
# Multi-line goals are normalized to a single line before slugging — almanac_loop_slug
# uses sed which processes line-by-line, so a `$'first\nsecond'` goal would emit
# `first\nsecond` (TWO lines) and the resulting dir name would contain an
# embedded newline. The `tr '\n' ' '` collapses linebreaks before the kebab
# pass so the slug stays a single token.
almanac_converge_short_slug() {
  local goal="$1" normalized full short
  normalized="$(printf '%s' "$goal" | tr '\n' ' ')"
  full="$(almanac_loop_slug "$normalized")"
  short="$(printf '%s' "$full" | cut -c1-30)"
  # Strip trailing `-` so a truncation that lands mid-word doesn't leave a
  # dangling separator ("codebase-improve-no-major-" → "codebase-improve-no-major").
  short="${short%-}"
  printf '%s\n' "$short"
}

# Compose a plan-dir name from goal + timestamp. The timestamp is the
# discriminator that lets multi-run runs of the same goal coexist (each gets
# its own dir). Format: YYYY-MM-DD-HHMMSS-<short-slug>. The timestamp is UTC
# so it sorts identically regardless of the operator's local timezone.
# Second arg lets tests pin a deterministic timestamp.
almanac_converge_compose_plan_dir_name() {
  local goal="$1" ts="${2:-}"
  [ -n "$ts" ] || ts="$(date -u +'%Y-%m-%d-%H%M%S')"
  printf '%s-%s\n' "$ts" "$(almanac_converge_short_slug "$goal")"
}

# Resolve the most recent plan-dir name matching a goal-derived slug. Used by
# CLI commands that take a slug from the user (--watch / --stop / no-flag
# status). The user types the SHORT slug they remember; we scan plan dirs and
# return the latest matching one (alphabetical sort = chronological since the
# timestamp comes first in the dir name).
#
# Match rule: a dir name "ENDS WITH -<slug>" matches that slug. So both
#   "2026-05-27-084312-codebase-improve" matches slug "codebase-improve"
#   "2026-05-27-084312-codebase-improve" matches slug "improve" (suffix)
# The suffix match is intentional — users may type just the distinctive
# tail of a slug to save typing. If ambiguous, the latest wins.
#
# Also accepts a full dir name (already-resolved) as input — returns it
# unchanged if a dir of that name exists. So callers can pass either a
# user-typed short slug OR an already-resolved full name without branching.
#
# Returns 1 when no matching dir exists.
almanac_converge_resolve_plan_dir_name() {
  local root="$1" query="$2"
  local container match
  container="$(almanac_loop_plan_container converge "$root")"
  [ -d "$container" ] || return 1

  # Exact match wins (already-resolved full name)
  if [ -d "$container/$query" ]; then
    printf '%s\n' "$query"
    return 0
  fi

  # Otherwise suffix-match on `-<query>` and return the lexicographically
  # latest (= chronologically newest because of the timestamp prefix).
  match="$(ls -1 "$container" 2>/dev/null | grep -E -- "-${query}\$" | sort | tail -1)"
  [ -n "$match" ] || return 1
  printf '%s\n' "$match"
}

# Scaffold a fresh plan dir for a converge run. Generates a NEW timestamped
# dir name (so concurrent / repeated runs of the same goal never collide on
# the same dir). Prints the chosen dir name to stdout so the caller can use
# it as the run's stable handle for subsequent operations.
#
# A pre-existing dir name can be passed as the optional third arg to pin the
# scaffold to that specific name — used by tests for deterministic fixtures,
# and by any future "resume" path that wants to re-enter an existing dir.
almanac_converge_scaffold() {
  local root="$1"
  local goal="$2"
  local dir_name="${3:-}"
  local plan_dir

  [ -n "$dir_name" ] || dir_name="$(almanac_converge_compose_plan_dir_name "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$dir_name")"

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

  printf '%s\n' "$dir_name"
}

# Resolve the role's (provider, model, effort) as one tab-separated line. The
# deep form callers use to populate three locals in one shot:
#   IFS=$'\t' read -r provider model effort < <(almanac_converge_role_resolve agent)
# Pre-deepening, every callsite triple-called a thin `_role_field` wrapper that
# itself re-walked the env layering for each field — nine env lookups per agent
# spawn for three values. Returns 2 on unknown role.
almanac_converge_role_resolve() {
  local role="$1"

  case "$role" in
    agent|overseer) ;;
    *) return 2 ;;
  esac

  almanac_loop_role_resolve "converge" "$role" "" "$(almanac_provider_default)" "" ""
}

almanac_converge_ensure_prompt_template() {
  local root="$1"
  local goal="$2"
  local plan_dir prompt_file

  plan_dir="$(almanac_converge_plan_dir_for_goal "$root" "$goal")"
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
  local slug plan_dir rel_plan steer_content

  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  rel_plan="${plan_dir#"$root"/}"

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

  # Signal files live in the plan dir (per-run scope), not at $root — so a
  # CONVERGED verdict from one converge run cannot poison another sharing
  # the same workspace.
  if steer_content="$(almanac_loop_consume_signal converge "$plan_dir" steer)"; then
    printf '\n===== STEER =====\n%s\n===== END STEER =====\n' "$steer_content"
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

Notes on GOAL_UPDATE (used below): emit a rewritten goal ONLY if the current
goal is structurally broken — too vague to judge (no falsifiable criterion),
too narrow to permit real fixes, phrased as absence-of-problem when the work
needs presence-of-property, or contradicted by what every recent self-report
says is the real work. Otherwise emit the literal word 'unchanged'. Goal
mutation is steering, not editorial polish. GOAL_UPDATE may span multiple
lines because it is the final field; the parser captures everything from the
GOAL_UPDATE: marker to EOF.

Now respond — emit EXACTLY these four lines, in this order, no preamble, no
markdown decoration (no **bold**, no ### headings, no - bullets, no > quotes,
no code fences). Each KEY lives at column 0 with the literal colon:

VERDICT: <CONVERGED|CONTINUE|STEER|STOP>
REASON: <one paragraph explaining the verdict>
STEER: <one paragraph of next-round guidance, or the literal word 'none'>
GOAL_UPDATE: <complete new goal.md text, or the literal word 'unchanged'>

All four lines are REQUIRED. Skipping any of them is a protocol violation —
the parser will tag it with PARSE_NOTE and the operator will see the gap in
overseer.log. If a value is "none" or "unchanged", write that word; don't
omit the line.

Example response (verbatim shape — copy the structure, fill the values):

VERDICT: CONTINUE
REASON: Round 4 surveyed 8 candidates and round 5 implemented finding #3 (extract role-env emitter). Three candidates remain unaddressed; the run hasn't yet converged because the worker is still finding work.
STEER: Implement finding #2 from round 4 (control-file wrapper deduplication) — the seam shows up in two adapters so the extraction will pay.
GOAL_UPDATE: unchanged
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
  # subsequent non-key lines append to whatever field is currently open.
  #
  # Pre-leniency: parser only matched the literal "KEY:" prefix. LLMs that
  # added markdown bold (`**VERDICT:**`), heading hashes (`### VERDICT:`),
  # or list-bullet markers (`- VERDICT:`) silently failed the case match,
  # found_X stayed 0, and the guard at the bottom returned with all defaults
  # — producing the canonical "VERDICT=CONTINUE, REASON='', STEER=none,
  # GOAL_UPDATE=unchanged" mirage seen across every overseer tick of three
  # consecutive converge runs.
  #
  # Now: strip a small set of decorative prefixes (markdown bold, leading
  # `#`/`-`/`*`/`>` characters + space) from the start of each line BEFORE
  # the case match, and trim trailing `**` for the bold-close variant
  # (`**VERDICT:**`). This is purposely a tight whitelist — we don't want
  # to start accepting `; VERDICT:` or `// VERDICT:` and then debug new
  # ambiguities; just the markdown shapes models actually emit.
  while IFS= read -r line || [ -n "$line" ]; do
    # Normalize a small set of decorative prefixes that wrap KEY: markers.
    # The targeted shapes (in order, all anchored to start of line):
    #   `**VERDICT:** value`   markdown bold + colon-close
    #   `**VERDICT:**`         bold-only, value on next line
    #   `### VERDICT: value`   markdown heading (1-6 hashes)
    #   `- VERDICT: value`     list bullet (`-` or `*`)
    #   `> VERDICT: value`     quote marker (rare but seen)
    # Each strips ONLY the surrounding decoration, leaves the KEY: literal
    # alone so the case match below works unchanged. Continuation lines
    # (paragraph body) bypass these substitutions when they don't start
    # with a recognized decoration — values keep their internal markdown
    # (e.g. a REASON paragraph with `**bold**` inline emphasis stays
    # intact).
    key_line="$(printf '%s' "$line" | sed -E '
      s/^[[:space:]]+//
      s/^\*\*([A-Z_]+):\*\*[[:space:]]*/\1: /
      s/^\*\*([A-Z_]+):\*\*[[:space:]]*$/\1:/
      s/^#+[[:space:]]+([A-Z_]+:)/\1/
      s/^[-*][[:space:]]+([A-Z_]+:)/\1/
      s/^>[[:space:]]*([A-Z_]+:)/\1/
    ')"
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

  # Partial-output policy: capture every field we DID find, default-fill the
  # rest. Pre-fix the parser bailed completely on any missing field —
  # silently returning all-defaults — which masked the LLM's actual
  # response. Now: VERDICT is required (a missing verdict can't be safely
  # defaulted to CONTINUE — that's confusing; bail), but REASON / STEER /
  # GOAL_UPDATE missing just keep their initial defaults ("", "none",
  # "unchanged") and we proceed with the verdict we have. The bare verdict
  # case (LLM emits "VERDICT: CONTINUE" followed by a paragraph instead of
  # the other three keys) now produces a useful tick: the verdict is
  # honored, the REASON section in overseer.log shows empty (operator can
  # tighten the prompt), STEER stays none, goal stays unchanged.
  if [ "$found_verdict" -ne 1 ]; then
    # No usable verdict at all — surface this so the operator sees the
    # parse failure in the overseer log instead of a silent all-defaults
    # fallback. Caller still gets the conservative CONTINUE default but
    # the parse-failure marker stamps the cause.
    ALMANAC_CONVERGE_PARSE_NOTE="no VERDICT marker found"
    return 0
  fi
  ALMANAC_CONVERGE_PARSE_NOTE=""

  # Note in the parse marker which optional fields the LLM skipped — so the
  # operator can see whether to tighten the prompt for that model.
  local _missing=()
  [ "$found_reason" -eq 1 ] || _missing+=(REASON)
  [ "$found_steer" -eq 1 ]  || _missing+=(STEER)
  [ "$found_goal" -eq 1 ]   || _missing+=(GOAL_UPDATE)
  if [ "${#_missing[@]}" -gt 0 ]; then
    ALMANAC_CONVERGE_PARSE_NOTE="missing fields: ${_missing[*]}"
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

  plan_dir="$(almanac_converge_plan_dir_for_goal "$root" "$goal")"
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

  if run_id="$(almanac_loop_latest_run_for_target "$root" "converge" "$slug" 2>/dev/null)"; then
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
    if run_id="$(almanac_loop_latest_run_for_target "$root" "converge" "$slug" 2>/dev/null)"; then
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
  local plan_dir plan_stop

  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  [ -d "$plan_dir" ] || return 1
  # Signal file lives in the plan dir (per-run scope). Pre-fix this wrote
  # BOTH $root and $plan_dir to dual-target both the old and new convention;
  # now the round loop only watches $plan_dir, so the $root write was dead.
  plan_stop="$(almanac_loop_run_control_file converge "$plan_dir" stop)"
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

  plan_dir="$(almanac_converge_plan_dir_for_goal "$root" "$goal")"
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

# Run an agent shape (`stream` / `capture`) with cwd anchored at $root. The
# three converge agent callsites (exec-mode worker, prompt-mode worker,
# overseer) all need the agent process inside $root — exec_cmd in the
# worker prompts is shell the agent runs against the project, and the
# overseer's git log / git status references resolve relative to $root.
# The agent runner itself (lib/agent.sh) is cwd-agnostic by design (slice
# 04 contract), so converge owns this anchor as a local verb instead of
# leaking a cd into every callsite. Args after $root pass straight through
# to almanac_loop_agent_<shape>.
almanac_converge_agent_in_root() {
  local shape="$1" root="$2"
  shift 2
  ( cd "$root" && "almanac_loop_agent_$shape" "$@" )
}

almanac_converge_run_worker() {
  local root="$1"
  local goal="$2"
  local exec_cmd="$3"
  local round="$4"
  local provider model effort prompt_file result_file events_file plan_dir rc

  IFS=$'\t' read -r provider model effort < <(almanac_converge_role_resolve agent)
  plan_dir="$(almanac_converge_plan_dir_for_goal "$root" "$goal")"

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
  almanac_converge_agent_in_root stream "$root" "$provider" "$model" "$effort" "danger-full-access" \
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

  # Distinctive fallback message — `git log` makes it visually obvious which
  # commits were AI-authored (real summary lines) vs driver-fallback (this
  # generic message that just records the round number). When you see a lot
  # of "driver-fallback" entries, the prompt isn't pushing the agent to
  # commit; tighten the worker prompt's commit instructions.
  if ! (cd "$root" \
          && git -c user.email=converge@almanac -c user.name=converge \
                 commit -m "CONVERGE($slug): round $round — driver-fallback (agent did not author commit)" \
                 --no-verify >/dev/null 2>&1); then
    _warn "Converge round $round: auto-commit failed (changes left in worktree)"
  fi
}

almanac_converge_run_worker_prompt() {
  local root="$1"
  local goal="$2"
  local prompt="$3"
  local round="$4"
  local provider model effort prompt_file result_file events_file rc
  local slug plan_dir log_file steer_content ts result_summary

  IFS=$'\t' read -r provider model effort < <(almanac_converge_role_resolve agent)
  slug="$(almanac_loop_slug "$goal")"
  plan_dir="$(almanac_converge_plan_dir "$root" "$slug")"
  log_file="$plan_dir/agent-reports.log"

  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-result.XXXXXX")"
  # Persistent per-round session log under the plan dir (same shape as
  # exec-mode + ralph's per-iteration logs). Streams live to terminal so the
  # operator sees the agent working; tees the raw stream here for forensics.
  events_file="$plan_dir/converge-${provider}-iteration-${round}.log"

  # Prompt assembly:
  #   1. Optional steer directive (one-shot, removed after consumption — the
  #      steer file is per-plan-dir; see signal_dir override in lib/loops/converge.sh)
  #   2. CONVERGE LOOP ground rules — including commit-message instructions
  #      so the AGENT authors meaningful commit messages instead of the
  #      driver fallback "round N" (which says nothing about what changed)
  #   3. The user's verbatim --prompt text
  #
  # The ground-rules block is prepended (not appended) so the agent reads it
  # as CONTEXT for the work, not as a post-hoc demand. Same reason ralph's
  # iteration prompt frames the task before listing the rules.
  local rel_plan_for_prompt="${plan_dir#"$root"/}"
  {
    if steer_content="$(almanac_loop_consume_signal converge "$plan_dir" steer)"; then
      printf '# Steer directive (from previous overseer tick):\n%s\n\n' "$steer_content"
    fi
    cat <<EOF
# === CONVERGE LOOP — round $round ===

You are one iteration of an autonomous convergence loop. The driver runs you
headlessly (no human to answer AskUserQuestion); the overseer reviews your
work between rounds via git log + agent-reports.log.

## Commit your work yourself

AFTER you finish the user prompt below, COMMIT your changes:

  git -c user.email=converge@almanac -c user.name=converge \\
      commit -am "CONVERGE($slug): <one-line summary>"

The "CONVERGE($slug):" prefix is REQUIRED — the overseer's drift review uses
\`git log --grep="CONVERGE($slug):"\` to find your work each tick. Without it
the overseer thinks the round did nothing.

The <one-line summary> must describe WHAT you changed, concretely:

  GOOD:  "extract loop-adapter signal_dir verb; scope converge signals to plan dir"
  GOOD:  "fix harden ratify gate threading: pass conductor to demo_reproduces"
  GOOD:  "rename almanac_converge_role_field -> almanac_converge_role_resolve"

  BAD:   "round $round"
  BAD:   "applied codebase-improve"
  BAD:   "improvements"
  BAD:   "fix stuff"

Do NOT commit:
  - .almanac/                    (run registry — runtime only)
  - $rel_plan_for_prompt/        (this run's plan dir — runtime artifacts)

If you finished without making meaningful changes, leave the worktree clean
and don't commit. The driver detects this and skips its fallback commit too.

If you committed correctly, the driver's auto-commit fallback will be a
no-op (clean worktree). If you forgot, the driver commits leftover changes
with a generic "round $round — driver-fallback" message — which shows up in
git log as a signal that the agent didn't author the message that round.

## User prompt

EOF
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
  almanac_converge_agent_in_root stream "$root" "$provider" "$model" "$effort" "danger-full-access" \
    "$prompt_file" "$result_file" "$events_file" merge-stderr || rc=$?

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
  local provider model effort result rc plan_dir log_file ts
  local prompt_file result_file events_file

  IFS=$'\t' read -r provider model effort < <(almanac_converge_role_resolve overseer)
  plan_dir="$(almanac_converge_plan_dir_for_goal "$root" "$goal")"
  log_file="$plan_dir/overseer.log"

  # Persist the overseer's events stream alongside the worker's iteration
  # logs. Pre-fix the overseer used `capture_text`, which silently discarded
  # the events.jsonl after extracting the final message — so when the LLM
  # emitted weird/terse output (observed: 10 consecutive ticks emitting just
  # "GOAL_UPDATE: unchanged") the operator had no way to inspect WHAT the
  # LLM did during the tick. Now: stream to terminal AND persist the events
  # to $plan_dir/converge-<provider>-overseer-tick-N.log — mirroring the
  # worker iteration logs, so `tail -f` works live and the file stays for
  # forensics post-run.
  prompt_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-prompt.XXXXXX")"
  result_file="$(mktemp "${TMPDIR:-/tmp}/almanac-converge-overseer-result.XXXXXX")"
  events_file="$plan_dir/converge-${provider}-overseer-tick-${round}.log"

  almanac_converge_overseer_prompt "$root" "$goal" "$round" > "$prompt_file"

  _info "Converge overseer tick $round (provider=$provider, log: ${events_file#"$root"/})"

  rc=0
  almanac_converge_agent_in_root stream "$root" "$provider" "$model" "$effort" "read-only" \
    "$prompt_file" "$result_file" "$events_file" merge-stderr || rc=$?

  result=""
  [ -s "$result_file" ] && result="$(cat "$result_file")"
  # events_file is persistent — NOT removed here. prompt/result are scratch.
  rm -f "$prompt_file" "$result_file"

  [ "$rc" -eq 0 ] || _warn "Converge overseer tick $round exited $rc; continuing"
  almanac_converge_overseer_parse "$result"

  # Log the RAW LLM response alongside the parsed verdict. Pre-fix the
  # overseer log showed only the parsed fields, so a parse failure (LLM
  # using markdown bold, skipping fields, putting the value on the next
  # line) looked identical to "the LLM gave us nothing useful". The raw
  # block is fenced so it's visually distinct from the structured parser
  # output and easy to grep for ("===== RAW =====") when debugging.
  ts="$(almanac_loop_now_utc)"
  {
    printf '\n===== tick=%s ts=%s overseer=%s exit=%s =====\n' "$round" "$ts" "$provider" "$rc"
    printf 'VERDICT: %s\n' "$ALMANAC_CONVERGE_VERDICT"
    printf 'REASON: %s\n' "$ALMANAC_CONVERGE_REASON"
    printf 'STEER: %s\n' "$ALMANAC_CONVERGE_STEER"
    printf 'GOAL_UPDATE: %s\n' "$ALMANAC_CONVERGE_GOAL_UPDATE"
    if [ -n "${ALMANAC_CONVERGE_PARSE_NOTE:-}" ]; then
      printf 'PARSE_NOTE: %s\n' "$ALMANAC_CONVERGE_PARSE_NOTE"
    fi
    printf '\n===== RAW LLM RESPONSE =====\n'
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
    else
      printf '(empty — provider exited %s with no final message)\n' "$rc"
    fi
    printf '===== END RAW =====\n'
  } >> "$log_file"

  if [ "$ALMANAC_CONVERGE_GOAL_UPDATE" != "unchanged" ]; then
    almanac_converge_apply_goal_update "$root" "$goal" "$round" "$provider" \
      "$ALMANAC_CONVERGE_REASON" "$ALMANAC_CONVERGE_GOAL_UPDATE"
  fi

  # Verdict signals land in the run's plan_dir (per-run scope) so a CONVERGED
  # verdict cannot poison subsequent unrelated runs sharing the same workspace
  # — see lib/loops/converge.sh::almanac_loop_converge_signal_dir.
  case "$ALMANAC_CONVERGE_VERDICT" in
    CONVERGED|STOP)
      : > "$(almanac_loop_run_control_file converge "$plan_dir" stop)"
      ;;
    STEER)
      if [ "$ALMANAC_CONVERGE_STEER" != "none" ]; then
        printf '%s\n' "$ALMANAC_CONVERGE_STEER" > "$(almanac_loop_run_control_file converge "$plan_dir" steer)"
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
  local slug plan_dir run_id pid exec_rc round started_epoch action_mode
  local final_status final_outcome final_verdict final_reason

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

  # Mark the run aborted on any unexpected exit (signal, mid-round _die) that
  # leaves it still running; the normal exit paths below mark done/failed and
  # clear this. The shared helper owns the %q bake — see
  # `almanac_loop_install_finalize_trap` in lib/run.sh for why that matters.
  # _almanac_converge_active_plan_dir_name is a local to THIS function, so it
  # goes out of scope when the function returns — no explicit cleanup needed,
  # and no risk of leaking into a CLI command issued after the loop exits.
  # The dir name remains discoverable via the run's status.tsv `plan_dir` field.
  almanac_loop_install_finalize_trap "$root" "$run_id"

  # Persist enough of the launch config that the hub's resume path can rebuild
  # the same invocation from status.tsv alone — see almanac_loop_converge_status_to_opts.
  # Without these the hub would resume with --goal blank / no action verb.
  almanac_loop_set_run_config "$root" "$run_id" \
    "goal=$goal" \
    "prompt=$prompt" \
    "exec=$exec_cmd" \
    "rounds=$rounds" \
    "oversee=$([ "$no_oversee" -eq 1 ] && printf off || printf 'every-%s' "$oversee_every")" \
    "oversee_every=$oversee_every" \
    >/dev/null 2>&1 || true

  # Scaffold creates a fresh timestamped plan dir; capture the name so every
  # helper within this run targets THE SAME dir for its full lifetime (no
  # races with concurrent same-goal runs that might scaffold their own dir
  # mid-loop). Stored as a NON-exported shell var: helpers and `(...)`
  # subshells inherit it via bash dynamic scope, but exec'd subprocess agents
  # (claude/codex) do not — so a parent converge can't poison a nested agent's
  # environment with its plan-dir name. Pre-fix this was `export`ed and the
  # leak silently steered tests/test-converge.sh inside nested agents.
  local plan_dir_name _almanac_converge_active_plan_dir_name
  plan_dir_name="$(almanac_converge_scaffold "$root" "$goal")"
  _almanac_converge_active_plan_dir_name="$plan_dir_name"
  plan_dir="$(almanac_converge_plan_dir "$root" "$plan_dir_name")"

  # Persist the dir name on the run's status.tsv so CLI commands run AFTER
  # this run exits (when the env var is gone) can still find the right dir
  # via almanac_loop_status_field.
  almanac_loop_set_run_config "$root" "$run_id" \
    "plan_dir=$plan_dir_name" \
    >/dev/null 2>&1 || true

  # Default state when the loop exits via the round budget. `final_verdict` is
  # the overseer's LAST raw say (informational); `final_outcome` is the
  # AUTHORITATIVE termination shape (used to label convergence.md). A run that
  # hits the budget without an overseer-said CONVERGED is NON_CONVERGED — the
  # loop ran out of attempts, not consensus. Pre-fix the convergence.md just
  # echoed final_verdict, so a budget exhaustion looked like "Final verdict:
  # CONTINUE" — misread by future agents (and humans) as a soft stop.
  final_status="done"
  final_outcome="NON_CONVERGED"
  if [ "$no_oversee" -eq 1 ]; then
    final_verdict="n/a"
    final_reason="overseer disabled; round budget ($rounds) exhausted"
  else
    final_verdict="CONTINUE"
    final_reason="round budget ($rounds) exhausted; overseer's last verdict was CONTINUE"
  fi

  # Signal files live in the run's plan dir now (per-run scope; see
  # lib/loops/converge.sh::almanac_loop_converge_signal_dir). The round loop
  # watches them at $plan_dir; nothing reads from $root anymore.
  #
  # Clear leftover control signals before entering the round loop. With plan-
  # dir scoping cross-RUN contamination is structurally impossible (each run
  # has its own dir), but a user re-running converge with the SAME goal text
  # gets the SAME plan dir — and a previous run's CONVERGED would have left
  # .converge-stop sitting there, halting the new run at round 0. Clearing
  # here keeps the same-goal-re-run case clean. Same hygiene for steer (one-
  # shot directives must not bleed from a prior run).
  #
  # Also wipe the legacy $root copies in case the operator launched a prior
  # run against an older build of converge that wrote there — one-time
  # migration grace; harmless on a clean workspace.
  rm -f "$(almanac_loop_run_control_file converge "$plan_dir" stop)" \
        "$(almanac_loop_run_control_file converge "$plan_dir" steer)" \
        "$root/.converge-stop" "$root/.converge-steer"

  round=0
  while [ "$round" -lt "$rounds" ]; do
    # Stop check routes through `almanac_loop_consume_signal` — the documented
    # collapse seam in lib/run.sh:912 ("the seam they collapse onto"). Steer
    # already uses it (almanac_converge_run_worker_prompt); stop was the last
    # holdout doing a bare `[ -f $file ]` peek. Consume = read+delete in one
    # op, so a refactor of this break path can't leave the file behind for
    # the next iteration to re-fire on.
    if almanac_loop_consume_signal converge "$plan_dir" stop >/dev/null; then
      final_status="aborted"
      final_outcome="STOPPED"
      final_verdict="STOP"
      final_reason="stop signal present before round $((round + 1))"
      break
    fi

    round=$((round + 1))
    # Both worker fns route their agent invocation through
    # almanac_converge_agent_in_root (cwd anchor lives there) — the
    # dispatcher just selects which fn + which action arg (prompt vs exec_cmd).
    exec_rc=0
    case "$action_mode" in
      prompt) almanac_converge_run_worker_prompt "$root" "$goal" "$prompt"   "$round" || exec_rc=$? ;;
      *)      almanac_converge_run_worker        "$root" "$goal" "$exec_cmd" "$round" || exec_rc=$? ;;
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
      almanac_converge_write_convergence "$root" "$goal" \
        "FAILED" "${final_verdict:-n/a}" "$round" "$rounds" "$started_epoch" \
        "exec exit=$exec_rc round=$round"
      almanac_loop_run_finalize "$root" "$run_id" "failed" "exec exit=$exec_rc round=$round"
      return "$exec_rc"
    fi

    if [ "$no_oversee" -eq 0 ] && [ $((round % oversee_every)) -eq 0 ]; then
      almanac_converge_run_overseer "$root" "$goal" "$round"
      final_verdict="$ALMANAC_CONVERGE_VERDICT"
      final_reason="$ALMANAC_CONVERGE_REASON"
      case "$ALMANAC_CONVERGE_VERDICT" in
        CONVERGED)
          final_status="done"
          final_outcome="CONVERGED"
          [ -n "$final_reason" ] || final_reason="overseer verdict: CONVERGED at round $round"
          break
          ;;
        STOP)
          final_status="aborted"
          final_outcome="STOPPED"
          [ -n "$final_reason" ] || final_reason="overseer verdict: STOP at round $round"
          break
          ;;
      esac
    fi
  done

  almanac_converge_write_convergence "$root" "$goal" \
    "$final_outcome" "$final_verdict" "$round" "$rounds" "$started_epoch" "$final_reason"
  almanac_loop_run_finalize "$root" "$run_id" "$final_status"
}
