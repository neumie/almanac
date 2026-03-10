#!/usr/bin/env bash
# install.sh — Install almanac for a specific provider

_install_claude_code() {
  local settings_file="$HOME/.claude/settings.json"
  local hook_script="$ALMANAC_HOME/providers/claude-code/hooks/session-start"

  [[ -d "$HOME/.claude" ]] || _die "~/.claude not found — is Claude Code installed?"
  [[ -x "$hook_script" ]] || chmod +x "$hook_script"

  # Add SessionStart hook to settings.json
  [[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

  python3 -c "
import json

with open('$settings_file', 'r') as f:
    data = json.load(f)

hooks = data.setdefault('hooks', {})
session_hooks = hooks.setdefault('SessionStart', [])

# Check if almanac hook already exists
already_installed = any(
    'almanac' in hh.get('command', '')
    for h in session_hooks if isinstance(h, dict)
    for hh in h.get('hooks', [])
)

if not already_installed:
    session_hooks.append({
        'hooks': [{
            'type': 'command',
            'command': '$hook_script'
        }]
    })

with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  _success "Installed almanac for Claude Code"
  _info "Hook added to ~/.claude/settings.json"
  _info "Restart Claude Code to activate"
}

_install_symlink() {
  local provider="$1"
  local readme="$ALMANAC_HOME/providers/$provider/README.md"
  if [[ -f "$readme" ]]; then
    _info "Follow the setup instructions:"
    echo ""
    cat "$readme"
  else
    _warn "No setup instructions for $provider"
  fi
}

# --- main ---

PROVIDER="${1:-}"
[[ -z "$PROVIDER" ]] && _die "Usage: almanac install <provider>"

PROVIDER_DIR="$ALMANAC_HOME/providers/$PROVIDER"
[[ -d "$PROVIDER_DIR" ]] || _die "Unknown provider: $PROVIDER (run 'almanac list')"

case "$PROVIDER" in
  claude-code)
    _install_claude_code
    ;;
  opencode|cursor|codex)
    _install_symlink "$PROVIDER"
    ;;
  *)
    _die "No installer for provider: $PROVIDER"
    ;;
esac
