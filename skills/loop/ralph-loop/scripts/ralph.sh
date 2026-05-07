#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ralph.sh [options]

Interactive Ralph loop launcher.

Options:
  --prd <name>          PRD name from plans/<name>.md
  --mode <once|afk>     Run one iteration or autonomous mode
  --provider <name>     Agent provider: codex or claude
  --model <model>       Model name. Use "default" for provider default
  --effort <level>      Thinking level. Use "default" for provider default
  --iterations <n>      AFK iteration count
  --no-oversee          Disable AFK overseer
  --help                Show this help

Examples:
  bash ralph.sh
  bash ralph.sh --prd auth-system --mode afk --provider codex --model gpt-5.5 --effort high --iterations 10
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

normalize_provider() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

provider_available() {
  case "$1" in
    codex) command -v codex >/dev/null 2>&1 ;;
    claude) command -v claude >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

detect_default_provider() {
  if [ -n "${CODEX_THREAD_ID:-}" ] && provider_available codex; then
    echo "codex"
  elif provider_available claude; then
    echo "claude"
  elif provider_available codex; then
    echo "codex"
  else
    echo ""
  fi
}

prompt_text() {
  local label="$1"
  local default_value="$2"
  local answer

  if [ -n "$default_value" ]; then
    read -r -p "$label [$default_value]: " answer
    echo "${answer:-$default_value}"
  else
    read -r -p "$label: " answer
    echo "$answer"
  fi
}

choose_from_list() {
  local label="$1"
  local default_value="$2"
  shift 2
  local items=("$@")
  local i choice item

  echo "$label" >&2
  for ((i=0; i<${#items[@]}; i++)); do
    item="${items[$i]}"
    if [ "$item" = "$default_value" ]; then
      printf '  %d) %s (default)\n' "$((i + 1))" "$item" >&2
    else
      printf '  %d) %s\n' "$((i + 1))" "$item" >&2
    fi
  done

  while true; do
    read -r -p "> " choice
    if [ -z "$choice" ] && [ -n "$default_value" ]; then
      echo "$default_value"
      return
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
      echo "${items[$((choice - 1))]}"
      return
    fi
    for item in "${items[@]}"; do
      if [ "$choice" = "$item" ]; then
        echo "$item"
        return
      fi
    done
    echo "Choose 1-${#items[@]} or type a listed value." >&2
  done
}

list_prds() {
  local file name
  for file in plans/*.md; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .md)"
    case "$name" in
      prompt-*|brief) continue ;;
    esac
    echo "$name"
  done
}

provider_model_options() {
  case "$1" in
    codex)
      printf '%s\n' default gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.3-codex-spark gpt-5.2 custom
      ;;
    claude)
      printf '%s\n' default sonnet opus haiku claude-sonnet-4-6 claude-opus-4-7 custom
      ;;
  esac
}

provider_effort_options() {
  case "$1" in
    codex)
      printf '%s\n' default low medium high xhigh custom
      ;;
    claude)
      printf '%s\n' default low medium high xhigh max custom
      ;;
  esac
}

PRD_NAME=""
MODE=""
PROVIDER=""
MODEL=""
EFFORT=""
ITERATIONS=""
NO_OVERSEE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prd)
      PRD_NAME="${2:-}"
      [ -n "$PRD_NAME" ] || die "--prd requires a value"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      [ -n "$MODE" ] || die "--mode requires a value"
      shift 2
      ;;
    --provider)
      PROVIDER="$(normalize_provider "${2:-}")"
      [ -n "$PROVIDER" ] || die "--provider requires a value"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      [ -n "$MODEL" ] || die "--model requires a value"
      shift 2
      ;;
    --effort|--thinking)
      EFFORT="${2:-}"
      [ -n "$EFFORT" ] || die "$1 requires a value"
      shift 2
      ;;
    --iterations)
      ITERATIONS="${2:-}"
      [ -n "$ITERATIONS" ] || die "--iterations requires a value"
      shift 2
      ;;
    --no-oversee)
      NO_OVERSEE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ ! -d plans ]; then
  die "plans/ not found. Run this from the project root."
fi

if [ -z "$PRD_NAME" ]; then
  PRDS=()
  while IFS= read -r prd; do
    PRDS+=("$prd")
  done < <(list_prds)
  [ "${#PRDS[@]}" -gt 0 ] || die "no PRDs found in plans/. Run /prd-create first."

  if [ "${#PRDS[@]}" -eq 1 ]; then
    PRD_NAME="${PRDS[0]}"
  else
    PRD_NAME="$(choose_from_list "Select PRD:" "${PRDS[0]}" "${PRDS[@]}")"
  fi
fi

[ -f "plans/${PRD_NAME}.md" ] || die "plans/${PRD_NAME}.md not found."
[ -f "plans/prompt-${PRD_NAME}.md" ] || die "plans/prompt-${PRD_NAME}.md not found. Run /ralph-loop ${PRD_NAME} first."

if [ -z "$MODE" ]; then
  MODE="$(choose_from_list "Select mode:" once once afk)"
fi
case "$MODE" in
  once|afk) ;;
  *) die "--mode must be once or afk" ;;
esac

if [ -z "$PROVIDER" ]; then
  PROVIDERS=()
  if provider_available codex; then
    PROVIDERS+=("codex")
  fi
  if provider_available claude; then
    PROVIDERS+=("claude")
  fi
  [ "${#PROVIDERS[@]}" -gt 0 ] || die "no supported provider found. Install Codex or Claude Code."
  DEFAULT_PROVIDER="$(detect_default_provider)"
  PROVIDER="$(choose_from_list "Select provider:" "$DEFAULT_PROVIDER" "${PROVIDERS[@]}")"
fi
case "$PROVIDER" in
  codex|claude) ;;
  *) die "--provider must be codex or claude" ;;
esac
provider_available "$PROVIDER" || die "provider '$PROVIDER' is selected, but its CLI is not on PATH."

if [ -z "$MODEL" ]; then
  MODELS=()
  while IFS= read -r model; do
    MODELS+=("$model")
  done < <(provider_model_options "$PROVIDER")
  MODEL="$(choose_from_list "Select model:" default "${MODELS[@]}")"
  if [ "$MODEL" = "custom" ]; then
    MODEL="$(prompt_text "Model name" "")"
    [ -n "$MODEL" ] || die "model name cannot be empty"
  fi
fi

if [ "$MODEL" = "default" ]; then
  MODEL=""
fi

if [ -z "$EFFORT" ]; then
  EFFORTS=()
  while IFS= read -r effort; do
    EFFORTS+=("$effort")
  done < <(provider_effort_options "$PROVIDER")
  EFFORT="$(choose_from_list "Select thinking level:" default "${EFFORTS[@]}")"
  if [ "$EFFORT" = "custom" ]; then
    EFFORT="$(prompt_text "Thinking level" "")"
    [ -n "$EFFORT" ] || die "thinking level cannot be empty"
  fi
fi

if [ "$EFFORT" = "default" ]; then
  EFFORT=""
fi

if [ "$MODE" = "afk" ]; then
  if [ -z "$ITERATIONS" ]; then
    ITERATIONS="$(prompt_text "Iterations" "10")"
  fi
  [[ "$ITERATIONS" =~ ^[0-9]+$ ]] && [ "$ITERATIONS" -gt 0 ] || die "iterations must be a positive integer"

  if [ -z "$NO_OVERSEE" ]; then
    OVERSEE_CHOICE="$(choose_from_list "Overseer:" on on off)"
    [ "$OVERSEE_CHOICE" = "off" ] && NO_OVERSEE=1
  fi
fi

echo ""
echo "======= RALPH CLI ======="
echo "PRD:        $PRD_NAME"
echo "Mode:       $MODE"
echo "Provider:   $PROVIDER"
echo "Model:      ${MODEL:-provider default}"
echo "Thinking:   ${EFFORT:-provider default}"
if [ "$MODE" = "afk" ]; then
  echo "Iterations: $ITERATIONS"
  echo "Overseer:   $([ -n "$NO_OVERSEE" ] && echo off || echo on)"
fi
echo "========================="
echo ""

export RALPH_PROVIDER="$PROVIDER"
if [ -n "$MODEL" ]; then
  export RALPH_MODEL="$MODEL"
else
  unset RALPH_MODEL
fi
if [ -n "$EFFORT" ]; then
  export RALPH_EFFORT="$EFFORT"
else
  unset RALPH_EFFORT
fi
if [ -n "$NO_OVERSEE" ]; then
  export RALPH_NO_OVERSEE=1
fi

case "$MODE" in
  once)
    exec bash "$SCRIPT_DIR/once.sh" "$PRD_NAME"
    ;;
  afk)
    exec bash "$SCRIPT_DIR/afk.sh" "$PRD_NAME" "$ITERATIONS"
    ;;
esac
