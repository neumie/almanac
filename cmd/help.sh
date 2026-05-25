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
echo "  ralph                  Launch the interactive Ralph loop CLI"
echo "  harden <target>        Fan out read-only reviewers (one per lens), aggregate findings"
echo "  harden <target> --goal Draft a harden-loop rubric for a target"
echo "  update                 Update almanac (git pull)"
echo "  sync                   Check adapted skills for upstream changes"
echo "  help                   Show this help"
