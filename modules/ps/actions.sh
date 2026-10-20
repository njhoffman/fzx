#!/usr/bin/env bash
# ps actions: signal processes.

# ps::action <term|kill> <pid...>
ps::action() {
  local action="${1:-}" pid
  shift
  (($#)) || {
    printf 'ps: %s: no pids given\n' "$action" >&2
    return 2
  }
  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || {
      printf 'ps: not a pid: %s\n' "$pid" >&2
      return 2
    }
  done

  case "$action" in
    term) kill -TERM -- "$@" ;;
    kill) kill -KILL -- "$@" ;;
    *)
      printf 'ps: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::action "$@"
