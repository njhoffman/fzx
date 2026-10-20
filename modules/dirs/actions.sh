#!/usr/bin/env bash
# dirs actions

# dirs::action remove <path...>: forget directories in the current mode's database
dirs::action() {
  local action="${1:-}" dir
  shift
  case "$action:${FZX_MODE:-frecent}" in
    remove:frecent) for dir in "$@"; do command zoxide remove -- "$dir"; done ;;
    remove:fasd | remove:recent) command fasd -D "$@" ;;
    remove:bookmarks) printf 'dirs: bookmarks come from FZX_DIRS_BOOKMARKS in config\n' >&2 ;;
    *)
      printf 'dirs: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && dirs::action "$@"
