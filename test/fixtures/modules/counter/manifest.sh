#!/usr/bin/env bash
# counter menu entries. COUNTER_HIDE_TWO hides the second entry; COUNTER_SUMMARY_SLEEP and
# COUNTER_SUMMARY_FAIL make the summary slow or failing; each summary run is counted in
# $COUNTER_FILE.summaries. COUNTER_SUMMARY_PROBE: the file each summary writes "pgid sid tty" of itself to.

counter::manifest() {
  fzx::entry counter "Counter in its first mode"
  fzx::entry counter:two "Counter in mode two" --x "a b"
}

counter::applicable() {
  [[ "$1" != counter:two || -z "${COUNTER_HIDE_TWO:-}" ]]
}

counter::summary() {
  printf '%s\n' "$1" >> "$COUNTER_FILE.summaries"
  [[ -n "${COUNTER_SUMMARY_PROBE:-}" ]] && ps -o pgid=,sid=,tty= -p "$BASHPID" >> "$COUNTER_SUMMARY_PROBE"
  [[ -n "${COUNTER_SUMMARY_SLEEP:-}" ]] && sleep "$COUNTER_SUMMARY_SLEEP"
  [[ -n "${COUNTER_SUMMARY_FAIL:-}" ]] && return 1
  printf 'summary of %s\n' "$*"
}
