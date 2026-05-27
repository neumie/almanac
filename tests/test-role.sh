#!/usr/bin/env bash
# test-role.sh - role config resolution tests (lib/role.sh)
#
# Sources lib/role.sh DIRECTLY (not through loop-core) so the role resolver —
# almanac_loop_env_key_part / _env_value / role_field / role_config — is its own
# test surface. These pin the layered precedence (lens -> role -> consumer-wide
# -> default), the set-empty-wins rule, env-key normalisation, and the three-row
# role_config projection that harden (test-harden-cli) and ralph build on.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/role.sh"

fail() {
  echo "  FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

echo "=== Role Config Resolution Tests ==="

test_env_key_part_normalises_to_upper_underscore() {
  assert_eq "RALPH_AGENT" "$(almanac_loop_env_key_part "ralph-agent")" \
    "lowercase + hyphen should uppercase and join with _"
  assert_eq "A_B_C" "$(almanac_loop_env_key_part "a..b  c")" \
    "runs of non-alnum should collapse to a single _"
  assert_eq "X" "$(almanac_loop_env_key_part "-x-")" \
    "leading/trailing separators should be trimmed"
  echo "  PASS: env key part normalises to UPPER_UNDERSCORE"
}

test_role_field_lens_layer_wins() {
  local actual
  actual="$(
    HARDEN_PROVIDER=claude \
    HARDEN_REVIEWER_PROVIDER=codex \
    HARDEN_REVIEWER_SECURITY_PROVIDER=opus \
    almanac_loop_role_field "harden" "reviewer" "security" "provider" "fallback"
  )"
  assert_eq "opus" "$actual" "the lens-specific key is most specific and must win"
  echo "  PASS: role_field lens layer wins"
}

test_role_field_role_layer_beats_consumer_wide() {
  local actual
  actual="$(
    HARDEN_PROVIDER=claude \
    HARDEN_REVIEWER_PROVIDER=codex \
    almanac_loop_role_field "harden" "reviewer" "security" "provider" "fallback"
  )"
  assert_eq "codex" "$actual" "with no lens key the role key beats the consumer-wide key"
  echo "  PASS: role_field role layer beats consumer-wide"
}

test_role_field_consumer_wide_beats_default() {
  local actual
  actual="$(
    HARDEN_PROVIDER=claude \
    almanac_loop_role_field "harden" "reviewer" "security" "provider" "fallback"
  )"
  assert_eq "claude" "$actual" "with no role/lens key the consumer-wide key beats the default"
  echo "  PASS: role_field consumer-wide beats default"
}

test_role_field_falls_through_to_default() {
  local actual
  actual="$(
    env -u HARDEN_PROVIDER -u HARDEN_REVIEWER_PROVIDER -u HARDEN_REVIEWER_SECURITY_PROVIDER \
      bash -c "source '$ROOT/lib/role.sh'; almanac_loop_role_field harden reviewer security provider fallback"
  )"
  assert_eq "fallback" "$actual" "with no key set at any layer the default value is used"
  echo "  PASS: role_field falls through to default"
}

test_role_field_lens_skipped_when_empty() {
  local actual
  actual="$(
    RALPH_AGENT_PROVIDER=codex \
    RALPH_PROVIDER=claude \
    almanac_loop_role_field "ralph" "agent" "" "provider" "fallback"
  )"
  assert_eq "codex" "$actual" "an empty lens skips the lens layer and uses the role key"
  echo "  PASS: role_field skips the lens layer when lens is empty"
}

test_role_field_set_empty_beats_general_layer() {
  local actual
  actual="$(
    HARDEN_REVIEWER_PROVIDER= \
    HARDEN_PROVIDER=claude \
    almanac_loop_role_field "harden" "reviewer" "security" "provider" "fallback"
  )"
  assert_eq "" "$actual" "an explicitly-empty role key must win over the consumer-wide layer"
  echo "  PASS: role_field set-empty key beats a more general layer"
}

test_role_field_requires_five_args() {
  local rc=0
  almanac_loop_role_field "harden" "reviewer" "security" "provider" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "role_field with fewer than 5 args should return 2 (got $rc)"
  echo "  PASS: role_field requires five args"
}

test_resolves_role_config_with_lens_overrides() {
  local expected actual
  expected=$(cat <<'EOF'
provider	codex
model	security-model
effort	medium
EOF
)
  actual="$(
    HARDEN_PROVIDER=claude \
    HARDEN_MODEL=default-model \
    HARDEN_EFFORT=medium \
    HARDEN_REVIEWER_PROVIDER=codex \
    HARDEN_REVIEWER_SECURITY_MODEL=security-model \
    almanac_loop_role_config "harden" "reviewer" "security" "fallback-provider" "fallback-model" "low"
  )"
  assert_eq "$expected" "$actual" "lens config should layer lens, role, shared, then defaults"
  echo "  PASS: resolves role config with lens overrides"
}

test_resolves_role_config_with_ralph_style_fallbacks() {
  local expected actual
  expected=$(cat <<'EOF'
provider	claude
model	sonnet
effort	high
EOF
)
  actual="$(
    RALPH_PROVIDER=claude \
    RALPH_MODEL=sonnet \
    RALPH_EFFORT=high \
    almanac_loop_role_config "ralph" "worker" "" "codex" "" "medium"
  )"
  assert_eq "$expected" "$actual" "shared config should support Ralph-style global overrides"
  echo "  PASS: resolves role config with Ralph-style fallbacks"
}

test_role_config_requires_two_args() {
  local rc=0
  almanac_loop_role_config "harden" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "role_config with fewer than 2 args should return 2 (got $rc)"
  echo "  PASS: role_config requires two args"
}

test_role_tsv_field_reads_named_field() {
  local stream actual
  stream=$(printf 'provider\tcodex\nmodel\tgpt-5\neffort\thigh\n')
  actual="$(printf '%s' "$stream" | almanac_loop_role_tsv_field provider)"
  assert_eq "codex" "$actual" "role_tsv_field reads provider"
  actual="$(printf '%s' "$stream" | almanac_loop_role_tsv_field effort)"
  assert_eq "high" "$actual" "role_tsv_field reads effort"
  actual="$(printf '%s' "$stream" | almanac_loop_role_tsv_field missing)"
  assert_eq "" "$actual" "role_tsv_field echoes empty for an absent field"
  # The reader consumes the whole stream (no awk early-exit) so a producer in a
  # `set -o pipefail` shell never takes a SIGPIPE.
  actual="$(set -o pipefail; printf '%s' "$stream" | almanac_loop_role_tsv_field provider)"
  assert_eq "codex" "$actual" "role_tsv_field is pipefail-safe (no early-exit SIGPIPE)"
  echo "  PASS: role_tsv_field reads a field from a TSV stream"
}

test_role_resolve_emits_one_tab_separated_line() {
  local actual provider model effort
  actual="$(
    HARDEN_PROVIDER=claude \
    HARDEN_MODEL=sonnet \
    HARDEN_EFFORT=high \
    HARDEN_REVIEWER_PROVIDER=codex \
    HARDEN_REVIEWER_SECURITY_MODEL=security-model \
    almanac_loop_role_resolve "harden" "reviewer" "security" "fallback-provider" "fallback-model" "low"
  )"
  assert_eq $'codex\tsecurity-model\thigh' "$actual" \
    "role_resolve must emit provider<TAB>model<TAB>effort on one line"
  # The intended caller idiom: pull three locals with one read.
  IFS=$'\t' read -r provider model effort <<< "$actual"
  assert_eq "codex" "$provider" "read should populate provider"
  assert_eq "security-model" "$model" "read should populate model"
  assert_eq "high" "$effort" "read should populate effort"
  echo "  PASS: role_resolve emits one tab-separated line"
}

test_role_resolve_requires_two_args() {
  local rc=0
  almanac_loop_role_resolve "harden" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "role_resolve with fewer than 2 args should return 2 (got $rc)"
  echo "  PASS: role_resolve requires two args"
}

test_role_resolve_uses_defaults_when_env_unset() {
  local actual
  actual="$(
    env -u RALPH_PROVIDER -u RALPH_MODEL -u RALPH_EFFORT \
        -u RALPH_AGENT_PROVIDER -u RALPH_AGENT_MODEL -u RALPH_AGENT_EFFORT \
      bash -c "source '$ROOT/lib/role.sh'; almanac_loop_role_resolve ralph agent '' codex sonnet medium"
  )"
  assert_eq $'codex\tsonnet\tmedium' "$actual" \
    "role_resolve must fall through to per-field defaults when nothing is set"
  echo "  PASS: role_resolve falls through to defaults"
}

test_env_key_part_normalises_to_upper_underscore
test_role_field_lens_layer_wins
test_role_field_role_layer_beats_consumer_wide
test_role_field_consumer_wide_beats_default
test_role_field_falls_through_to_default
test_role_field_lens_skipped_when_empty
test_role_field_set_empty_beats_general_layer
test_role_field_requires_five_args
test_resolves_role_config_with_lens_overrides
test_resolves_role_config_with_ralph_style_fallbacks
test_role_config_requires_two_args
test_role_tsv_field_reads_named_field
test_role_resolve_emits_one_tab_separated_line
test_role_resolve_requires_two_args
test_role_resolve_uses_defaults_when_env_unset

echo ""
echo "All role config resolution tests passed."
