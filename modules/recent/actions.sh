#!/usr/bin/env bash
# recent actions

# recent::action edit <path...>: open in $EDITOR (foreground)
recent::action() {
  case "${1:-}" in
    edit)
      shift
      (($#)) || return 0
      "${EDITOR:-vi}" -- "$@"
      ;;
    *)
      printf 'recent: unknown action: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && recent::action "$@"
