#!/usr/bin/env bash
# files actions

# files::action edit <path...> | (grep mode) edit <path> <line>: open in $EDITOR (foreground)
files::action() {
  local action="${1:-}"
  shift
  case "$action:${FZX_MODE:-files}" in
    edit:grep) "${EDITOR:-vi}" "+${2:-1}" -- "$1" ;;
    edit:*)
      (($#)) || return 0
      "${EDITOR:-vi}" -- "$@"
      ;;
    *)
      printf 'files: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && files::action "$@"
