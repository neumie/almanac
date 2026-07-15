#!/usr/bin/env bash
# role.sh - Role config resolution (role -> provider/model/effort)
#
# A role is a configurable slot a loop fills with an agent config: loop's
# `agent`; converge's `agent`/`overseer`. Resolution layers most
# specific first — lens -> role -> consumer-wide -> default — over env keys
# named <PREFIX>[_<ROLE>][_<LENS>]_<FIELD> (uppercased, non-alnum -> `_`).
#
# Self-contained like lib/ui.sh / lib/run.sh: uses only printf/tr/sed and bash
# indirect expansion (no lib/core.sh dependency), so this file's interface is its
# own test surface (tests/test-role.sh). Callers source it directly.

# A single env-key component: uppercased, runs of non-alphanumerics collapsed to
# one `_`, leading/trailing `_` trimmed. Joined with `_` to form a candidate key.
almanac_loop_env_key_part() {
  printf '%s' "$1" \
    | tr '[:lower:]' '[:upper:]' \
    | sed 's/[^A-Z0-9][^A-Z0-9]*/_/g; s/^_//; s/_$//'
}

# Echo an env var's value if it is SET (even when empty), returning 0; return 1
# when the name is unset. The `+x` test distinguishes set-empty from unset so an
# explicitly-empty override wins over a more general layer.
almanac_loop_env_value() {
  local name="$1"

  if [ "${!name+x}" ]; then
    printf '%s\n' "${!name}"
    return 0
  fi

  return 1
}

# Resolve one field of a role's config, most specific layer first:
#   <PREFIX>_<ROLE>_<LENS>_<FIELD> -> <PREFIX>_<ROLE>_<FIELD>
#   -> <PREFIX>_<FIELD> -> default_value
# The lens layer is skipped when lens is empty. Returns 2 on missing args.
almanac_loop_role_field() {
  [ "$#" -ge 5 ] || return 2

  local prefix="$1"
  local role="$2"
  local lens="$3"
  local field="$4"
  local default_value="$5"
  local prefix_key role_key lens_key field_key candidate value

  prefix_key="$(almanac_loop_env_key_part "$prefix")"
  role_key="$(almanac_loop_env_key_part "$role")"
  lens_key="$(almanac_loop_env_key_part "$lens")"
  field_key="$(almanac_loop_env_key_part "$field")"

  if [ -n "$lens_key" ]; then
    candidate="${prefix_key}_${role_key}_${lens_key}_${field_key}"
    if value="$(almanac_loop_env_value "$candidate")"; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  candidate="${prefix_key}_${role_key}_${field_key}"
  if value="$(almanac_loop_env_value "$candidate")"; then
    printf '%s\n' "$value"
    return 0
  fi

  candidate="${prefix_key}_${field_key}"
  if value="$(almanac_loop_env_value "$candidate")"; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '%s\n' "$default_value"
}

# Resolve a role's (provider, model, effort) as ONE tab-separated line — the
# single shape every loop role resolver emits. Each of the three fields is
# resolved through almanac_loop_role_field with its own default. Designed to be
# paired with `IFS=$'\t' read -r provider model effort < <(almanac_loop_role_resolve …)`,
# so a caller pulls three locals in one read instead of triple-calling a thin
# wrapper that re-walks the env layering for each field. Returns 2 on missing
# args.
almanac_loop_role_resolve() {
  [ "$#" -ge 2 ] || return 2

  local prefix="$1"
  local role="$2"
  local lens="${3:-}"
  local default_provider="${4:-}"
  local default_model="${5:-}"
  local default_effort="${6:-}"

  printf '%s\t%s\t%s\n' \
    "$(almanac_loop_role_field "$prefix" "$role" "$lens" "provider" "$default_provider")" \
    "$(almanac_loop_role_field "$prefix" "$role" "$lens" "model" "$default_model")" \
    "$(almanac_loop_role_field "$prefix" "$role" "$lens" "effort" "$default_effort")"
}
