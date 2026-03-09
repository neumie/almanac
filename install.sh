#!/usr/bin/env bash
# install.sh — Bootstrap almanac CLI into ~/.almanac
set -euo pipefail

ALMANAC_HOME="$HOME/.almanac"
REPO_URL="https://github.com/neumie/almanac.git"

# Add to PATH first — safe to do even if git operations fail below
_setup_path() {
  local shell_rc=""
  if [[ -f "$HOME/.zshrc" ]]; then
    shell_rc="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    shell_rc="$HOME/.bashrc"
  fi

  if [[ -z "$shell_rc" ]]; then
    echo "Warning: No .zshrc or .bashrc found. Add ~/.almanac/bin to your PATH manually."
    return
  fi

  if ! grep -q 'almanac/bin' "$shell_rc" 2>/dev/null; then
    echo '' >> "$shell_rc"
    echo '# Almanac' >> "$shell_rc"
    echo 'export PATH="$HOME/.almanac/bin:$PATH"' >> "$shell_rc"
    echo "Added ~/.almanac/bin to PATH in $shell_rc"
  fi
}

_setup_path

echo "Installing almanac..."

# Clone or update
if [[ -d "$ALMANAC_HOME" ]]; then
  git -C "$ALMANAC_HOME" pull --ff-only 2>/dev/null || {
    echo "Warning: Could not fast-forward ~/.almanac. Run 'git -C ~/.almanac pull' manually."
  }
else
  git clone "$REPO_URL" "$ALMANAC_HOME"
fi

# Make CLI executable
chmod +x "$ALMANAC_HOME/bin/almanac"

echo ""
echo "Done! Open a new terminal, then:"
echo "  almanac install claude-code"
