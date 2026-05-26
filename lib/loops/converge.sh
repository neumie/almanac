#!/usr/bin/env bash
# lib/loops/converge.sh - converge loop adapter.
#
# Converge launches directly through `almanac converge --goal ... --exec ...` in
# v1, so this adapter only declares the generic hub control contract.

almanac_loop_converge_signal_file() {
  case "$1" in
    stop)  printf '%s\n' ".converge-stop" ;;
    steer) printf '%s\n' ".converge-steer" ;;
    *) return 1 ;;
  esac
}
