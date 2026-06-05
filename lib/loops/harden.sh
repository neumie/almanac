#!/usr/bin/env bash
# lib/loops/harden.sh — the harden loop adapter.
#
# One file owns everything the engine needs to know about how to launch and
# control the harden loop. Auto-discovered by lib/loops.sh from lib/loops/*.sh.
#
# Contract (called as almanac_loop_harden_<verb>):
#   launch        — interactive config + exec. Used by lib/loop-launcher.sh's
#                   dispatch (no central case-statement on loop type).
#   launch_usage  — the --help text printed for this loop's launcher.
#   exec_argv     — populate _ALMANAC_LOOP_ARGV with the runner exec tokens
#                   for a given target/rounds. Harden's runner runs through the
#                   CLI (`almanac harden <target> --loop`).
#   new_run_argv  — emit the hub's "new run" launcher argv (one token per line)
#                   from key=val pairs; reviewer/role config rides on env, not
#                   argv (see new_run_env).
#   new_run_env   — emit KEY=VALUE env lines for the reviewer/role config
#                   (HARDEN_LENSES/PROVIDER/MODEL/EFFORT) so the hub never has
#                   to know harden's env prefixes.
#   new_run_usage — one-line missing-config hint for hub errors.
#
# Control contract (signal_file) inherits the default `.harden-stop` /
# `.harden-steer` convention from lib/loops.sh — no adapter override needed.
#
# The launch verb uses helpers defined in lib/loop-launcher.sh
# (_almanac_launch_need_provider/_choice/_positive_int, almanac_loop_launch_summary)
# and the shared UI / provider seams. The launcher sources those before
# dispatching, so the adapter need not source them itself.

# Build harden's runner exec command into _ALMANAC_LOOP_ARGV (the launcher execs
# it). harden has no standalone runner script — its convergence loop runs through
# the CLI (`almanac harden <target> --loop [--rounds N]`), so the adapter yields
# that bin/almanac invocation. The reviewer/role config rides on environment
# exported by the launcher, not argv. Requires $ALMANAC_HOME (set by every entry
# point).
almanac_loop_harden_exec_argv() {
  local target="$1" rounds="${2:-}"
  _ALMANAC_LOOP_ARGV=(bash "$ALMANAC_HOME/bin/almanac" harden "$target" --loop)
  [ -n "$rounds" ] && _ALMANAC_LOOP_ARGV+=(--rounds "$rounds")
  return 0
}

# Interactive config + exec for the harden loop. Parses native flags, prompts
# for any missing field, exports the role-config env, and execs the runner via
# the exec_argv verb. Called by lib/loop-launcher.sh's adapter dispatch — no
# central code branches on loop type.
almanac_loop_harden_launch() {
  local target="" lenses="" provider="" model="" effort="" rounds="" yes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lenses)   shift; lenses="${1:-}";   [ -n "$lenses" ] || _die "--lenses requires a value" ;;
      --provider) shift; provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"; [ -n "$provider" ] || _die "--provider requires a value" ;;
      --model)    shift; model="${1:-}";    [ -n "$model" ] || _die "--model requires a value" ;;
      --effort|--thinking) shift; effort="${1:-}"; [ -n "$effort" ] || _die "$1 requires a value" ;;
      --rounds)   shift; rounds="${1:-}";   [ -n "$rounds" ] || _die "--rounds requires a value" ;;
      --yes|-y) yes=1 ;;
      --help|-h) almanac_loop_harden_launch_usage; return 0 ;;
      -*) _die "Unknown harden launch option: $1" ;;
      *)  [ -z "$target" ] && target="$1" || _die "Unexpected harden argument: $1" ;;
    esac
    shift
  done

  [ -n "$target" ] || target="$(almanac_loop_ui_input "What to harden (path, PR ref, or description)")" || return 1
  [ -n "$target" ] || _die "A harden target is required."

  lenses="$(test -n "$lenses" && printf '%s' "$lenses" || almanac_loop_ui_input "Lenses (blank = default set)")" || return 1
  # Provider / model / effort — the universal role-config dance, owned by the
  # launcher helper. Harden's reviewer role is the dominant role here, hence the
  # "Reviewer …" label qualifier (conductor and fixer roles inherit reviewer's
  # provider unless overridden via HARDEN_{CONDUCTOR,FIXER}_* env).
  { IFS= read -r provider && IFS= read -r model && IFS= read -r effort; } \
    < <(_almanac_launch_need_role_triple "$provider" "$model" "$effort" \
          "Reviewer model" "Reviewer thinking effort") || return 1
  rounds="$(_almanac_launch_need_positive_int_optional "Round budget" "$rounds")" || return 1

  almanac_loop_launch_summary "harden" \
    "Target:$target" "Lenses:${lenses:-default set}" "Provider:$provider" \
    "Model:${model:-provider default}" "Thinking:${effort:-provider default}" \
    "Rounds:${rounds:-default budget}"
  [ -n "$yes" ] || almanac_loop_ui_confirm "Launch this run?" || { _info "Cancelled."; return 0; }

  [ -n "$lenses" ] && export HARDEN_LENSES="$lenses"
  _almanac_launch_export_role HARDEN_ "$provider" "$model" "$effort"

  # Exec the runner via the harden adapter (its convergence loop runs through
  # `almanac harden <target> --loop` — the adapter owns that invocation).
  almanac_loop_adapter_call harden exec_argv "$target" "$rounds" \
    || _die "harden adapter could not build a runner for target: $target"
  exec "${_ALMANAC_LOOP_ARGV[@]}"
}

# Compose the hub's new-run launcher argv for harden (one token per line). The
# convergence loop launches via `almanac harden <target> --loop [--rounds N]` —
# all other reviewer/role config rides on env (see new_run_env). Returns 2 when
# a required field (target) is missing.
almanac_loop_harden_new_run_argv() {
  local target rounds
  target="$(_almanac_loop_kv_get target "$@")"
  rounds="$(_almanac_loop_kv_get rounds "$@")"

  [ -n "$target" ] || return 2
  printf '%s\n%s\n%s\n' harden "$target" --loop
  [ -n "$rounds" ] && printf '%s\n%s\n' --rounds "$rounds"
  return 0
}

# Compose the hub's new-run env stream for harden (KEY=VALUE per line) from
# key=val pairs: reviewer lenses + role config (HARDEN_LENSES / HARDEN_PROVIDER /
# HARDEN_MODEL / HARDEN_EFFORT). Empty fields drop their key.
almanac_loop_harden_new_run_env() {
  local provider model effort lenses
  provider="$(_almanac_loop_kv_get provider "$@")"
  model="$(_almanac_loop_kv_get model "$@")"
  effort="$(_almanac_loop_kv_get effort "$@")"
  lenses="$(_almanac_loop_kv_get lenses "$@")"
  [ -n "$lenses" ] && printf 'HARDEN_LENSES=%s\n' "$lenses"
  _almanac_loop_emit_role_env HARDEN_ "$provider" "$model" "$effort"
}

almanac_loop_harden_new_run_usage() {
  printf '%s\n' "requires --target <what-to-harden>"
}

# Read a harden run's status blob and emit the key=val pairs that
# almanac_loop_harden_new_run_argv / _new_run_env consume — the inverse of those
# composers. Resume / clone in the hub pipes the output straight to them, so the
# hub never has to know harden's status schema (it used to; this verb is the
# deepening that makes the hub loop-agnostic).
almanac_loop_harden_status_to_opts() {
  local status_file="$1"
  almanac_loop_status_emit_opt "$status_file" target
  almanac_loop_status_emit_opt "$status_file" lenses
  almanac_loop_status_emit_opt "$status_file" provider
  almanac_loop_status_emit_opt "$status_file" model
  almanac_loop_status_emit_opt "$status_file" effort
  almanac_loop_status_emit_opt "$status_file" rounds
  return 0
}

# --help text for `almanac harden --loop` / `almanac_loop_launch harden`. Stays
# inside the adapter so adding a loop is a one-file change.
almanac_loop_harden_launch_usage() {
  cat >&2 <<'EOF'
Usage (loop launch): <target> [options]
  <target>            what to harden: a path, a PR ref ("PR 47"), or a description
  --lenses <list>     reviewer lenses (blank = default set)
  --provider <p>      codex | claude
  --model <m>         reviewer model
  --effort <l>        reviewer thinking level
  --rounds <n>        round budget
Any option not given is prompted interactively.
EOF
}
