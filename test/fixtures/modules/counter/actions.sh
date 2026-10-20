#!/usr/bin/env bash
# counter actions: record the call in $COUNTER_FILE.actions

counter::action() {
  printf '%s\n' "$*" >> "$COUNTER_FILE.actions"
  printf 'action stderr\n' >&2
  [[ "$1" != fail ]]
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && counter::action "$@"
