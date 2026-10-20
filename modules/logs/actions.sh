#!/usr/bin/env bash
# logs actions

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# logs::action follow <kind> <target>: runs in the foreground (fzf execute); ctrl-c returns to the list
logs::action() {
  case "${1:-}" in
    follow)
      trap : INT
      logs::show "${2:-}" "${3:-}" 1
      return 0
      ;;
    *)
      printf 'logs: unknown action: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && logs::action "$@"
