#!/usr/bin/env bash
# ps menu entries

ps::manifest() {
  fzx::entry ps "Your processes, busiest first"
  fzx::entry ps:all "All processes, busiest first"
  fzx::entry ps:tree "Process tree"
}

# ps::summary <target>: process counts straight from /proc (no ps scan, no fork per process)
ps::summary() {
  local dir n=0 mine=0
  for dir in /proc/[0-9]*; do
    n=$((n + 1))
    [[ -O "$dir" ]] && mine=$((mine + 1))
  done
  case "$1" in
    ps) printf '%s of yours, %s total\n' "$mine" "$n" ;;
    *) printf '%s processes\n' "$n" ;;
  esac
}
