#!/usr/bin/env bash
# help.sh — Show almanac CLI usage

echo -e "${_BOLD}almanac${_RESET} — agent toolkit CLI"
echo ""
echo "Usage: almanac <command> [args]"
echo ""
echo "Commands:"
echo "  install <provider>     Install almanac for a provider (e.g. claude-code)"
echo "  uninstall <provider>   Remove almanac from a provider"
echo "  list                   List available providers"
echo "  update                 Update almanac (git pull)"
echo "  sync                   Check adapted skills for upstream changes"
echo "  help                   Show this help"
