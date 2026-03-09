#!/usr/bin/env bash
# install.sh — Bootstrap almanac CLI into ~/.almanac
set -euo pipefail

ALMANAC_HOME="$HOME/.almanac"
REPO_URL="https://github.com/neumie/almanac.git"

echo "Installing almanac..."

# Clone or update
if [[ -d "$ALMANAC_HOME" ]]; then
  git -C "$ALMANAC_HOME" pull --ff-only
else
  git clone "$REPO_URL" "$ALMANAC_HOME"
fi

# Make CLI executable
chmod +x "$ALMANAC_HOME/bin/almanac"

# Add to PATH if not already there
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]] && ! grep -q 'almanac/bin' "$SHELL_RC" 2>/dev/null; then
  echo '' >> "$SHELL_RC"
  echo '# Almanac' >> "$SHELL_RC"
  echo 'export PATH="$HOME/.almanac/bin:$PATH"' >> "$SHELL_RC"
  echo "Added ~/.almanac/bin to PATH in $SHELL_RC"
fi

echo ""
echo "Done! Run 'source $SHELL_RC' or open a new terminal, then:"
echo "  almanac install claude-code"
