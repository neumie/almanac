#!/usr/bin/env bash
# lib/loops/converge.sh - converge loop adapter.
#
# Contract (called as almanac_loop_converge_<verb>):
#   launch        — interactive config + exec. Used by lib/loop-launcher.sh's
#                   dispatch (no central case-statement on loop type).
#   launch_usage  — the --help text printed for this loop's launcher.
#   exec_argv     — populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                   for a given goal / exec / rounds / oversee config. Converge's
#                   runner is the CLI itself (`almanac converge --goal … --exec …`),
#                   so the adapter yields that bin/almanac invocation. Mirrors
#                   harden's adapter shape (no standalone runner script).
#   new_run_argv  — emit the hub's "new run" launcher argv (one token per line)
#                   from key=val pairs; role config rides on env (see
#                   new_run_env). Enforces the prompt/exec mutex.
#   new_run_env   — emit KEY=VALUE env lines for the role config (CONVERGE_*)
#                   so the hub never has to know converge's env prefixes.
#
# Control contract (signal_file) inherits the default `.converge-stop` /
# `.converge-steer` convention from lib/loops.sh — no adapter override needed.
#
# The launch verb uses helpers defined in lib/loop-launcher.sh
# (_almanac_launch_need_provider/_choice/_positive_int, almanac_loop_launch_summary)
# and the shared UI / provider seams. The launcher sources those before
# dispatching, so the adapter need not source them itself.

# Build converge's runner exec command into _ALMANAC_LOOP_ARGV (the launcher
# execs it). Positional args:
#   $1  goal           (required)
#   $2  action_mode    "prompt" | "exec" (required) — picks the flag $3 maps to
#   $3  action         the prompt text OR shell command (required)
#   $4  rounds         (optional) numeric budget
#   $5  no_oversee     (optional) "1" / "true" enables, anything else is off
#   $6  oversee_every  (optional) cadence
# The role config (provider/model/effort per CONVERGE_AGENT_* / CONVERGE_OVERSEER_*)
# rides on environment exported by the launcher, not argv — same split ralph and
# harden use. Requires $ALMANAC_HOME (set by every entry point).
# Returns 2 on an unknown action_mode.
almanac_loop_converge_exec_argv() {
  local goal="$1" mode="$2" action="$3" rounds="${4:-}" no_oversee="${5:-}" oversee_every="${6:-}"
  local action_flag
  case "$mode" in
    prompt) action_flag="--prompt" ;;
    exec)   action_flag="--exec" ;;
    *) return 2 ;;
  esac
  _ALMANAC_LOOP_ARGV=(bash "$ALMANAC_HOME/bin/almanac" converge --goal "$goal" "$action_flag" "$action")
  [ -n "$rounds" ]         && _ALMANAC_LOOP_ARGV+=(--rounds "$rounds")
  [ -n "$no_oversee" ]     && [ "$no_oversee" != "0" ] && _ALMANAC_LOOP_ARGV+=(--no-oversee)
  [ -n "$oversee_every" ]  && _ALMANAC_LOOP_ARGV+=(--oversee-every "$oversee_every")
  return 0
}

# Interactive config + exec for the converge loop. Parses native flags, prompts
# for any missing field, exports the role-config env, and execs the runner via
# the exec_argv verb. Called by lib/loop-launcher.sh's adapter dispatch — no
# central code branches on loop type.
almanac_loop_converge_launch() {
  local goal="" exec_cmd="" prompt="" rounds="" provider="" model="" effort="" no_oversee="" oversee_every="" yes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --goal)       shift; goal="${1:-}";       [ -n "$goal" ] || _die "--goal requires a value" ;;
      --exec)       shift; exec_cmd="${1:-}";   [ -n "$exec_cmd" ] || _die "--exec requires a value" ;;
      --prompt)     shift; prompt="${1:-}";     [ -n "$prompt" ] || _die "--prompt requires a value" ;;
      --rounds)     shift; rounds="${1:-}";     [ -n "$rounds" ] || _die "--rounds requires a value" ;;
      --provider)   shift; provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"; [ -n "$provider" ] || _die "--provider requires a value" ;;
      --model)      shift; model="${1:-}";      [ -n "$model" ] || _die "--model requires a value" ;;
      --effort|--thinking) shift; effort="${1:-}"; [ -n "$effort" ] || _die "$1 requires a value" ;;
      --no-oversee) no_oversee=1 ;;
      --oversee-every) shift; oversee_every="${1:-}"; [ -n "$oversee_every" ] || _die "--oversee-every requires a value" ;;
      --yes|-y) yes=1 ;;
      --help|-h) almanac_loop_converge_launch_usage; return 0 ;;
      *) _die "Unknown converge launch option: $1" ;;
    esac
    shift
  done

  # Goal is always required. Action is either --prompt (agent invocation —
  # dominant mode, takes slash commands / chains / free-form text) or --exec
  # (shell command run by a wrapping worker agent — escape hatch). Mutex
  # enforced; the runner enforces it again so direct invocations stay safe.
  if [ -n "$prompt" ] && [ -n "$exec_cmd" ]; then
    _die "--prompt and --exec are mutually exclusive — pick one"
  fi

  [ -n "$goal" ] || goal="$(almanac_loop_ui_input "Goal (one-line description of convergence target)")" || return 1
  [ -n "$goal" ] || _die "A converge goal is required."

  # If neither --prompt nor --exec was passed, ask which mode the operator
  # wants and prompt for the value. Default to prompt-mode because slash-command
  # convergence is the canonical use case.
  if [ -z "$prompt" ] && [ -z "$exec_cmd" ]; then
    local action_mode
    action_mode="$(almanac_loop_ui_choose "Action mode" "prompt (agent invocation — recommended)" "exec (shell command)")" || return 1
    case "$action_mode" in
      prompt*)
        prompt="$(almanac_loop_ui_input "Prompt (slash command, chain, or free-form — sent to agent each round)")" || return 1
        [ -n "$prompt" ] || _die "A converge --prompt or --exec is required."
        ;;
      exec*)
        exec_cmd="$(almanac_loop_ui_input "Exec (shell command run by wrapping worker agent each round)")" || return 1
        [ -n "$exec_cmd" ] || _die "A converge --prompt or --exec is required."
        ;;
    esac
  fi

  local action_mode action_text
  if [ -n "$prompt" ]; then
    action_mode="prompt"
    action_text="$prompt"
  else
    action_mode="exec"
    action_text="$exec_cmd"
  fi

  # Provider / model / effort — same resolution as ralph + harden. Single
  # provider drives both the worker and overseer roles by default; the user can
  # still override per-role via CONVERGE_{AGENT,OVERSEER}_* env outside the
  # launcher.
  provider="$(_almanac_launch_need_provider provider "$provider")" || return 1
  almanac_provider_known "$provider"     || _die "--provider must be a supported provider (e.g. codex or claude)"
  almanac_provider_available "$provider" || _die "Provider '$provider' selected but its CLI is not on PATH."
  model="$(_almanac_launch_need_choice "Model" "$model" $(almanac_provider_models "$provider"))" || return 1
  effort="$(_almanac_launch_need_choice "Thinking effort" "$effort" $(almanac_provider_efforts "$provider"))" || return 1

  # Rounds: optional; blank accepts the cmd/converge.sh default
  # (CONVERGE_ROUND_BUDGET or 10). Validated when present.
  [ -n "$rounds" ] || rounds="$(almanac_loop_ui_input "Round budget (blank = default)")" || return 1
  [ -z "$rounds" ] || rounds="$(_almanac_launch_need_positive_int "Round budget" "$rounds")" || return 1

  # Overseer: on by default; ask the operator only if neither flag was passed.
  if [ -z "$no_oversee" ]; then
    almanac_loop_ui_confirm "Run the overseer?" || no_oversee=1
  fi

  almanac_loop_launch_summary "converge" \
    "Goal:$goal" \
    "$([ "$action_mode" = "prompt" ] && printf 'Prompt:%s' "$action_text" || printf 'Exec:%s' "$action_text")" \
    "Provider:$provider" \
    "Model:${model:-provider default}" "Thinking:${effort:-provider default}" \
    "Rounds:${rounds:-default budget}" \
    "Overseer:$([ -n "$no_oversee" ] && echo off || echo on)" \
    $([ -n "$oversee_every" ] && printf 'Oversee-every:%s' "$oversee_every")
  [ -n "$yes" ] || almanac_loop_ui_confirm "Launch this run?" || { _info "Cancelled."; return 0; }

  # Export role config — same shape as ralph/harden. The consumer-wide
  # CONVERGE_PROVIDER/MODEL/EFFORT becomes the fallback that role.sh's lookup
  # uses for both the worker and overseer roles unless the user has set
  # CONVERGE_{AGENT,OVERSEER}_* explicitly.
  export CONVERGE_PROVIDER="$provider"
  [ -n "$model" ]  && export CONVERGE_MODEL="$model"   || unset CONVERGE_MODEL
  [ -n "$effort" ] && export CONVERGE_EFFORT="$effort" || unset CONVERGE_EFFORT

  # Build the runner argv via the adapter (the path to bin/almanac and the flag
  # composition both live in this file — the launcher doesn't know them). The
  # adapter takes mode + action so the same call shape works for both --prompt
  # and --exec.
  almanac_loop_adapter_call converge exec_argv "$goal" "$action_mode" "$action_text" "$rounds" "$no_oversee" "$oversee_every" \
    || _die "converge adapter could not build a runner for goal: $goal"
  exec "${_ALMANAC_LOOP_ARGV[@]}"
}

# Compose the hub's new-run launcher argv for converge (one token per line). The
# runner is `almanac converge --goal <g> (--prompt|--exec) <action> [...]`; role
# config (provider/model/effort) rides on env via new_run_env. Returns 2 when a
# required field is missing or the prompt/exec mutex is violated.
almanac_loop_converge_new_run_argv() {
  local goal="" prompt="" exec_cmd="" rounds="" oversee="" oversee_every=""
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      goal) goal="$val" ;;
      prompt) prompt="$val" ;;
      exec) exec_cmd="$val" ;;
      rounds) rounds="$val" ;;
      oversee) oversee="$val" ;;
      oversee_every) oversee_every="$val" ;;
    esac
  done

  [ -n "$goal" ] || return 2
  # Mutex: prompt is the dominant mode (agent invocation); exec is the escape
  # hatch (shell command in a wrapping worker). Enforced here so the hub never
  # composes a malformed launch; cmd/converge.sh enforces it again for direct
  # invocations.
  if [ -n "$prompt" ] && [ -n "$exec_cmd" ]; then return 2; fi
  [ -n "$prompt" ] || [ -n "$exec_cmd" ] || return 2

  printf '%s\n' converge
  printf '%s\n%s\n' --goal "$goal"
  if [ -n "$prompt" ]; then
    printf '%s\n%s\n' --prompt "$prompt"
  else
    printf '%s\n%s\n' --exec "$exec_cmd"
  fi
  [ -n "$rounds" ]        && printf '%s\n%s\n' --rounds "$rounds"
  [ "$oversee" = "off" ]  && printf '%s\n' --no-oversee
  [ -n "$oversee_every" ] && printf '%s\n%s\n' --oversee-every "$oversee_every"
  return 0
}

# Compose the hub's new-run env stream for converge (KEY=VALUE per line) from
# key=val pairs: the consumer-wide CONVERGE_PROVIDER/MODEL/EFFORT that role.sh's
# lookup uses for both worker and overseer roles unless the user has set
# CONVERGE_{AGENT,OVERSEER}_* explicitly. Empty fields drop their key.
almanac_loop_converge_new_run_env() {
  local provider="" model="" effort="" kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      provider) provider="$val" ;;
      model)    model="$val" ;;
      effort)   effort="$val" ;;
    esac
  done
  [ -n "$provider" ] && printf 'CONVERGE_PROVIDER=%s\n' "$provider"
  [ -n "$model" ]    && printf 'CONVERGE_MODEL=%s\n' "$model"
  [ -n "$effort" ]   && printf 'CONVERGE_EFFORT=%s\n' "$effort"
  return 0
}

# --help text for `almanac converge` / `almanac_loop_launch converge`. Stays
# inside the adapter so adding a loop is a one-file change.
almanac_loop_converge_launch_usage() {
  cat >&2 <<'EOF'
Usage (loop launch): converge [options]
  --goal <text>       one-line convergence goal (overseer can mutate it)
  --prompt <text>     prompt sent to the configured agent each round (slash
                      command, chain, or free-form). The dominant mode.
  --exec <cmd>        shell command run by a wrapping worker agent each round
                      (escape hatch for non-agent workflows).
                      Exactly one of --prompt / --exec is required.
  --provider <p>      codex | claude
  --model <m>         worker / overseer model
  --effort <l>        thinking level
  --rounds <n>        round budget (blank = default 10)
  --no-oversee        disable the overseer (rounds budget is the only stop)
  --oversee-every <n> overseer cadence in rounds (default 1)
Any option not given is prompted interactively.
EOF
}
